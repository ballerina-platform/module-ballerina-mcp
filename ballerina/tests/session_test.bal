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

import ballerina/test;

isolated class SessionCounter {
    private int count = 0;

    isolated function increment() {
        lock {
            self.count += 1;
        }
    }

    isolated function value() returns int {
        lock {
            return self.count;
        }
    }
}

type SessionProfile record {|
    string name;
    int visits;
|};

@test:Config {}
function testSessionIdAndEmptyState() {
    HttpSession session = new ("session-1");
    test:assertEquals(session.getSessionId(), "session-1");
    test:assertTrue(session.isEmpty());
    test:assertEquals(session.size(), 0);
    test:assertEquals(session.keys(), []);
    test:assertFalse(session.hasKey("missing"));
}

@test:Config {}
function testSessionStoresClonedValues() {
    HttpSession session = new ("session-2");
    SessionProfile profile = {name: "alice", visits: 1};
    session.set("profile", profile);
    profile.visits = 99;

    HttpSessionEntry storedEntry = session.get("profile");
    test:assertTrue(storedEntry is SessionProfile);
    if storedEntry is SessionProfile {
        // The session took a copy, so the caller's later mutation is not visible.
        test:assertEquals(storedEntry.visits, 1);
        storedEntry.visits = 42;
    }
    SessionProfile reRead = <SessionProfile>session.get("profile");
    test:assertEquals(reRead.visits, 1);
}

@test:Config {}
function testSessionStoresIsolatedObjectsByReference() {
    HttpSession session = new ("session-3");
    SessionCounter counter = new;
    session.set("counter", counter);

    HttpSessionEntry storedEntry = session.get("counter");
    test:assertTrue(storedEntry is SessionCounter);
    if storedEntry is SessionCounter {
        storedEntry.increment();
    }
    // Isolated objects are shared, not cloned.
    test:assertEquals(counter.value(), 1);
}

@test:Config {}
function testSessionKeysSizeAndClear() {
    HttpSession session = new ("session-4");
    session.set("a", 1);
    session.set("b", "two");
    int[] numbers = [1, 2, 3];
    session.set("c", numbers);

    test:assertEquals(session.size(), 3);
    test:assertFalse(session.isEmpty());
    test:assertEquals(session.keys().sort(), ["a", "b", "c"]);
    test:assertTrue(session.hasKey("b"));

    session.set("a", 10);
    test:assertEquals(session.get("a"), 10);
    test:assertEquals(session.size(), 3);

    session.remove("b");
    test:assertFalse(session.hasKey("b"));
    test:assertEquals(session.size(), 2);

    session.clear();
    test:assertTrue(session.isEmpty());
    test:assertEquals(session.keys(), []);
}

@test:Config {}
function testSessionGetAndRemovePanicOnMissingKey() {
    HttpSession session = new ("session-5");
    HttpSessionEntry|error missingGet = trap session.get("absent");
    test:assertTrue(missingGet is error);
    error? missingRemove = trap session.remove("absent");
    test:assertTrue(missingRemove is error);
}

@test:Config {}
function testSessionGetWithType() {
    HttpSession session = new ("session-6");
    session.set("count", 7);
    session.set("profile", <SessionProfile>{name: "bob", visits: 3});

    int|Error countValue = session.getWithType("count");
    test:assertEquals(countValue, 7);

    SessionProfile|Error profileValue = session.getWithType("profile");
    test:assertTrue(profileValue is SessionProfile);
    if profileValue is SessionProfile {
        test:assertEquals(profileValue.name, "bob");
    }

    string|Error wrongType = session.getWithType("count");
    test:assertTrue(wrongType is Error);
    if wrongType is Error {
        test:assertTrue(wrongType.message().includes("type conversion failed"));
    }

    int|Error absentValue = session.getWithType("absent");
    test:assertTrue(absentValue is Error);
    if absentValue is Error {
        test:assertTrue(absentValue.message().includes("no member found"));
    }
}
