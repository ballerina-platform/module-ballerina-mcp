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

@StreamableHttpServiceConfig {info: {name: "dispatcher-tools", version: "1"}}
service StreamableHttpAdvancedService /tools on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {
        tools: [{name: "echo", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {info: {name: "mirrored-headers", version: "1"}}
service StreamableHttpAdvancedService /mirrored on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {
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

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {info: {name: "fail-list", version: "1"}}
service StreamableHttpAdvancedService /failList on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage|ServerError =>
        error ServerError("tool listing is unavailable");

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {info: {name: "panic-list", version: "1"}}
service StreamableHttpAdvancedService /panicList on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage {
        panic error("unexpected listing panic");
    }

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {info: {name: "bad-headers", version: "1"}}
service StreamableHttpAdvancedService /badHeaders on dispatcherErrorListener {
    // Two arguments mirrored onto the same header name cannot be represented on the wire.
    remote isolated function onListTools() returns ToolPage => {
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

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {info: {name: "negative-ttl", version: "1"}}
service StreamableHttpAdvancedService /negativeTtl on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {
        tools: [{name: "echo", inputSchema: {'type: "object"}}],
        ttlMs: -5
    };

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {
        content: [{'type: "text", text: "called"}]
    };
}

@StreamableHttpServiceConfig {info: {name: "needs-structured", version: "1"}}
service StreamableHttpAdvancedService /needsStructured on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {
        tools: [{name: "structured", inputSchema: {'type: "object"}, outputSchema: {"type": "object"}}]
    };

    // Declares an output schema but never produces structured content.
    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {info: {name: "fail-call", version: "1"}}
service StreamableHttpAdvancedService /failCall on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {
        tools: [{name: "echo", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult|ServerError =>
        error ServerError("tool execution is unavailable");
}

// Form elicitations the types accept but the form schema subset or the spec does not.
final readonly & map<FormElicitationParams> badForms = {
    blankMessage: {message: " ", requestedSchema: {properties: {}}},
    undeclaredRequired: {message: "?", requestedSchema: {properties: {}, required: ["name"]}},
    invertedLength: {
        message: "?",
        requestedSchema: {properties: {name: {'type: "string", minLength: 5, maxLength: 2}}}
    },
    negativeLength: {message: "?", requestedSchema: {properties: {name: {'type: "string", minLength: -1}}}},
    invertedNumberRange: {
        message: "?",
        requestedSchema: {properties: {age: {'type: "integer", minimum: 10, maximum: 1}}}
    },
    emptyEnum: {message: "?", requestedSchema: {properties: {color: {'type: "string", 'enum: []}}}},
    legacyEnumNames: {
        message: "?",
        requestedSchema: {properties: {color: {'type: "string", 'enum: ["red"], enumNames: ["Red"]}}}
    },
    foreignDefault: {
        message: "?",
        requestedSchema: {properties: {color: {'type: "string", 'enum: ["red"], default: "blue"}}}
    },
    foreignTitledDefault: {
        message: "?",
        requestedSchema: {
            properties: {size: {'type: "string", oneOf: [{'const: "s", title: "Small"}], default: "xl"}}
        }
    },
    foreignMultiDefault: {
        message: "?",
        requestedSchema: {
            properties: {tags: {'type: "array", items: {'enum: ["a"]}, default: ["a", "b"]}}
        }
    },
    invertedItemRange: {
        message: "?",
        requestedSchema: {
            properties: {
                tags: {'type: "array", minItems: 2, maxItems: 1, items: {anyOf: [{'const: "a", title: "A"}]}}
            }
        }
    }
};

// URL elicitations the types accept but the spec does not.
final readonly & map<UrlElicitationParams> badUrls = {
    blankUrlMessage: {mode: "url", message: " ", url: "https://example.com/connect"},
    relativeUrl: {mode: "url", message: "Connect", url: "/connect"},
    schemelessUrl: {mode: "url", message: "Connect", url: "example.com/connect"},
    hostlessUrl: {mode: "url", message: "Connect", url: "https://"},
    portOnlyUrl: {mode: "url", message: "Connect", url: "https://:443/connect"},
    userinfoOnlyUrl: {mode: "url", message: "Connect", url: "https://user@/connect"},
    spacedUrl: {mode: "url", message: "Connect", url: "https://exa mple.com/connect"}
};

@StreamableHttpServiceConfig {info: {name: "bad-input-required", version: "1"}}
service StreamableHttpAdvancedService /badInputRequired on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {
        tools: from string toolName in ["ask", "openLink", "openLocalLink", ...badForms.keys(), ...badUrls.keys()]
            select {name: toolName, inputSchema: {'type: "object"}}
    };

    remote isolated function onCallTool(CallToolParams callParams) returns InputRequiredResult {
        FormElicitationParams? badForm = badForms[callParams.name];
        if badForm is FormElicitationParams {
            return {inputRequests: {"answer": {params: badForm}}};
        }
        UrlElicitationParams? badUrl = badUrls[callParams.name];
        if badUrl is UrlElicitationParams {
            return {inputRequests: {"connect": {params: badUrl}}};
        }
        if callParams.name == "openLocalLink" {
            return {inputRequests: {"connect": {params: {mode: "url", message: "Connect", url: "http://localhost:9090/connect"}}}};
        }
        if callParams.name == "openLink" {
            return {
                inputRequests: {
                    "connect": {params: {mode: "url", message: "Connect", url: "https://example.com/connect"}}
                }
            };
        }
        // Neither inputRequests nor requestState: an unusable continuation.
        return {};
    }
}

@StreamableHttpServiceConfig {info: {name: "reject-params", version: "1"}, sessionMode: STATELESS}
service StreamableHttpAdvancedService /rejectParams on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {
        tools: [{name: "forecast", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult|InvalidParamsError =>
        error InvalidParamsError("city is required");
}

@StreamableHttpServiceConfig {
    info: {name: "legacy-only", version: "1"},
    protocolMode: "legacy"
}
service StreamableHttpAdvancedService /legacyMode on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {
    info: {name: "guided", version: "1"},
    options: {instructions: "Call echo first."}
}
service StreamableHttpAdvancedService /guided on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {
    info: {name: "cors-guarded", version: "1"},
    httpConfig: {cors: {allowOrigins: ["https://trusted.example"]}}
}
service StreamableHttpAdvancedService /corsGuarded on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {info: {name: "panic-tool", version: "1"}}
service StreamableHttpService /panicTool on dispatcherErrorListener {
    @Tool {description: "always fails", schema: {'type: "object"}}
    remote isolated function explode() returns string {
        panic error("tool implementation panicked");
    }
}

isolated int endlessListings = 0;

// Always offers another page, each with a new cursor.
@StreamableHttpServiceConfig {info: {name: "endless-pages", version: "1"}}
service StreamableHttpAdvancedService /endlessPages on dispatcherErrorListener {
    remote isolated function onListTools(Cursor? cursor) returns ToolPage {
        lock {
            endlessListings += 1;
            return {tools: [], nextCursor: endlessListings.toString()};
        }
    }

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

final http:Client dispatcherErrorClient = check new ("http://localhost:3211");

isolated function dispatcherPost(string servicePath, string methodName, RequestParams requestParams = {},
        map<string|string[]> extraHeaders = {}, string protocolVersion = LATEST_MODERN_PROTOCOL_VERSION,
        string? metaProtocolVersion = (), boolean includeCapabilities = true,
        ClientCapabilities capabilities = {}) returns http:Response|error {
    Meta requestMeta = {};
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
function testToolLookupStopsAfterAPageLimit() returns error? {
    http:Response response = check dispatcherPost("/endlessPages", REQUEST_CALL_TOOL, {"name": "missing"},
            {[NAME_HEADER]: "missing"});
    check assertJsonRpcError(response, 200, INVALID_PARAMS, "Unknown tool name");
    lock {
        test:assertTrue(endlessListings > 1 && endlessListings <= 100, endlessListings.toString());
    }
}

@test:Config {}
function testDispatcherReportsToolListingFailures() returns error? {
    http:Response serverErrorResponse = check dispatcherPost("/failList", REQUEST_LIST_TOOLS);
    check assertJsonRpcError(serverErrorResponse, 200, INTERNAL_ERROR, "tool listing is unavailable");

    http:Response panicResponse = check dispatcherPost("/panicList", REQUEST_LIST_TOOLS);
    check assertJsonRpcError(panicResponse, 200, INTERNAL_ERROR, "Listing tools failed unexpectedly");

    http:Response headerResponse = check dispatcherPost("/badHeaders", REQUEST_LIST_TOOLS);
    check assertJsonRpcError(headerResponse, 200, INTERNAL_ERROR, "Duplicate x-mcp-header name");
}

@test:Config {}
function testNegativeHandlerTtlIsSentAsZero() returns error? {
    http:Response listResponse = check dispatcherPost("/negativeTtl", REQUEST_LIST_TOOLS);
    test:assertEquals(listResponse.statusCode, 200);
    json listResult = check (check listResponse.getJsonPayload()).result;
    test:assertEquals(check listResult.ttlMs, 0);

    http:Response callResponse = check dispatcherPost("/negativeTtl", REQUEST_CALL_TOOL, {"name": "echo"},
            {[NAME_HEADER]: "echo"});
    test:assertEquals(callResponse.statusCode, 200);
    json callResult = check (check callResponse.getJsonPayload()).result;
    test:assertEquals(check callResult.content, [{'type: "text", text: "called"}]);
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
}

@test:Config {}
function testDispatcherValidatesProtocolNegotiation() returns error? {
    http:Response missingMeta = check dispatcherPost("/tools", REQUEST_LIST_TOOLS, includeCapabilities = false);
    check assertJsonRpcError(missingMeta, 400, INVALID_PARAMS, "Required protocol version and client capabilities");

    http:Response headerMetaMismatch = check dispatcherPost("/tools", REQUEST_LIST_TOOLS,
            metaProtocolVersion = LATEST_LEGACY_PROTOCOL_VERSION);
    check assertJsonRpcError(headerMetaMismatch, 400, HEADER_MISMATCH, "MCP-Protocol-Version must match");

    // Only a known modern version header selects the modern protocol; others get 1.4.0's answer.
    http:Response unsupportedVersion = check dispatcherPost("/tools", REQUEST_LIST_TOOLS,
            protocolVersion = "1999-01-01");
    check assertJsonRpcError(unsupportedVersion, 400, INVALID_REQUEST, "Unsupported MCP-Protocol-Version header");

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
    test:assertEquals(errorData.supported, ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"]);

    http:Response legacyDiscover = check dispatcherPost("/legacyMode", "server/discover");
    test:assertEquals(legacyDiscover.statusCode, 400);
    JsonRpcError discoverError = check (check legacyDiscover.getJsonPayload()).cloneWithType();
    record {|string[] supported; string requested;|} discoverData =
            check (discoverError.'error?.data).cloneWithType();
    test:assertEquals(discoverData.supported, ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"]);
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
function testHandlersRejectParamsWithTheirOwnMessage() returns error? {
    http:Response modernCall = check dispatcherPost("/rejectParams", REQUEST_CALL_TOOL, {"name": "forecast"},
            {[NAME_HEADER]: "forecast"});
    check assertJsonRpcError(modernCall, 200, INVALID_PARAMS, "city is required");
    JsonRpcError modernError = check (check modernCall.getJsonPayload()).cloneWithType();
    test:assertEquals(modernError.'error.message, "city is required");

    http:Response legacyCall = check legacyToolPost("/rejectParams", REQUEST_CALL_TOOL, {"name": "forecast"});
    check assertJsonRpcError(legacyCall, 200, INVALID_PARAMS, "city is required");
    JsonRpcError legacyError = check (check legacyCall.getJsonPayload()).cloneWithType();
    test:assertEquals(legacyError.'error.message, "city is required");
}

@test:Config {}
function testDispatcherValidatesInputRequiredResults() returns error? {
    http:Response emptyContinuation = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL, {"name": "ask"},
            {[NAME_HEADER]: "ask"});
    check assertJsonRpcError(emptyContinuation, 200, INTERNAL_ERROR,
            "Input-required result must contain inputRequests or requestState");

    http:Response missingCapability = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL,
            {"name": "openLink"}, {[NAME_HEADER]: "openLink"});
    check assertMissingCapability(missingCapability, "Client did not declare the required capability: elicitation",
            {elicitation: {url: {}}});

    string formTool = badForms.keys()[0];
    http:Response missingFormCapability = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL,
            {"name": formTool}, {[NAME_HEADER]: formTool});
    check assertMissingCapability(missingFormCapability,
            "Client did not declare the required capability: elicitation", {elicitation: {form: {}}});

    http:Response missingMode = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL, {"name": "openLink"},
            {[NAME_HEADER]: "openLink"}, capabilities = {elicitation: {form: {}}});
    check assertMissingCapability(missingMode, "Client did not declare the required elicitation mode",
            {elicitation: {url: {}}});
}

@test:Config {}
function testDispatcherRejectsMalformedFormElicitations() returns error? {
    foreach string toolName in badForms.keys() {
        http:Response response = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL, {"name": toolName},
                {[NAME_HEADER]: toolName}, capabilities = {elicitation: {form: {}}});
        check assertJsonRpcError(response, 200, INTERNAL_ERROR, "Form ");
    }
}

@test:Config {}
function testDispatcherRejectsMalformedUrlElicitations() returns error? {
    foreach string toolName in badUrls.keys() {
        http:Response response = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL, {"name": toolName},
                {[NAME_HEADER]: toolName}, capabilities = {elicitation: {url: {}}});
        check assertJsonRpcError(response, 200, INTERNAL_ERROR, "URL elicitation");
    }
}

@test:Config {}
function testDispatcherAllowsHttpUrlElicitations() returns error? {
    http:Response response = check dispatcherPost("/badInputRequired", REQUEST_CALL_TOOL, {"name": "openLocalLink"},
            {[NAME_HEADER]: "openLocalLink"}, capabilities = {elicitation: {url: {}}});
    test:assertEquals(response.statusCode, 200);
    json body = check response.getJsonPayload();
    test:assertEquals(check body.result.resultType, "input_required", body.toJsonString());
}

isolated function assertMissingCapability(http:Response response, string expectedMessage,
        json expectedCapabilities) returns error? {
    check assertJsonRpcError(response, 400, MISSING_REQUIRED_CLIENT_CAPABILITY, expectedMessage);
    json errorBody = check response.getJsonPayload();
    test:assertEquals(check errorBody.'error.data.requiredCapabilities, expectedCapabilities);
}

@test:Config {}
function testDispatcherRejectsSubscriptions() returns error? {
    http:Response listen = check dispatcherPost("/tools", "subscriptions/listen",
            {"notifications": {"toolsListChanged": true}});
    check assertJsonRpcError(listen, 404, METHOD_NOT_FOUND, "Method not found");
}

@test:Config {}
function testDispatcherAdvertisesInstructionsAndToolCapability() returns error? {
    http:Response guided = check dispatcherPost("/guided", "server/discover");
    test:assertEquals(guided.statusCode, 200);
    WireResponse guidedBody = check (check guided.getJsonPayload()).cloneWithType();
    test:assertEquals(guidedBody.result["instructions"], "Call echo first.");

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
