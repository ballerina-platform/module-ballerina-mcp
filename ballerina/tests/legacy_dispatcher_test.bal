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

listener StreamableHttpListener legacyDispatcherListener = check new (3216);

@StreamableHttpConfig {info: {name: "stateful-legacy", version: "1"}, sessionMode: STATEFUL}
service StreamableHttpAdvancedService /stateful on legacyDispatcherListener {
    remote isolated function onListTools() returns ListToolsResult => {
        tools: [{name: "echo", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

// Binds every transport-specific parameter shape an advanced handler may declare.
@StreamableHttpConfig {info: {name: "session-aware", version: "1"}, sessionMode: STATEFUL}
service StreamableHttpAdvancedService /sessionAware on legacyDispatcherListener {
    remote isolated function onListTools(http:Request request, http:Headers headers) returns ListToolsResult => {
        tools: [{name: "whoami", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams, HttpSession session, http:Request request)
            returns CallToolResult {
        session.set("lastTool", callParams.name);
        return {
            content: [{'type: "text", text: string `${session.getSessionId()}:${request.rawPath}`}]
        };
    }
}

@StreamableHttpConfig {info: {name: "modern-only", version: "1"}, protocolMode: "modern"}
service StreamableHttpAdvancedService /modernOnly on legacyDispatcherListener {
    remote isolated function onListTools() returns ListToolsResult => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "stateless-legacy", version: "1"}, sessionMode: STATELESS}
service StreamableHttpAdvancedService /stateless on legacyDispatcherListener {
    remote isolated function onListTools() returns ListToolsResult => {
        tools: [{name: "ask", inputSchema: {'type: "object"}}]
    };

    // Input-required continuations have no representation in the legacy protocol.
    remote isolated function onCallTool(CallToolParams callParams) returns InputRequiredResult => {
        requestState: "state"
    };
}

// Attached without a @StreamableHttpConfig annotation so the dispatcher falls back to defaults.
isolated function newUnconfiguredService() returns StreamableHttpAdvancedService =>
    service object {
        remote isolated function onListTools() returns ListToolsResult => {
            tools: [{name: "plain", inputSchema: {'type: "object"}}]
        };

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
    };

final http:Client legacyDispatcherClient = check new ("http://localhost:3216");

isolated function legacyHeaders(map<string|string[]> extraHeaders = {}) returns map<string|string[]> {
    map<string|string[]> requestHeaders = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: LATEST_LEGACY_PROTOCOL_VERSION
    };
    foreach var [headerName, headerValue] in extraHeaders.entries() {
        requestHeaders[headerName] = headerValue;
    }
    return requestHeaders;
}

isolated function legacyPost(string servicePath, json body, map<string|string[]> extraHeaders = {})
        returns http:Response|error {
    return legacyDispatcherClient->post(servicePath, body, headers = legacyHeaders(extraHeaders));
}

isolated function legacyRequest(string method, json params = {}, RequestId id = 1) returns json => {
    "jsonrpc": JSONRPC_VERSION,
    "id": id,
    "method": method,
    "params": params
};

@test:Config {}
function testLegacyDispatcherRequiresAcceptAndContentType() returns error? {
    http:Request noAccept = new;
    noAccept.setJsonPayload(legacyRequest(REQUEST_LIST_TOOLS));
    check noAccept.setContentType(CONTENT_TYPE_JSON);
    http:Response noAcceptResponse = check legacyDispatcherClient->post("/stateless", noAccept);
    test:assertEquals(noAcceptResponse.statusCode, 406);

    http:Response jsonOnlyAccept = check legacyPost("/stateless", legacyRequest(REQUEST_LIST_TOOLS),
            {[ACCEPT_HEADER]: CONTENT_TYPE_JSON});
    test:assertEquals(jsonOnlyAccept.statusCode, 406);

    http:Request textRequest = new;
    textRequest.setTextPayload(legacyRequest(REQUEST_LIST_TOOLS).toJsonString());
    textRequest.setHeader(ACCEPT_HEADER, string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`);
    http:Response textResponse = check legacyDispatcherClient->post("/stateless", textRequest);
    test:assertEquals(textResponse.statusCode, 415);
}

@test:Config {}
function testLegacyDispatcherRejectsUnsupportedMessages() returns error? {
    http:Response unknownNotification = check legacyPost("/stateless", {
        "jsonrpc": JSONRPC_VERSION,
        "method": "notifications/unknown"
    });
    test:assertEquals(unknownNotification.statusCode, 400);
    WireError notificationError = check (check unknownNotification.getJsonPayload()).cloneWithType();
    test:assertEquals(notificationError.'error.message, "Unknown notification method");

    // A response message is a valid JSON-RPC message but not something a server accepts.
    http:Response responseMessage = check legacyPost("/stateless", {
        "jsonrpc": JSONRPC_VERSION,
        "id": 1,
        "result": {"tools": []}
    });
    test:assertEquals(responseMessage.statusCode, 400);
    WireError responseError = check (check responseMessage.getJsonPayload()).cloneWithType();
    test:assertEquals(responseError.'error.message, "Unsupported request type");

    http:Response unknownMethod = check legacyPost("/stateless", legacyRequest("resources/list"));
    JsonRpcError methodError = check (check unknownMethod.getJsonPayload()).cloneWithType();
    test:assertEquals(methodError.'error.code, METHOD_NOT_FOUND);
}

@test:Config {}
function testModernOnlyServiceRejectsLegacyRequests() returns error? {
    http:Response legacyResponse = check legacyPost("/modernOnly", legacyRequest(REQUEST_LIST_TOOLS));
    test:assertEquals(legacyResponse.statusCode, 400);
    JsonRpcError legacyError = check (check legacyResponse.getJsonPayload()).cloneWithType();
    test:assertEquals(legacyError.'error.code, UNSUPPORTED_PROTOCOL_VERSION);

    http:Response deleteResponse = check legacyDispatcherClient->delete("/modernOnly",
            headers = legacyHeaders());
    test:assertEquals(deleteResponse.statusCode, 405);
}

@test:Config {}
function testStatefulServiceRequiresSessionIds() returns error? {
    http:Response listWithoutSession = check legacyPost("/stateful", legacyRequest(REQUEST_LIST_TOOLS));
    test:assertEquals(listWithoutSession.statusCode, 400);
    JsonRpcError listError = check (check listWithoutSession.getJsonPayload()).cloneWithType();
    test:assertEquals(listError.'error.message, "Missing session ID header");

    http:Response callWithoutSession = check legacyPost("/stateful",
            legacyRequest(REQUEST_CALL_TOOL, {"name": "echo"}));
    test:assertEquals(callWithoutSession.statusCode, 400);

    http:Response unknownSession = check legacyPost("/stateful", legacyRequest(REQUEST_LIST_TOOLS),
            {[SESSION_ID_HEADER]: "no-such-session"});
    test:assertEquals(unknownSession.statusCode, 404);

    http:Response deleteWithoutSession = check legacyDispatcherClient->delete("/stateful",
            headers = legacyHeaders());
    test:assertEquals(deleteWithoutSession.statusCode, 400);

    http:Response deleteUnknownSession = check legacyDispatcherClient->delete("/stateful",
            headers = legacyHeaders({[SESSION_ID_HEADER]: "no-such-session"}));
    test:assertEquals(deleteUnknownSession.statusCode, 404);
}

@test:Config {}
function testStatefulSessionLifecycle() returns error? {
    http:Response initResponse = check legacyPost("/stateful", legacyRequest(REQUEST_INITIALIZE, {
        "protocolVersion": LATEST_LEGACY_PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": "legacy-test", "version": "1"}
    }));
    test:assertEquals(initResponse.statusCode, 200);
    string sessionId = check initResponse.getHeader(SESSION_ID_HEADER);

    http:Response listResponse = check legacyPost("/stateful", legacyRequest(REQUEST_LIST_TOOLS),
            {[SESSION_ID_HEADER]: sessionId});
    test:assertEquals(listResponse.statusCode, 200);

    http:Response callResponse = check legacyPost("/stateful",
            legacyRequest(REQUEST_CALL_TOOL, {"name": "echo"}), {[SESSION_ID_HEADER]: sessionId});
    test:assertEquals(callResponse.statusCode, 200);

    http:Response deleteResponse = check legacyDispatcherClient->delete("/stateful",
            headers = legacyHeaders({[SESSION_ID_HEADER]: sessionId}));
    test:assertEquals(deleteResponse.statusCode, 200);
}

@test:Config {}
function testLegacyCallToolRejectsInputRequiredResults() returns error? {
    http:Response inputRequired = check legacyPost("/stateless",
            legacyRequest(REQUEST_CALL_TOOL, {"name": "ask"}));
    JsonRpcError inputError = check (check inputRequired.getJsonPayload()).cloneWithType();
    test:assertTrue(inputError.'error.message.includes("Input-required tool calls require modern MCP"));

    http:Response taskCall = check legacyPost("/stateless",
            legacyRequest(REQUEST_CALL_TOOL, {"name": "ask", "task": {"ttl": 1}}));
    JsonRpcError taskError = check (check taskCall.getJsonPayload()).cloneWithType();
    test:assertEquals(taskError.'error.message, "Task-augmented tool calls are not supported");

    http:Response invalidParams = check legacyPost("/stateless",
            legacyRequest(REQUEST_CALL_TOOL, {"name": 42}));
    JsonRpcError paramsError = check (check invalidParams.getJsonPayload()).cloneWithType();
    test:assertEquals(paramsError.'error.code, INVALID_PARAMS);

    http:Response invalidInit = check legacyPost("/stateless", legacyRequest(REQUEST_INITIALIZE, {"bogus": true}));
    JsonRpcError initError = check (check invalidInit.getJsonPayload()).cloneWithType();
    test:assertEquals(initError.'error.code, INVALID_PARAMS);
}

@test:Config {}
function testUnconfiguredServiceUsesDefaultConfiguration() returns error? {
    StreamableHttpListener unconfiguredListener = check new (3217);
    check unconfiguredListener.attach(newUnconfiguredService(), "/plain");
    check unconfiguredListener.'start();

    http:Client plainClient = check new ("http://localhost:3217");
    http:Response initResponse = check plainClient->post("/plain", legacyRequest(REQUEST_INITIALIZE, {
        "protocolVersion": LATEST_LEGACY_PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": "legacy-test", "version": "1"}
    }), headers = legacyHeaders());
    test:assertEquals(initResponse.statusCode, 200);
    JsonRpcResponse initBody = check (check initResponse.getJsonPayload()).cloneWithType();
    InitializeResult initResult = check initBody.result.ensureType();
    test:assertEquals(initResult.serverInfo.name, "MCP Service");
    test:assertEquals(initResult.serverInfo.version, "1.0.0");

    check unconfiguredListener.immediateStop();
}

@test:Config {}
function testAdvancedHandlersBindTransportParameters() returns error? {
    http:Response initResponse = check legacyPost("/sessionAware", legacyRequest(REQUEST_INITIALIZE, {
        "protocolVersion": LATEST_LEGACY_PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": "legacy-test", "version": "1"}
    }));
    string sessionId = check initResponse.getHeader(SESSION_ID_HEADER);

    http:Response listResponse = check legacyPost("/sessionAware", legacyRequest(REQUEST_LIST_TOOLS),
            {[SESSION_ID_HEADER]: sessionId});
    test:assertEquals(listResponse.statusCode, 200);

    http:Response callResponse = check legacyPost("/sessionAware",
            legacyRequest(REQUEST_CALL_TOOL, {"name": "whoami"}), {[SESSION_ID_HEADER]: sessionId});
    JsonRpcResponse callBody = check (check callResponse.getJsonPayload()).cloneWithType();
    CallToolResult callResult = check callBody.result.ensureType();
    TextContent textContent = check callResult.content[0].ensureType();
    test:assertEquals(textContent.text, string `${sessionId}:/sessionAware`);
}
