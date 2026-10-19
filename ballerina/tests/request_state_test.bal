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
import ballerina/jwt;
import ballerina/lang.runtime;
import ballerina/test;
import ballerina/uuid;

const REQUEST_STATE_SERVICE_URL = "http://localhost:3260";

listener StreamableHttpListener requestStateListener = check new (3260);

isolated function stateEchoTools() returns ListToolsResult => {
    tools: [{name: "remember", inputSchema: {'type: "object"}}, {name: "other", inputSchema: {'type: "object"}}]
};

// Returns state on the first round, then reports the state it received.
isolated function echoState(CallToolParams callParams) returns CallToolResult|InputRequiredResult {
    string? requestState = callParams.requestState;
    if requestState is () {
        return {requestState: "step-1"};
    }
    return {resultType: "complete", content: [{'type: "text", text: requestState}]};
}

@StreamableHttpConfig {info: {name: "request-state", version: "1"}}
service StreamableHttpAdvancedService /state on requestStateListener {
    remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
        echoState(callParams);
}

@StreamableHttpConfig {
    info: {name: "protected-request-state", version: "1"},
    httpConfig: {
        auth: {
            'resource: REQUEST_STATE_SERVICE_URL + "/protectedState",
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ]
        }
    }
}
service StreamableHttpAdvancedService /protectedState on requestStateListener {
    remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
        echoState(callParams);
}

isolated function callerToken(string audience, string? subject = "alice", string? clientId = ()) returns string|error {
    map<json> customClaims = {scope: "mcp:tools"};
    if clientId is string {
        customClaims[CLIENT_ID_CLAIM] = clientId;
    }
    return jwt:issue({
        issuer: PROTECTED_ISSUER,
        username: subject,
        audience,
        customClaims,
        signatureConfig: {algorithm: jwt:HS256, config: SIGNING_KEY}
    });
}

@StreamableHttpConfig {info: {name: "short-lived-state", version: "1"}, requestState: {ttl: 1}}
service StreamableHttpAdvancedService /shortLived on requestStateListener {
    remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

    // Completes on the third round; each round's state is the number of rounds so far.
    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult {
        int round = nextRound(callParams);
        if round < 3 {
            return {requestState: round.toString()};
        }
        return {resultType: "complete", content: [{'type: "text", text: round.toString()}]};
    }
}

// The same tool behind shared keys, with and without an auth context.
@StreamableHttpConfig {info: {name: "unbound-shared", version: "1"}, requestState: {keys: [SIGNING_KEY]}}
service StreamableHttpAdvancedService /unboundShared on requestStateListener {
    remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
        echoState(callParams);
}

@StreamableHttpConfig {
    info: {name: "bound-shared", version: "1"},
    requestState: {keys: [SIGNING_KEY]},
    httpConfig: {
        auth: {
            'resource: REQUEST_STATE_SERVICE_URL + "/boundShared",
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ]
        }
    }
}
service StreamableHttpAdvancedService /boundShared on requestStateListener {
    remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
        echoState(callParams);
}

final http:Client requestStateHttpClient = check new (REQUEST_STATE_SERVICE_URL);

isolated function postToolCall(string servicePath, string toolName, map<json> arguments = {},
        string? requestState = (), string? token = (), http:Client httpClient = requestStateHttpClient)
        returns json|error {
    map<json> callParams = {
        name: toolName,
        arguments,
        _meta: {[PROTOCOL_META_KEY]: MODERN_PROTOCOL_VERSION, [CAPABILITIES_META_KEY]: {}}
    };
    if requestState is string {
        callParams["requestState"] = requestState;
    }
    map<string> requestHeaders = {
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: MODERN_PROTOCOL_VERSION,
        [METHOD_HEADER]: REQUEST_CALL_TOOL,
        [NAME_HEADER]: encodeProtocolHeader(toolName)
    };
    if token is string {
        requestHeaders[AUTHORIZATION_HEADER] = "Bearer " + token;
    }
    json requestMessage = {jsonrpc: JSONRPC_VERSION, id: 9, method: REQUEST_CALL_TOOL, params: callParams};
    return httpClient->post(servicePath, requestMessage, headers = requestHeaders);
}

isolated function assertInvalidRequestState(json responseBody, string caseName) returns error? {
    test:assertEquals(responseBody.'error, {
        code: INVALID_PARAMS,
        message: "Invalid or expired requestState",
        data: {reason: "invalid_request_state"}
    }, caseName);
}

@test:Config {}
function testForgedRequestStateIsRejected() returns error? {
    json responseBody = check postToolCall("/state", "remember", requestState = "step-1");
    check assertInvalidRequestState(responseBody, "plain-text state");
}

isolated function issuedRequestState(string servicePath, string toolName, map<json> arguments = {},
        string? token = (), http:Client httpClient = requestStateHttpClient) returns string|error {
    json responseBody = check postToolCall(servicePath, toolName, arguments, token = token, httpClient = httpClient);
    return (check responseBody.result.requestState).ensureType();
}

isolated function completedText(json responseBody) returns string|error {
    json[] content = check (check responseBody.result.content).ensureType();
    return (check content[0].text).ensureType();
}

@test:Config {}
function testTamperedRequestStateIsRejected() returns error? {
    string issued = check issuedRequestState("/state", "remember");
    test:assertEquals(check completedText(check postToolCall("/state", "remember", requestState = issued)), "step-1");

    string[] parts = re `\.`.split(issued);
    string forgedPayload = {state: "step-9"}.toJsonString().toBytes().toBase64();
    map<string> tamperedStates = {
        "forged payload": string `${parts[0]}.${forgedPayload}.${parts[2]}`,
        "dropped signature": string `${parts[0]}.${parts[1]}`,
        "other version": string `v9.${parts[1]}.${parts[2]}`,
        "undecodable": "v1.***.***",
        "empty": ""
    };
    foreach [string, string] [caseName, tamperedState] in tamperedStates.entries() {
        check assertInvalidRequestState(check postToolCall("/state", "remember", requestState = tamperedState),
            caseName);
    }
}

@test:Config {}
function testRequestStateIsBoundToTheTool() returns error? {
    string issued = check issuedRequestState("/state", "remember");
    check assertInvalidRequestState(check postToolCall("/state", "other", requestState = issued), "another tool");
}

@test:Config {}
function testRequestStateIsBoundToTheArguments() returns error? {
    string issued = check issuedRequestState("/state", "remember",
        {path: "/tmp/a", options: {force: true, tags: ["x", "y"]}});

    json reordered = check postToolCall("/state", "remember", {options: {tags: ["x", "y"], force: true}, path: "/tmp/a"},
        requestState = issued);
    test:assertEquals(check completedText(reordered), "step-1", "key order must not matter");

    map<map<json>> changedArguments = {
        "changed value": {path: "/tmp/b", options: {force: true, tags: ["x", "y"]}},
        "changed nested value": {path: "/tmp/a", options: {force: false, tags: ["x", "y"]}},
        "reordered list": {path: "/tmp/a", options: {force: true, tags: ["y", "x"]}},
        "added argument": {path: "/tmp/a", options: {force: true, tags: ["x", "y"]}, extra: 1},
        "no arguments": {}
    };
    foreach [string, map<json>] [caseName, arguments] in changedArguments.entries() {
        check assertInvalidRequestState(check postToolCall("/state", "remember", arguments, issued), caseName);
    }
}

@test:Config {}
function testRequestStateIsBoundToTheCaller() returns error? {
    string audience = REQUEST_STATE_SERVICE_URL + "/protectedState";
    string aliceToken = check callerToken(audience, clientId = "desktop");
    string issued = check issuedRequestState("/protectedState", "remember", token = aliceToken);
    json sameCaller = check postToolCall("/protectedState", "remember", requestState = issued,
        token = check callerToken(audience, clientId = "desktop"));
    test:assertEquals(check completedText(sameCaller), "step-1", "a fresh token of the same caller");

    map<string> otherCallers = {
        "another subject": check callerToken(audience, "bob", "desktop"),
        "another client": check callerToken(audience, clientId = "mobile"),
        "no client": check callerToken(audience),
        "no subject": check callerToken(audience, (), "desktop")
    };
    foreach [string, string] [caseName, token] in otherCallers.entries() {
        check assertInvalidRequestState(check postToolCall("/protectedState", "remember", requestState = issued,
            token = token), caseName);
    }
}

isolated function newSharedKeyService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {info: {name: "replica", version: "1"}, requestState: {keys: [SIGNING_KEY]}}
    isolated service object {
        remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
            echoState(callParams);
    };

final string ROTATED_KEY = uuid:createType4AsString() + uuid:createType4AsString();

isolated function newRotatedKeyService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {info: {name: "replica", version: "1"}, requestState: {keys: [ROTATED_KEY, SIGNING_KEY]}}
    isolated service object {
        remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
            echoState(callParams);
    };

isolated function newDefaultKeyService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {info: {name: "replica", version: "1"}} isolated service object {
        remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
            echoState(callParams);
    };

// Issues state on one replica and continues on the other.
function continueOnAnotherReplica(function () returns StreamableHttpAdvancedService newService,
        function () returns StreamableHttpAdvancedService newOtherService = newService) returns json|error {
    StreamableHttpListener firstReplica = check new (3261);
    StreamableHttpListener secondReplica = check new (3262);
    check firstReplica.attach(newService(), "/replica");
    check secondReplica.attach(newOtherService(), "/replica");
    check firstReplica.'start();
    check secondReplica.'start();
    json|error continued = continueAcross("http://localhost:3261", "http://localhost:3262");
    check firstReplica.immediateStop();
    check secondReplica.immediateStop();
    return continued;
}

function continueAcross(string firstUrl, string secondUrl) returns json|error {
    string issued = check issuedRequestState("/replica", "remember", httpClient = check new (firstUrl));
    return postToolCall("/replica", "remember", requestState = issued, httpClient = check new (secondUrl));
}

@test:Config {}
function testReplicasSharingKeysAcceptEachOthersState() returns error? {
    test:assertEquals(check completedText(check continueOnAnotherReplica(newSharedKeyService)), "step-1");
    check assertInvalidRequestState(check continueOnAnotherReplica(newDefaultKeyService), "per-attach keys");
}

@test:Config {}
function testRequestStateSignedWithAnOlderKeyStillVerifies() returns error? {
    test:assertEquals(check completedText(check continueOnAnotherReplica(newSharedKeyService, newRotatedKeyService)),
        "step-1");
    check assertInvalidRequestState(check continueOnAnotherReplica(newRotatedKeyService, newSharedKeyService),
        "the first key signs");
}

@test:Config {}
function testInvalidRequestStateConfigurationFailsAtAttach() returns error? {
    StreamableHttpListener validationListener = check new (3263);
    map<[StreamableHttpAdvancedService, string]> invalidServices = {
        "short key": [newShortKeyService(), "at least 32 bytes"],
        "zero ttl": [newZeroTtlService(), "ttl must be positive"],
        "negative ttl": [newNegativeTtlService(), "ttl must be positive"]
    };
    foreach [string, [StreamableHttpAdvancedService, string]] [caseName, [invalidService, expected]]
            in invalidServices.entries() {
        Error? attachResult = validationListener.attach(invalidService, "/invalid");
        if attachResult !is Error {
            test:assertFail(caseName + " must fail at attach");
        }
        test:assertTrue(attachResult.message().includes(expected), caseName + ": " + attachResult.message());
    }
}

isolated function newShortKeyService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {info: {name: "invalid", version: "1"}, requestState: {keys: [SIGNING_KEY, "too-short"]}}
    isolated service object {
        remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
            echoState(callParams);
    };

isolated function newZeroTtlService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {info: {name: "invalid", version: "1"}, requestState: {ttl: 0}}
    isolated service object {
        remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
            echoState(callParams);
    };

isolated function newNegativeTtlService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {info: {name: "invalid", version: "1"}, requestState: {ttl: -1}}
    isolated service object {
        remote isolated function onListTools() returns ListToolsResult => stateEchoTools();

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult =>
            echoState(callParams);
    };

@test:Config {}
function testExpiredRequestStateIsRejected() returns error? {
    string issued = check issuedRequestState("/shortLived", "remember");
    runtime:sleep(1.2);
    check assertInvalidRequestState(check postToolCall("/shortLived", "remember", requestState = issued), "expired");
}

@test:Config {}
function testRequestStateExpiryIsRenewedEachRound() returns error? {
    string firstState = check issuedRequestState("/shortLived", "remember");
    runtime:sleep(0.7);
    json secondRound = check postToolCall("/shortLived", "remember", requestState = firstState);
    string secondState = check (check secondRound.result.requestState).ensureType();
    runtime:sleep(0.7);
    json lastRound = check postToolCall("/shortLived", "remember", requestState = secondState);
    test:assertEquals(check completedText(lastRound), "3");
}

@test:Config {}
function testBoundAndUnboundRequestStateAreNotInterchangeable() returns error? {
    string token = check callerToken(REQUEST_STATE_SERVICE_URL + "/boundShared");
    string unbound = check issuedRequestState("/unboundShared", "remember");
    check assertInvalidRequestState(check postToolCall("/boundShared", "remember", requestState = unbound,
        token = token), "unbound state on a bound call");

    string bound = check issuedRequestState("/boundShared", "remember", token = token);
    check assertInvalidRequestState(check postToolCall("/unboundShared", "remember", requestState = bound),
        "bound state on an unbound call");
    test:assertEquals(check completedText(check postToolCall("/unboundShared", "remember", requestState = unbound)),
        "step-1");
}

@test:Config {}
function testLegacyCallsDoNotPassRequestStateToAdvancedServices() returns error? {
    StreamableHttpClient legacyClient = check new (REQUEST_STATE_SERVICE_URL + "/state", protocolMode = "legacy");
    _ = check legacyClient->connect();
    CallToolResult|InputRequiredResult|ClientError callResult = legacyClient->callToolOnce({
        name: "remember",
        inputResponses: {"confirm": {action: "accept", content: {confirmed: true}}},
        requestState: "forged"
    });
    // Without the forged state, the handler asks for input, which legacy calls cannot carry.
    if callResult !is ClientError {
        test:assertFail("Expected the legacy input-required error, got " + callResult.toString());
    }
    test:assertTrue(callResult.message().includes("Input-required tool calls require modern MCP"),
        callResult.message());
    check legacyClient->close();
}
