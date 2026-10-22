// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/time;

// Bounds the per-page fetch order kept for servers whose cursors change on every listing.
const FETCH_ORDER_LIMIT = 1024;

type CachedResult record {|
    string method;
    Result & readonly resultValue;
    decimal expiresAt;
|};

# Holds results reused across calls of one client: results that are still fresh according to their
# caching hints, and the tool schemas needed to mirror tool arguments into request headers. A client
# represents a single authorization context, so its entries are never shared with another client.
isolated class ResultCache {
    private final boolean enabled;
    private final decimal maxTtlSeconds;
    private final int maxEntries;
    private final isolated function () returns decimal clock;
    // Iterated in insertion order, so a hit is re-inserted to keep the least recently used entry first.
    private map<CachedResult> entries = {};
    private map<ToolInfo> toolSchemas = {};
    // Fetches are numbered as they start. A fetch is stale if it started before the last invalidation, or
    // before the most recent fetch of the same page that completed.
    private int lastFetch = 0;
    private int invalidatedThrough = 0;
    private map<int> latestCompletedFetch = {};

    isolated function init(ResultCacheConfig? config, isolated function () returns decimal clock = time:monotonicNow) {
        self.enabled = config is ResultCacheConfig;
        self.maxTtlSeconds = config is ResultCacheConfig ? <decimal>config.maxTtlMs / 1000 : 0;
        self.maxEntries = config is ResultCacheConfig ? config.maxEntries : 0;
        self.clock = clock;
    }

    // Returns a fresh cached result for the request, or `()` on a miss.
    isolated function get(string method, Cursor? cursor) returns Result? {
        if !self.enabled {
            return;
        }
        string entryKey = [method, cursor].toJsonString();
        decimal now = self.clock();
        lock {
            CachedResult? cachedEntry = self.entries.removeIfHasKey(entryKey);
            if cachedEntry is () || now >= cachedEntry.expiresAt {
                return;
            }
            self.entries[entryKey] = cachedEntry;
            return cachedEntry.resultValue;
        }
    }

    // Numbers a fetch as it starts; the number is passed back when its result is stored.
    isolated function beginFetch() returns int {
        lock {
            self.lastFetch += 1;
            return self.lastFetch;
        }
    }

    // Stores a result for as long as its hints keep it fresh, replacing the request's earlier entry. A stale
    // fetch stores nothing, and an accepted one is ordered even when its result is not kept.
    isolated function put(string method, Cursor? cursor, Result resultValue, int fetchNumber) {
        string entryKey = [method, cursor].toJsonString();
        anydata ttlValue = resultValue["ttlMs"];
        decimal ttlSeconds = ttlValue is int && ttlValue > 0 ? <decimal>ttlValue / 1000 : 0;
        if ttlSeconds > self.maxTtlSeconds {
            ttlSeconds = self.maxTtlSeconds;
        }
        decimal now = self.clock();
        Result & readonly storedResult = resultValue.cloneReadOnly();
        lock {
            if self.isStaleFetch(entryKey, fetchNumber) {
                return;
            }
            _ = self.latestCompletedFetch.removeIfHasKey(entryKey);
            self.latestCompletedFetch[entryKey] = fetchNumber;
            if self.latestCompletedFetch.length() > FETCH_ORDER_LIMIT {
                _ = self.latestCompletedFetch.remove(self.latestCompletedFetch.keys()[0]);
            }
            if !self.enabled {
                return;
            }
            _ = self.entries.removeIfHasKey(entryKey);
            foreach [string, CachedResult] [storedKey, storedEntry] in self.entries.entries() {
                if now >= storedEntry.expiresAt {
                    _ = self.entries.remove(storedKey);
                }
            }
            if ttlSeconds <= 0d || self.maxEntries == 0 {
                return;
            }
            self.entries[entryKey] = {method, resultValue: storedResult, expiresAt: now + ttlSeconds};
            if self.entries.length() > self.maxEntries {
                _ = self.entries.remove(self.entries.keys()[0]);
            }
        }
    }

    // Drops every cached result of a method, including all of its pages.
    isolated function invalidate(string method) {
        lock {
            self.markInvalidated();
            foreach [string, CachedResult] [storedKey, storedEntry] in self.entries.entries() {
                if storedEntry.method == method {
                    _ = self.entries.remove(storedKey);
                }
            }
            if method == REQUEST_LIST_TOOLS {
                self.toolSchemas = {};
            }
        }
    }

    isolated function clear() {
        lock {
            self.markInvalidated();
            self.entries = {};
            self.toolSchemas = {};
        }
    }

    isolated function toolSchema(string toolName) returns ToolInfo? {
        lock {
            return self.toolSchemas[toolName].clone();
        }
    }

    // Records the schemas of a fetched page unless the fetch is stale. Schemas are only removed by
    // invalidate() and clear(), so other pages' schemas survive.
    isolated function recordToolSchemas(Cursor? cursor, ToolInfo[] tools, int fetchNumber) {
        string entryKey = [REQUEST_LIST_TOOLS, cursor].toJsonString();
        lock {
            if self.isStaleFetch(entryKey, fetchNumber) {
                return;
            }
            foreach ToolInfo toolInfo in tools.clone() {
                self.toolSchemas[toolInfo.name] = toolInfo;
            }
        }
    }

    private isolated function isStaleFetch(string entryKey, int fetchNumber) returns boolean {
        lock {
            return fetchNumber <= self.invalidatedThrough || fetchNumber < (self.latestCompletedFetch[entryKey] ?: 0);
        }
    }

    // Every fetch started so far becomes stale; their completion order no longer matters.
    private isolated function markInvalidated() {
        lock {
            self.invalidatedThrough = self.lastFetch;
            self.latestCompletedFetch = {};
        }
    }
}
