// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
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

import ballerina/jballerina.java;

// This is same as the `Cloneable`, except that it does not include `error` type.
# Represents a non-error type that can be cloned.
public type Cloneable (any & readonly)|xml|Cloneable[]|map<Cloneable>|table<map<Cloneable>>;

# Represents the type of a value stored in the `Session` object.
public type SessionEntry Cloneable|isolated object {};

# Represents an MCP session storage object used to maintain session state across requests.
public isolated class Session {
    private final map<SessionEntry> entries = {};
    private final string sessionId;

    # Creates a new MCP session with the given session ID.
    #
    # + sessionId - Unique identifier for the session
    public isolated function init(string sessionId) {
        self.sessionId = sessionId;
    }

    # Gets the session ID.
    #
    # + return - The session ID
    public isolated function getSessionId() returns string {
        return self.sessionId;
    }

    # Adds or updates an entry in the session.
    #
    # + key - Represents the entry key
    # + value - Represents the entry value
    public isolated function set(string key, SessionEntry value) {
        if value is Cloneable {
            lock {
                self.entries[key] = value.clone();
            }
        } else {
            lock {
                self.entries[key] = value;
            }
        }
    }

    # Retrieves a value from the session by key. Panics if the key does not exist.
    #
    # + key - The key identifying the entry
    # + return - The value associated with the key
    public isolated function get(string key) returns SessionEntry {
        lock {
            Cloneable|isolated object {} value = self.entries.get(key);
            if value is Cloneable {
                return value.clone();
            }
            return value;
        }
    }

    # Checks if the session contains an entry for the given key.
    #
    # + key - The key to check
    # + return - `true` if the entry exists, otherwise `false`
    public isolated function hasKey(string key) returns boolean {
        lock {
            return self.entries.hasKey(key);
        }
    }

    # Returns all the keys currently stored in the session.
    #
    # + return - An array of all entry keys
    public isolated function keys() returns string[] {
        lock {
            return self.entries.keys().clone();
        }
    }

    # Retrieves and casts a value from the session to the specified type.
    #
    # + key - The key identifying the entry
    # + targetType - The expected type of the entry
    # + return - The casted value or an error if the entry is missing or of the wrong type
    public isolated function getWithType(string key, typedesc<SessionEntry> targetType = <>)
    returns targetType|Error = @java:Method {
        'class: "io.ballerina.stdlib.mcp.Session"
    } external;

    # Removes the entry associated with the given key. Panics if the key does not exist.
    #
    # + key - The key identifying the entry to remove
    public isolated function remove(string key) {
        lock {
            SessionEntry|error err = trap self.entries.remove(key);
            if err is error {
                panic err;
            }
        }
    }

    # Gets the number of entries in the session.
    #
    # + return - The number of entries in the session
    public isolated function size() returns int {
        lock {
            return self.entries.length();
        }
    }

    # Clears all entries from the session.
    public isolated function clear() {
        lock {
            self.entries.removeAll();
        }
    }

    # Checks if the session is empty.
    #
    # + return - `true` if the session has no entries, otherwise `false`
    public isolated function isEmpty() returns boolean {
        lock {
            return self.entries.length() == 0;
        }
    }
}
