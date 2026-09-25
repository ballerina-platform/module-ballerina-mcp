// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/test;

isolated class RecordingObserver {
    *ClientObserver;
    private (readonly & ClientEvent)[] eventList = [];

    public isolated function onEvent(readonly & ClientEvent clientEvent) {
        lock {
            self.eventList.push(clientEvent);
        }
    }

    isolated function getEvents() returns (readonly & ClientEvent)[] {
        lock {
            return self.eventList.clone();
        }
    }
}

isolated class PanickingObserver {
    *ClientObserver;

    public isolated function onEvent(readonly & ClientEvent clientEvent) {
        string eventUrl = clientEvent.eventUrl;
        panic error(string `Observer failed for '${eventUrl}'.`);
    }
}

function findEvent((readonly & ClientEvent)[] eventList, ClientEventType eventType,
        ClientEventTarget eventTarget) returns (readonly & ClientEvent)? {
    foreach readonly & ClientEvent clientEvent in eventList {
        if clientEvent.eventType == eventType && clientEvent.eventTarget == eventTarget {
            return clientEvent;
        }
    }
    return;
}

function countEvents((readonly & ClientEvent)[] eventList, ClientEventType eventType) returns int {
    int eventCount = 0;
    foreach readonly & ClientEvent clientEvent in eventList {
        if clientEvent.eventType == eventType {
            eventCount += 1;
        }
    }
    return eventCount;
}

function bodyContains((readonly & ClientEvent)[] eventList, string expectedText) returns boolean {
    foreach readonly & ClientEvent clientEvent in eventList {
        string? eventBody = clientEvent.eventBody;
        if eventBody is string && eventBody.includes(expectedText) {
            return true;
        }
    }
    return false;
}

@test:Config {}
function testObserverReceivesModernTransportEventsInOrder() returns error? {
    RecordingObserver eventObserver = new;
    StreamableHttpClient observedClient = check new (mockUrl("ok"),
        protocolMode = "modern", observer = eventObserver);

    _ = check observedClient->connect();
    _ = check observedClient->listTools();

    (readonly & ClientEvent)[] eventList = eventObserver.getEvents();
    test:assertEquals(eventList.length(), 6);
    test:assertEquals(eventList[0].eventType, HTTP_REQUEST);
    test:assertEquals(eventList[1].eventType, HTTP_RESPONSE);
    test:assertEquals(eventList[2].eventType, MCP_MESSAGE);
    test:assertEquals(eventList[3].eventType, HTTP_REQUEST);
    test:assertEquals(eventList[4].eventType, HTTP_RESPONSE);
    test:assertEquals(eventList[5].eventType, MCP_MESSAGE);
    test:assertTrue(bodyContains(eventList, "server/discover"));
    test:assertTrue(bodyContains(eventList, "tools/list"));
}

@test:Config {}
function testObserverReceivesModernSseMessages() returns error? {
    RecordingObserver eventObserver = new;
    StreamableHttpClient observedClient = check new (mockUrl("sseNotificationThenResult"),
        protocolMode = "modern", observer = eventObserver);

    _ = check observedClient->connect();

    (readonly & ClientEvent)[] eventList = eventObserver.getEvents();
    test:assertEquals(countEvents(eventList, MCP_MESSAGE), 2);
    test:assertTrue(bodyContains(eventList, "notifications/progress"));
    test:assertTrue(bodyContains(eventList, MODERN_PROTOCOL_VERSION));
}

@test:Config {}
function testObserverFailureDoesNotInterruptClient() returns error? {
    PanickingObserver eventObserver = new;
    StreamableHttpClient observedClient = check new (mockUrl("ok"),
        protocolMode = "modern", observer = eventObserver);

    ConnectionInfo connectionInfo = check observedClient->connect();
    ListToolsResult toolList = check observedClient->listTools();

    test:assertEquals(connectionInfo.protocolVersion, MODERN_PROTOCOL_VERSION);
    test:assertEquals(toolList.tools.length(), 1);
}

