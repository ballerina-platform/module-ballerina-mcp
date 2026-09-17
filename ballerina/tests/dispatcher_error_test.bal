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

listener StreamableHttpListener dispatcherErrorListener = check new (3211);

@StreamableHttpConfig {info: {name: "dispatcher-tools", version: "1"}}
service StreamableHttpAdvancedService /tools on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {
        tools: [{name: "echo", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "mirrored-headers", version: "1"}}
service StreamableHttpAdvancedService /mirrored on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {
        tools: [
            {
                name: "regional",
                inputSchema: {
                    'type: "object",
                    properties: {region: {'type: "string", "x-mcp-header": "Region"}}
                }
            }
        ]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "fail-list", version: "1"}}
service StreamableHttpAdvancedService /failList on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult|ServerError =>
        error ServerError("tool listing is unavailable");

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "panic-list", version: "1"}}
service StreamableHttpAdvancedService /panicList on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult {
        panic error("unexpected listing panic");
    }

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "bad-headers", version: "1"}}
service StreamableHttpAdvancedService /badHeaders on dispatcherErrorListener {
    // Two arguments mirrored onto the same header name cannot be represented on the wire.
    remote isolated function onListTools() returns ListToolsResult => {
        tools: [
            {
                name: "conflicting",
                inputSchema: {
                    'type: "object",
                    properties: {
                        first: {'type: "string", "x-mcp-header": "Region"},
                        second: {'type: "string", "x-mcp-header": "region"}
                    }
                }
            }
        ]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "negative-ttl", version: "1"}}
service StreamableHttpAdvancedService /negativeTtl on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {tools: [], ttlMs: -1};

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "needs-structured", version: "1"}}
service StreamableHttpAdvancedService /needsStructured on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {
        tools: [{name: "structured", inputSchema: {'type: "object"}, outputSchema: {"type": "object"}}]
    };

    // Declares an output schema but never produces structured content.
    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "fail-call", version: "1"}}
service StreamableHttpAdvancedService /failCall on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {
        tools: [{name: "echo", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|ServerError =>
        error ServerError("tool execution is unavailable");
}

@StreamableHttpConfig {info: {name: "bad-input-required", version: "1"}}
service StreamableHttpAdvancedService /badInputRequired on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {
        tools: [{name: "ask", inputSchema: {'type: "object"}}, {name: "badMode", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns InputRequiredResult {
        if callParams.name == "badMode" {
            return {
                requestState: "state",
                inputRequests: {
                    "answer": {
                        method: "elicitation/create",
                        params: {"mode": "telepathy", "message": "?"}
                    }
                }
            };
        }
        // Neither inputRequests nor requestState: an unusable continuation.
        return {};
    }
}

@StreamableHttpConfig {info: {name: "fail-subscribe", version: "1"}}
service StreamableHttpAdvancedService /failSubscribe on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};

    remote isolated function onSubscribe(SubscriptionFilter notifications)
            returns stream<JsonRpcNotification, error?>|ServerError => error ServerError("subscriptions are down");
}

@StreamableHttpConfig {
    info: {name: "legacy-only", version: "1"},
    protocolMode: "legacy"
}
service StreamableHttpAdvancedService /legacyMode on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {
    info: {name: "guided", version: "1"},
    options: {instructions: "Call echo first."}
}
service StreamableHttpAdvancedService /guided on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {
    info: {name: "cors-guarded", version: "1"},
    httpConfig: {cors: {allowOrigins: ["https://trusted.example"]}}
}
service StreamableHttpAdvancedService /corsGuarded on dispatcherErrorListener {
    remote isolated function onListTools() returns ListToolsResult => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "panic-tool", version: "1"}}
service StreamableHttpService /panicTool on dispatcherErrorListener {
    @Tool {description: "always fails", schema: {'type: "object"}}
    remote isolated function explode() returns string {
        panic error("tool implementation panicked");
    }
}

final http:Client dispatcherErrorClient = check new ("http://localhost:3211");

isolated function dispatcherPost(string servicePath, string methodName, RequestParams requestParams = {},
        map<string|string[]> extraHeaders = {}, string protocolVersion = MODERN_PROTOCOL_VERSION,
        string? metaProtocolVersion = (), boolean includeCapabilities = true,
        ClientCapabilities capabilities = {}) returns http:Response|error {
    RequestMetaObject requestMeta = {};
    requestMeta[PROTOCOL_META_KEY] = metaProtocolVersion ?: protocolVersion;
    if includeCapabilities {
        requestMeta[CAPABILITIES_META_KEY] = capabilities;
    }
    requestParams._meta = requestMeta;
    map<string|string[]> requestHeaders = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: protocolVersion,
        [METHOD_HEADER]: methodName
    };
    foreach var [headerName, headerValue] in extraHeaders.entries() {
        requestHeaders[headerName] = headerValue;
    }
    JsonRpcRequest requestMessage = {jsonrpc: JSONRPC_VERSION, id: 200, method: methodName, params: requestParams};
    return dispatcherErrorClient->post(servicePath, requestMessage, headers = requestHeaders);
}

isolated function assertJsonRpcError(http:Response response, int expectedStatus, int expectedCode,
        string expectedMessagePart) returns error? {
    test:assertEquals(response.statusCode, expectedStatus);
    JsonRpcError errorBody = check (check response.getJsonPayload()).cloneWithType();
    test:assertEquals(errorBody.'error.code, expectedCode);
    test:assertTrue(errorBody.'error.message.includes(expectedMessagePart),
            string `unexpected error message '${errorBody.'error.message}'`);
}

@test:Config {}
function testDispatcherReportsToolListingFailures() returns error? {
    http:Response serverErrorResponse = check dispatcherPost("/failList", REQUEST_LIST_TOOLS);
    check assertJsonRpcError(serverErrorResponse, 200, INTERNAL_ERROR, "tool listing is unavailable");

    http:Response panicResponse = check dispatcherPost("/panicList", REQUEST_LIST_TOOLS);
    check assertJsonRpcError(panicResponse, 200, INTERNAL_ERROR, "Listing tools failed unexpectedly");

    http:Response headerResponse = check dispatcherPost("/badHeaders", REQUEST_LIST_TOOLS);
    check assertJsonRpcError(headerResponse, 200, INTERNAL_ERROR, "Duplicate x-mcp-header name");

    http:Response ttlResponse = check dispatcherPost("/negativeTtl", REQUEST_LIST_TOOLS);
    check assertJsonRpcError(ttlResponse, 200, INTERNAL_ERROR, "ttlMs must be non-negative");
}

@test:Config {}
function testDispatcherValidatesToolCallHeaders() returns error? {
    http:Response missingName = check dispatcherPost("/tools", REQUEST_CALL_TOOL, {"name": "echo"});
    check assertJsonRpcError(missingName, 400, HEADER_MISMATCH, "Missing Mcp-Name header");

    http:Response wrongName = check dispatcherPost("/tools", REQUEST_CALL_TOOL, {"name": "echo"},
            {[NAME_HEADER]: "other"});
    check assertJsonRpcError(wrongName, 400, HEADER_MISMATCH, "Mcp-Name must match the tool name");

    http:Response unknownTool = check dispatcherPost("/tools", REQUEST_CALL_TOOL, {"name": "ghost"},
            {[NAME_HEADER]: "ghost"});
    check assertJsonRpcError(unknownTool, 200, INVALID_PARAMS, "Unknown tool name");

    http:Response invalidParams = check dispatcherPost("/tools", REQUEST_CALL_TOOL, {"name": 42});
    check assertJsonRpcError(invalidParams, 200, INVALID_PARAMS, "Invalid tool call parameters");

    http:Response taskParams = check dispatcherPost("/tools", REQUEST_CALL_TOOL,
            {"name": "echo", "task": {"ttl": 1000}}, {[NAME_HEADER]: "echo"});
    check assertJsonRpcError(taskParams, 200, INVALID_PARAMS, "Legacy task parameters are not supported");
}

@test:Config {}
function testDispatcherValidatesProtocolNegotiation() returns error? {
    http:Response missingMeta = check dispatcherPost("/tools", REQUEST_LIST_TOOLS, includeCapabilities = false);
    check assertJsonRpcError(missingMeta, 400, INVALID_PARAMS, "Required protocol version and client capabilities");

    http:Response headerMetaMismatch = check dispatcherPost("/tools", REQUEST_LIST_TOOLS,
            metaProtocolVersion = LATEST_LEGACY_PROTOCOL_VERSION);
    check assertJsonRpcError(headerMetaMismatch, 400, HEADER_MISMATCH, "MCP-Protocol-Version must match");

    http:Response unsupportedVersion = check dispatcherPost("/tools", REQUEST_LIST_TOOLS,
            protocolVersion = "1999-01-01");
    check assertJsonRpcError(unsupportedVersion, 400, UNSUPPORTED_PROTOCOL_VERSION, "Unsupported protocol version");

    http:Response methodMismatch = check dispatcherPost("/tools", REQUEST_LIST_TOOLS,
            extraHeaders = {[METHOD_HEADER]: "server/discover"});
    check assertJsonRpcError(methodMismatch, 400, HEADER_MISMATCH, "Mcp-Method must match");

    // A legacy-only service refuses modern requests and advertises the legacy revisions.
    http:Response legacyOnly = check dispatcherPost("/legacyMode", REQUEST_LIST_TOOLS);
    test:assertEquals(legacyOnly.statusCode, 400);
    JsonRpcError legacyError = check (check legacyOnly.getJsonPayload()).cloneWithType();
    test:assertEquals(legacyError.'error.code, UNSUPPORTED_PROTOCOL_VERSION);
    record {|string[] supported; string requested;|} errorData =
            check (legacyError.'error?.data).cloneWithType();
    test:assertFalse(errorData.supported.some(v => v == MODERN_PROTOCOL_VERSION));
    test:assertTrue(errorData.supported.some(v => v == LATEST_LEGACY_PROTOCOL_VERSION));
}

@test:Config {}
function testDispatcherReportsToolCallFailures() returns error? {
    http:Response callFailure = check dispatcherPost("/failCall", REQUEST_CALL_TOOL, {"name": "echo"},
            {[NAME_HEADER]: "echo"});
    check assertJsonRpcError(callFailure, 200, INTERNAL_ERROR, "tool execution is unavailable");

    http:Response missingStructured = check dispatcherPost("/needsStructured", REQUEST_CALL_TOOL,
            {"name": "structured"}, {[NAME_HEADER]: "structured"});
    check assertJsonRpcError(missingStructured, 200, INTERNAL_ERROR, "Missing structured output");

    // A panicking regular-service tool is reported as a failed tool result, not a transport error.
    http:Response panicTool = check dispatcherPost("/panicTool", REQUEST_CALL_TOOL, {"name": "explode"},
            {[NAME_HEADER]: "explode"});
    test:assertEquals(panicTool.statusCode, 200);
    WireResponse panicBody = check (check panicTool.getJsonPayload()).cloneWithType();
    test:assertEquals(panicBody.result["isError"], true);
}

@test:Config {}
function testDispatcherValidatesInputRequiredResults() returns error? {
    http:Response emptyContinuation = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL, {"name": "ask"},
            {[NAME_HEADER]: "ask"});
    check assertJsonRpcError(emptyContinuation, 200, INTERNAL_ERROR,
            "Input-required result must contain inputRequests or requestState");

    http:Response missingCapability = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL,
            {"name": "badMode"}, {[NAME_HEADER]: "badMode"});
    check assertJsonRpcError(missingCapability, 400, MISSING_REQUIRED_CLIENT_CAPABILITY,
            "Client did not declare the required capability: elicitation");

    http:Response badMode = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL, {"name": "badMode"},
            {[NAME_HEADER]: "badMode"}, capabilities = {elicitation: {form: {}}});
    check assertJsonRpcError(badMode, 200, INTERNAL_ERROR, "Invalid elicitation mode");
}

@test:Config {}
function testDispatcherReportsSubscriptionFailures() returns error? {
    http:Response invalidFilter = check dispatcherPost("/failSubscribe", "subscriptions/listen",
            {"notifications": {"toolsListChanged": "yes"}});
    check assertJsonRpcError(invalidFilter, 200, INVALID_PARAMS, "Invalid subscription filter");

    http:Response failingSource = check dispatcherPost("/failSubscribe", "subscriptions/listen",
            {"notifications": {"toolsListChanged": true}});
    check assertJsonRpcError(failingSource, 200, INTERNAL_ERROR, "subscriptions are down");
}

@test:Config {}
function testDispatcherAdvertisesInstructionsAndSubscriptionCapability() returns error? {
    http:Response guided = check dispatcherPost("/guided", "server/discover");
    test:assertEquals(guided.statusCode, 200);
    WireResponse guidedBody = check (check guided.getJsonPayload()).cloneWithType();
    test:assertEquals(guidedBody.result["instructions"], "Call echo first.");

    http:Response subscribable = check dispatcherPost("/failSubscribe", "server/discover");
    WireResponse subscribableBody = check (check subscribable.getJsonPayload()).cloneWithType();
    DiscoverResult discovered = check subscribableBody.result.cloneWithType();
    test:assertEquals(discovered.capabilities.tools?.listChanged, true);

    http:Response plain = check dispatcherPost("/tools", "server/discover");
    WireResponse plainBody = check (check plain.getJsonPayload()).cloneWithType();
    DiscoverResult plainDiscovered = check plainBody.result.cloneWithType();
    test:assertEquals(plainDiscovered.capabilities.tools?.listChanged, false);
}

@test:Config {}
function testDispatcherEnforcesConfiguredOriginAllowList() returns error? {
    http:Response allowed = check dispatcherPost("/corsGuarded", "server/discover", {},
            {"origin": "https://trusted.example"});
    test:assertEquals(allowed.statusCode, 200);

    http:Response rejected = check dispatcherPost("/corsGuarded", "server/discover", {},
            {"origin": "https://untrusted.example"});
    check assertJsonRpcError(rejected, 403, INVALID_REQUEST, "Origin is not allowed");
}

@test:Config {}
function testDispatcherRejectsUnknownModernMethods() returns error? {
    http:Response unknownMethod = check dispatcherPost("/tools", "resources/list");
    check assertJsonRpcError(unknownMethod, 404, METHOD_NOT_FOUND, "Method not found");
}

@test:Config {}
function testMirroredToolHeadersMustMatchTheArguments() returns error? {
    map<string|string[]> callHeaders = {[NAME_HEADER]: "regional"};
    RequestParams callParams = {"name": "regional", "arguments": {"region": "north"}};

    http:Response missingHeader = check dispatcherPost("/mirrored", REQUEST_CALL_TOOL, callParams, callHeaders);
    check assertJsonRpcError(missingHeader, 400, HEADER_MISMATCH, "Missing or duplicate mirrored tool header");

    callHeaders["mcp-param-region"] = encodeProtocolHeader("south");
    http:Response mismatchedHeader = check dispatcherPost("/mirrored", REQUEST_CALL_TOOL, callParams, callHeaders);
    check assertJsonRpcError(mismatchedHeader, 400, HEADER_MISMATCH,
            "Mirrored tool header does not match arguments");

    callHeaders["mcp-param-region"] = encodeProtocolHeader("north");
    http:Response matchingHeader = check dispatcherPost("/mirrored", REQUEST_CALL_TOOL, callParams, callHeaders);
    test:assertEquals(matchingHeader.statusCode, 200);
}
