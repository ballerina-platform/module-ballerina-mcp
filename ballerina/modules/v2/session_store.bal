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
import ballerina/uuid;

type SessionEntry record {|
    HttpSession session;
    # Principal that created the session, when the caller could be identified
    string? owner;
    decimal lastSeen;
|};

# Holds the legacy sessions of a service, evicting idle ones and bounding how many may exist.
# A full pool evicts its least recently used session rather than refusing new ones, so no caller can
# hold all of the room by keeping its sessions alive.
isolated class SessionStore {
    private final map<SessionEntry> entries = {};
    private final readonly & SessionLimits limits;
    private final isolated function () returns decimal clock;

    isolated function init(SessionLimits limits = {}, isolated function () returns decimal clock = time:monotonicNow) {
        self.limits = limits.cloneReadOnly();
        self.clock = clock;
    }

    # Creates a session for the given owner, evicting the owner's least recently used session if its pool is full.
    #
    # + owner - Principal the session belongs to, or `()` for an anonymous session
    # + return - The new session
    isolated function create(string? owner) returns HttpSession {
        lock {
            decimal now = self.clock();
            int ownedSessions = 0;
            string leastRecentlyUsed = "";
            // Later than any session was used, so the first owned session is taken.
            decimal leastRecentlyUsedAt = now + 1d;
            foreach [string, SessionEntry] [sessionId, entry] in self.entries.entries() {
                if self.isExpired(entry.lastSeen, now) {
                    _ = self.entries.remove(sessionId);
                } else if entry.owner == owner {
                    ownedSessions += 1;
                    if entry.lastSeen < leastRecentlyUsedAt {
                        leastRecentlyUsed = sessionId;
                        leastRecentlyUsedAt = entry.lastSeen;
                    }
                }
            }
            int cap = owner is string ? self.limits.maxPerOwner : self.limits.maxAnonymous;
            if ownedSessions >= cap {
                _ = self.entries.removeIfHasKey(leastRecentlyUsed);
            }
            string sessionId = uuid:createRandomUuid();
            HttpSession session = new (sessionId);
            self.entries[sessionId] = {session, owner, lastSeen: now};
            return session;
        }
    }

    # Returns a live session the caller may use, and marks it as used.
    #
    # + sessionId - The session ID
    # + caller - Principal of the caller, if it could be identified
    # + return - The session, or `()` if it is unknown, expired, or owned by another principal
    isolated function access(string sessionId, string? caller) returns HttpSession? {
        lock {
            self.evictIfExpired(sessionId);
            SessionEntry? entry = self.entries[sessionId];
            if entry is () || !isSessionOwner(entry.owner, caller) {
                return ();
            }
            entry.lastSeen = self.clock();
            return entry.session;
        }
    }

    # Returns whether a live session with the given ID exists, whoever owns it.
    #
    # + sessionId - The session ID
    # + return - `true` if the session exists
    isolated function contains(string sessionId) returns boolean {
        lock {
            self.evictIfExpired(sessionId);
            return self.entries.hasKey(sessionId);
        }
    }

    # Removes a session the caller may use.
    #
    # + sessionId - The session ID
    # + caller - Principal of the caller, if it could be identified
    # + return - `true` if the session was removed, `false` if it is unknown, expired, or owned by another principal
    isolated function remove(string sessionId, string? caller) returns boolean {
        lock {
            self.evictIfExpired(sessionId);
            SessionEntry? entry = self.entries[sessionId];
            if entry is () || !isSessionOwner(entry.owner, caller) {
                return false;
            }
            _ = self.entries.remove(sessionId);
            return true;
        }
    }

    private isolated function evictIfExpired(string sessionId) {
        lock {
            SessionEntry? entry = self.entries[sessionId];
            if entry is SessionEntry && self.isExpired(entry.lastSeen, self.clock()) {
                _ = self.entries.remove(sessionId);
            }
        }
    }

    private isolated function isExpired(decimal lastSeen, decimal now) returns boolean =>
        now - lastSeen >= self.limits.idleTimeout;
}
