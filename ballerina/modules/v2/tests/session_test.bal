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
    SessionStore store = new ({idleTimeout: 60}, fakeSessionClock);
    string activeId = store.create(()).getSessionId();
    string idleId = store.create(()).getSessionId();

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
function testFullOwnerPoolEvictsItsLeastRecentlyUsedSession() {
    SessionStore store = new ({idleTimeout: 60, maxPerOwner: 2}, fakeSessionClock);
    string first = store.create("alice").getSessionId();
    advanceFakeSessionClock(1);
    string second = store.create("alice").getSessionId();
    advanceFakeSessionClock(1);
    string bobs = store.create("bob").getSessionId();
    advanceFakeSessionClock(1);
    // Using the older session makes the second one the least recently used.
    test:assertTrue(store.access(first, "alice") is HttpSession);
    advanceFakeSessionClock(1);

    string third = store.create("alice").getSessionId();
    test:assertTrue(store.contains(first));
    test:assertFalse(store.contains(second));
    test:assertTrue(store.contains(third));
    // One owner's pool never evicts the sessions of another.
    test:assertTrue(store.contains(bobs));
}

@test:Config {}
function testFullAnonymousPoolEvictsItsLeastRecentlyUsedSession() {
    SessionStore store = new ({idleTimeout: 60, maxPerOwner: 1, maxAnonymous: 2}, fakeSessionClock);
    string owned = store.create("alice").getSessionId();
    string first = store.create(()).getSessionId();
    advanceFakeSessionClock(1);
    string second = store.create(()).getSessionId();
    advanceFakeSessionClock(1);

    // Callers that keep their sessions alive cannot keep a new caller out.
    string third = store.create(()).getSessionId();
    test:assertFalse(store.contains(first));
    test:assertTrue(store.contains(second));
    test:assertTrue(store.contains(third));
    test:assertTrue(store.contains(owned));
}

@test:Config {}
function testSessionEvictionOverHttp() returns error? {
    http:Listener httpListener = check new (3242);
    DispatcherService dispatcher = getDispatcherService({}, (), check new ({}),
            new ({idleTimeout: 60, maxAnonymous: 1}, fakeSessionClock));
    check addMcpServiceToDispatcher(dispatcher, newUnconfiguredService());
    check httpListener.attach(dispatcher, "/capped");
    check httpListener.'start();
    error? assertionResult = trap assertSessionEviction();
    check httpListener.immediateStop();
    return assertionResult;
}

isolated function assertSessionEviction() returns error? {
    http:Client cappedClient = check new ("http://localhost:3242");
    json initRequest = legacyRequest(REQUEST_INITIALIZE, {
        "protocolVersion": LATEST_LEGACY_PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": "capped-test", "version": "1"}
    });
    http:Response first = check cappedClient->post("/capped", initRequest, headers = legacyHeaders());
    test:assertEquals(first.statusCode, 200);
    string firstId = check first.getHeader(SESSION_ID_HEADER);

    // A full pool admits the new session and evicts the old one, whose client must initialize again.
    http:Response second = check cappedClient->post("/capped", initRequest, headers = legacyHeaders());
    test:assertEquals(second.statusCode, 200);
    string secondId = check second.getHeader(SESSION_ID_HEADER);
    http:Response evicted = check cappedClient->post("/capped", legacyRequest(REQUEST_LIST_TOOLS),
            headers = legacyHeaders({[SESSION_ID_HEADER]: firstId}));
    test:assertEquals(evicted.statusCode, 404);

    advanceFakeSessionClock(60);
    http:Response idle = check cappedClient->post("/capped", legacyRequest(REQUEST_LIST_TOOLS),
            headers = legacyHeaders({[SESSION_ID_HEADER]: secondId}));
    test:assertEquals(idle.statusCode, 404);
}

@test:Config {}
function testInvalidSessionLimitsAreRejectedOnAttach() returns error? {
    StreamableHttpListener unstartedListener = check new (3243);
    StreamableHttpAdvancedService noIdleTimeout = @StreamableHttpServiceConfig {
        info: {name: "limited", version: "1"},
        sessionLimits: {idleTimeout: 0}
    } isolated service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
    };
    StreamableHttpAdvancedService noOwnedSessions = @StreamableHttpServiceConfig {
        info: {name: "limited", version: "1"},
        sessionLimits: {maxPerOwner: 0}
    } isolated service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
    };
    StreamableHttpAdvancedService noAnonymousSessions = @StreamableHttpServiceConfig {
        info: {name: "limited", version: "1"},
        sessionLimits: {maxAnonymous: -1}
    } isolated service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
    };
    foreach StreamableHttpAdvancedService limitedService in [noIdleTimeout, noOwnedSessions, noAnonymousSessions] {
        Error? attachResult = unstartedListener.attach(limitedService, "/limited");
        if attachResult !is Error {
            test:assertFail("expected the session limits to be rejected");
        }
        test:assertEquals(attachResult.message(), "Session limits must be positive");
    }
}
