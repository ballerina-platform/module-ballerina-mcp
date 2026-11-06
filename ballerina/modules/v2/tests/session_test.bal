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

import ballerina/http;
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

    if profileValue is SessionProfile {
        // The value is a copy, so mutating it leaves the stored entry unchanged.
        profileValue.visits = 99;
        SessionProfile|Error reRead = session.getWithType("profile");
        test:assertEquals(reRead, <SessionProfile>{name: "bob", visits: 3});
    }

    SessionCounter counter = new;
    session.set("counter", counter);
    SessionCounter|Error sharedCounter = session.getWithType("counter");
    test:assertTrue(sharedCounter === counter);

    int|Error absentValue = session.getWithType("absent");
    test:assertTrue(absentValue is Error);
    if absentValue is Error {
        test:assertTrue(absentValue.message().includes("no member found"));
    }
}

isolated decimal fakeSessionNow = 0;

isolated function fakeSessionClock() returns decimal {
    lock {
        return fakeSessionNow;
    }
}

isolated function advanceFakeSessionClock(decimal seconds) {
    lock {
        fakeSessionNow += seconds;
    }
}

@test:Config {}
function testSessionStoreEvictsIdleSessions() {
    SessionStore store = new ({idleTimeoutSeconds: 60}, fakeSessionClock);
    string activeId = (<HttpSession>store.create(())).getSessionId();
    string idleId = (<HttpSession>store.create(())).getSessionId();

    advanceFakeSessionClock(59);
    // Using a session restarts its idle timer.
    test:assertTrue(store.access(activeId, ()) is HttpSession);
    advanceFakeSessionClock(1);
    test:assertTrue(store.access(idleId, ()) is ());
    test:assertFalse(store.contains(idleId));
    test:assertTrue(store.contains(activeId));

    advanceFakeSessionClock(60);
    test:assertFalse(store.remove(activeId, ()));
}

@test:Config {}
function testSessionStoreCapsSessionsPerOwner() {
    SessionStore store = new ({idleTimeoutSeconds: 60, maxPerOwner: 2, maxAnonymous: 1}, fakeSessionClock);
    test:assertTrue(store.create("alice") is HttpSession);
    test:assertTrue(store.create("alice") is HttpSession);
    test:assertTrue(store.create("alice") is ());
    // Other principals and anonymous callers are not affected by one owner reaching its cap.
    test:assertTrue(store.create("bob") is HttpSession);
    test:assertTrue(store.create(()) is HttpSession);
    test:assertTrue(store.create(()) is ());

    // Idle sessions are evicted on the next initialize, freeing room.
    advanceFakeSessionClock(60);
    test:assertTrue(store.create("alice") is HttpSession);
    test:assertTrue(store.create(()) is HttpSession);
}

@test:Config {}
function testSessionCapAndIdleEvictionOverHttp() returns error? {
    http:Listener httpListener = check new (3242);
    DispatcherService dispatcher = getDispatcherService({}, (), check new ({}),
            new ({idleTimeoutSeconds: 60, maxAnonymous: 1}, fakeSessionClock));
    check addMcpServiceToDispatcher(dispatcher, newUnconfiguredService());
    check httpListener.attach(dispatcher, "/capped");
    check httpListener.'start();
    error? assertionResult = trap assertSessionCapAndIdleEviction();
    check httpListener.immediateStop();
    return assertionResult;
}

isolated function assertSessionCapAndIdleEviction() returns error? {
    http:Client cappedClient = check new ("http://localhost:3242");
    json initRequest = legacyRequest(REQUEST_INITIALIZE, {
        "protocolVersion": LATEST_LEGACY_PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": "capped-test", "version": "1"}
    });
    http:Response first = check cappedClient->post("/capped", initRequest, headers = legacyHeaders());
    test:assertEquals(first.statusCode, 200);
    string sessionId = check first.getHeader(SESSION_ID_HEADER);

    http:Response overCap = check cappedClient->post("/capped", initRequest, headers = legacyHeaders());
    test:assertEquals(overCap.statusCode, 503);
    JsonRpcError capError = check (check overCap.getJsonPayload()).cloneWithType();
    test:assertEquals(capError.id, 1);

    advanceFakeSessionClock(60);
    http:Response evicted = check cappedClient->post("/capped", legacyRequest(REQUEST_LIST_TOOLS),
            headers = legacyHeaders({[SESSION_ID_HEADER]: sessionId}));
    test:assertEquals(evicted.statusCode, 404);

    http:Response replacement = check cappedClient->post("/capped", initRequest, headers = legacyHeaders());
    test:assertEquals(replacement.statusCode, 200);
}