@test:Config {}
function testAuthorizationLifecycleEventsRedactCallbackParameters() returns error? {
    RecordingObserver eventObserver = new;
    AuthorizationCodeGrant authorizationGrant = authorizationCodeGrant();
    readonly & AuthorizationCodeGrant readonlyGrant = authorizationGrant.cloneReadOnly();
    ClientOAuthProvider oauthProvider = check new (
        "https://mcp.example.com/mcp", {grant: readonlyGrant}, observer = eventObserver);
    readonly & DiscoveredContext discoveredContext = {
        metadata: authorizationCodeMetadata().cloneReadOnly(),
        resourceUri: "https://mcp.example.com/mcp",
        resourceScopes: [],
        clientId: "https://client.example.com/oauth/metadata.json"
    };

    Error? authorizationResult = oauthProvider.authorizeInteractively(
        readonlyGrant, discoveredContext, []);

    test:assertTrue(authorizationResult is OAuthAuthorizationError);
    (readonly & ClientEvent)[] eventList = eventObserver.getEvents();
    readonly & ClientEvent? redirectEvent = findEvent(eventList, AUTHORIZATION_REDIRECT, USER_AGENT);
    readonly & ClientEvent? callbackEvent = findEvent(eventList, AUTHORIZATION_CALLBACK, USER_AGENT);
    test:assertTrue(redirectEvent is readonly & ClientEvent);
    test:assertTrue(callbackEvent is readonly & ClientEvent);
    if callbackEvent is readonly & ClientEvent {
        test:assertTrue(callbackEvent.eventBody is ());
        test:assertFalse(callbackEvent.toString().includes("authorization-code"));
    }
}

@test:Config {}
function testTokenRequestEventsRedactCredentials() returns error? {
    RecordingObserver eventObserver = new;
    AuthorizationServerMetadata tokenMetadata = {
        issuer: "https://127.0.0.1:1",
        token_endpoint: "https://127.0.0.1:1/token",
        response_types_supported: ["code"],
        grant_types_supported: ["authorization_code"],
        token_endpoint_auth_methods_supported: [CLIENT_SECRET_POST]
    };
    map<string> tokenForm = {
        "grant_type": "authorization_code",
        "code": "secret-code",
        "code_verifier": "secret-verifier",
        "refresh_token": "secret-refresh",
        "access_token": "secret-access"
    };

    TokenResponse|Error tokenResult = requestToken(
        {clientSecret: "secret-client", authMethod: CLIENT_SECRET_POST}, tokenMetadata,
        "observer-client", tokenForm, {timeout: 1}, eventObserver);

    test:assertTrue(tokenResult is OAuthTokenError);
    (readonly & ClientEvent)[] eventList = eventObserver.getEvents();
    readonly & ClientEvent? requestEvent = findEvent(eventList, HTTP_REQUEST, AUTHORIZATION_SERVER);
    test:assertTrue(requestEvent is readonly & ClientEvent);
    if requestEvent is readonly & ClientEvent {
        string requestBody = requestEvent.eventBody ?: "";
        test:assertTrue(requestBody.includes(REDACTED_VALUE));
        test:assertFalse(requestBody.includes("secret-client"));
        test:assertFalse(requestBody.includes("secret-code"));
        test:assertFalse(requestBody.includes("secret-verifier"));
        test:assertFalse(requestBody.includes("secret-refresh"));
        test:assertFalse(requestBody.includes("secret-access"));
    }
}

@test:Config {}
function testSensitiveHeadersAreRedactedCaseInsensitively() {
    map<string|string[]> sanitizedHeaders = sanitizedEventHeaders({
        "Authorization": "Bearer secret-token",
        "COOKIE": "session=secret-cookie",
        "X-Auth-Token": "secret-header-token",
        "X-Request-Id": "request-1"
    });

    test:assertEquals(sanitizedHeaders["Authorization"], [REDACTED_VALUE]);
    test:assertEquals(sanitizedHeaders["COOKIE"], [REDACTED_VALUE]);
    test:assertEquals(sanitizedHeaders["X-Auth-Token"], [REDACTED_VALUE]);
    test:assertEquals(sanitizedHeaders["X-Request-Id"], "request-1");
}

@test:Config {}
function testAuthorizationFailureEmitsClientError() returns error? {
    RecordingObserver eventObserver = new;
    StreamableHttpClient observedClient = check new (CHALLENGING_SERVER_URL,
        auth = preRegisteredConfig(), observer = eventObserver);

    var connectResult = observedClient->connect();
    test:assertTrue(connectResult is AuthorizationError);

    (readonly & ClientEvent)[] eventList = eventObserver.getEvents();
    test:assertTrue(eventList.length() > 0);
    readonly & ClientEvent lastEvent = eventList[eventList.length() - 1];
    test:assertEquals(lastEvent.eventType, CLIENT_ERROR);
    test:assertEquals(lastEvent.eventTarget, AUTHORIZATION_SERVER);
    test:assertTrue((lastEvent.eventMessage ?: "").includes("does not use HTTPS"));
}
