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
import ballerina/time;

@StreamableHttpConfig {info: {name: "modern-test", version: "1"}}
service StreamableHttpAdvancedService /mcp on new StreamableHttpListener(3205) {
    remote isolated function onListTools() returns ListToolsResult {
        ListToolsResult handlerResult = {
            tools: [
                {name: "scalar", inputSchema: {'type: "object"}, outputSchema: {"type": "integer"}},
                {
                    name: "echo",
                    inputSchema: {
                        'type: "object",
                        properties: {
                            region: {'type: "string", "x-mcp-header": "Region"}
                        }
                    }
                },
                {name: "continue", inputSchema: {'type: "object"}},
                {name: "ask", inputSchema: {'type: "object"}},
                {name: "survey", inputSchema: {'type: "object"}},
                {name: "openLink", inputSchema: {'type: "object"}},
                {name: "mixedAnswers", inputSchema: {'type: "object"}},
                {name: "loop", inputSchema: {'type: "object"}},
                {name: "count", inputSchema: {'type: "object"}},
                {name: "probe", inputSchema: {'type: "object"}},
                {name: "dropState", inputSchema: {'type: "object"}},
                {name: "shed", inputSchema: {'type: "object"}},
                {
                    name: "schemaMetadata",
                    inputSchema: {
                        'type: "object",
                        properties: {
                            value: {'type: "integer", minimum: 1}
                        }
                    },
                    outputSchema: {"type": "string", "$ref": "http://127.0.0.1:9/not-loaded"}
                }
            ]
        };
        return handlerResult.cloneReadOnly();
    }

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult|InputRequiredResult {
        if callParams.name == "scalar" || callParams.name == "schemaMetadata" {
            return {resultType: "complete", content: [], structuredContent: 42};
        }
        if callParams.name == "ask" {
            InputResponse? answer = (callParams.inputResponses ?: {})["answer"];
            if answer is () {
                return {
                    requestState: "echo-only-state",
                    inputRequests: {
                        "answer": {
                            params: {
                                message: "Confirm the deletion",
                                requestedSchema: {
                                    properties: {confirmed: {'type: "boolean", description: "Delete it?"}},
                                    required: ["confirmed"]
                                }
                            }
                        }
                    }
                };
            }
            string confirmed = (answer.content ?: {})["confirmed"].toString();
            string text = string `${answer.action}:${confirmed}:${callParams.requestState ?: ""}`;
            return {resultType: "complete", content: [{'type: "text", text}]};
        }
        if callParams.name == "survey" {
            map<InputResponse> answers = callParams.inputResponses ?: {};
            if answers.length() == 0 {
                // Every field schema kind, so the client parses each one from the wire.
                FormSchema confirmSchema = {
                    properties: {
                        confirmed: {'type: "boolean", default: false},
                        name: {'type: "string", minLength: 1, format: "email"},
                        age: {'type: "integer", minimum: 0, maximum: 150},
                        color: {'type: "string", 'enum: ["red", "green"], default: "red"},
                        size: {'type: "string", oneOf: [{'const: "s", title: "Small"}]},
                        tags: {'type: "array", maxItems: 2, items: {'enum: ["a", "b"]}},
                        labels: {'type: "array", items: {anyOf: [{'const: "x", title: "X"}]}, default: ["x"]}
                    },
                    required: ["confirmed"]
                };
                // Keys deliberately out of alphabetical order: the client must follow the server's order.
                return {
                    inputRequests: {
                        "zeta": {params: {message: "First", requestedSchema: confirmSchema}},
                        "alpha": {params: {message: "Second", requestedSchema: confirmSchema}}
                    }
                };
            }
            return {resultType: "complete", content: [{'type: "text", text: answers.keys().sort().toString()}]};
        }
        if callParams.name == "openLink" {
            if callParams.inputResponses is () {
                return {
                    inputRequests: {
                        "connect": {params: {mode: "url", message: "Connect", url: "https://example.com/connect"}}
                    }
                };
            }
            return {resultType: "complete", content: [{'type: "text", text: "connected"}]};
        }
        if callParams.name == "mixedAnswers" {
            // Reports which answers arrived with content, so the client's stripping is visible on the wire.
            map<InputResponse>? answers = callParams.inputResponses;
            if answers is () {
                FormSchema confirmSchema = {properties: {confirmed: {'type: "boolean"}}};
                return {
                    inputRequests: {
                        "link": {params: {mode: "url", message: "url", url: "https://example.com/connect"}},
                        "linkDeclined": {params: {mode: "url", message: "decline", url: "https://example.com/connect"}},
                        "accepted": {params: {message: "accept", requestedSchema: confirmSchema}},
                        "declined": {params: {message: "decline", requestedSchema: confirmSchema}},
                        "cancelled": {params: {message: "cancel", requestedSchema: confirmSchema}}
                    }
                };
            }
            string[] withContent = from [string, InputResponse] [key, answer] in answers.entries()
                where answer.hasKey("content")
                order by key
                select key;
            return {resultType: "complete", content: [{'type: "text", text: withContent.toString()}]};
        }
        if callParams.name == "count" {
            // Never completes; each round's message is its 1-based round number.
            int round = nextRound(callParams);
            return {
                requestState: round.toString(),
                inputRequests: {
                    "again": {
                        params: {
                            message: round.toString(),
                            requestedSchema: {properties: {confirmed: {'type: "boolean"}}}
                        }
                    }
                }
            };
        }
        if callParams.name == "probe" {
            // One state-only round, then report what the continuation carried.
            string? requestState = callParams.requestState;
            if requestState is () {
                return {requestState: PROBE_STATE};
            }
            string sent = callParams.inputResponses is () ? "none" : "sent";
            return {resultType: "complete", content: [{'type: "text", text: sent + "|" + requestState}]};
        }
        if callParams.name == "dropState" {
            // Round one sends state, round two none; round three reports what it received.
            ElicitRequest confirm = {params: {message: "Confirm", requestedSchema: {properties: {confirmed: {'type: "boolean"}}}}};
            if callParams.inputResponses is () {
                return {requestState: "first", inputRequests: {"one": confirm}};
            }
            if callParams.requestState == "first" {
                return {inputRequests: {"two": confirm}};
            }
            return {resultType: "complete", content: [{'type: "text", text: callParams.requestState ?: "absent"}]};
        }
        if callParams.name == "shed" {
            // Sheds load for five state-only rounds, recording when each call arrives.
            lock {
                shedArrivals.push(time:monotonicNow());
            }
            int round = nextRound(callParams);
            if round <= 5 {
                return {requestState: round.toString()};
            }
            return {resultType: "complete", content: [{'type: "text", text: "served"}]};
        }
        if (callParams.name == "continue" && callParams.requestState is ()) || callParams.name == "loop" {
            return {resultType: "input_required", requestState: "opaque-state"};
        }
        return {resultType: "complete", content: [{'type: "text", text: callParams.requestState ?: "ok"}]};
    }
}

isolated decimal[] shedArrivals = [];

// The 1-based round of a call whose request state holds the previous round number.
isolated function nextRound(CallToolParams callParams) returns int {
    int|error previous = int:fromString(callParams.requestState ?: "0");
    return (previous is int ? previous : 0) + 1;
}

// Whitespace, escapes and non-ASCII that a lossy echo would alter.
const PROBE_STATE = " ü\"{\\n}\t 💡 ";

final http:Client modernHttpClient = check new ("http://localhost:3205");

listener StreamableHttpListener structuredOutputListener = check new (3207);

type StructuredPerson record {|
    string name;
    int age;
|};

@StreamableHttpConfig {info: {name: "regular-structured-output", version: "1"}}
service StreamableHttpService /regular on structuredOutputListener {
    @Tool {description: "string", schema: {'type: "object"}, outputSchema: {"type": "string"}}
    remote isolated function stringValue() returns string => "hello";

    @Tool {description: "array", schema: {'type: "object"}, outputSchema: {"type": "array", "items": {"type": "integer"}}}
    remote isolated function arrayValue() returns int[] => [1, 2, 3];

    @Tool {description: "record", schema: {'type: "object"}, outputSchema: {"type": "object"}}
    remote isolated function recordValue() returns StructuredPerson => {name: "Alice", age: 30};

    @Tool {description: "nullable", schema: {'type: "object"}, outputSchema: {"anyOf": [{"type": "string"}, {"type": "null"}]}}
    remote isolated function nullableValue() returns string? => ();

    @Tool {description: "text", schema: {'type: "object"}, outputSchema: {"type": "string"}, structuredOutput: false}
    remote isolated function textOnlyValue() returns string => "text only";
}

@StreamableHttpConfig {info: {name: "generic-structured-output", version: "1"}}
service StreamableHttpService /generic on structuredOutputListener {
    @Tool {description: "boolean", schema: {'type: "object"}, outputSchema: {"type": "boolean"}}
    remote isolated function booleanValue() returns boolean => true;
}

isolated function modernPost(string methodName, RequestParams requestParams = {}, map<string|string[]> extraHeaders = {})
        returns http:Response|error {
    requestParams._meta = {
        [PROTOCOL_META_KEY]: MODERN_PROTOCOL_VERSION,
        [CAPABILITIES_META_KEY]: {}
    };
    map<string|string[]> requestHeaders = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: MODERN_PROTOCOL_VERSION,
        [METHOD_HEADER]: methodName,
        ...extraHeaders
    };
    JsonRpcRequest requestMessage = {jsonrpc: JSONRPC_VERSION, id: 100, method: methodName, params: requestParams};
    return modernHttpClient->post("/mcp", requestMessage, headers = requestHeaders);
}

@test:Config {}
function testModernDiscoveryWithoutSession() returns error? {
    http:Response responseValue = check modernPost("server/discover");
    test:assertEquals(responseValue.statusCode, 200);
    test:assertFalse(responseValue.hasHeader(SESSION_ID_HEADER));
    WireResponse payloadValue = check (check responseValue.getJsonPayload()).cloneWithType();
    test:assertEquals(payloadValue.result["resultType"], "complete");
    test:assertEquals(payloadValue.result["ttlMs"], 0);
    test:assertEquals(payloadValue.result["cacheScope"], "private");
}

@test:Config {}
function testClientCanDiscoverAndAdoptModernConnection() returns error? {
    StreamableHttpClient discoveryClient = check new ("http://localhost:3205/mcp", protocolMode = "modern");
    DiscoverResult discovered = check discoveryClient->discover();
    ConnectionInfo connection = check discoveryClient.adoptDiscovery(discovered);
    test:assertEquals(connection.protocolVersion, MODERN_PROTOCOL_VERSION);
    test:assertEquals(connection.serverInfo?.name, "modern-test");
    ListToolsResult tools = check discoveryClient->listTools();
    test:assertEquals(tools.tools.length(), 13);
    check discoveryClient->close();
}

@test:Config {}
function testModernHeaderValidationAndUnknownMethod() returns error? {
    http:Response mismatchResponse = check modernPost(REQUEST_CALL_TOOL,
            {"name": "echo", "arguments": {"region": "north"}}, {[NAME_HEADER]: "echo"});
    test:assertEquals(mismatchResponse.statusCode, 400);
    JsonRpcError mismatchError = check (check mismatchResponse.getJsonPayload()).cloneWithType();
    test:assertEquals(mismatchError.'error.code, HEADER_MISMATCH);
    http:Response unknownResponse = check modernPost("unknown/method");
    test:assertEquals(unknownResponse.statusCode, 404);
}

@test:Config {}
function testModernClientWideResultAndContinuation() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp");
    _ = check modernClient->connect();
    ListToolsResult toolList = check modernClient->listTools();
    test:assertEquals(toolList.tools.length(), 13);
    test:assertEquals(toolList.ttlMs, 0);
    test:assertEquals(toolList.cacheScope, "private");
    CallToolResult scalarResult = check modernClient->callTool({name: "scalar"});
    test:assertEquals(scalarResult["structuredContent"], 42);
    var echoResult = check modernClient->callToolOnce({name: "echo", arguments: {"region": "世界"}});
    test:assertTrue(echoResult is CallToolResult);
    CallToolResult continuedResult = check modernClient->callTool({name: "continue"});
    test:assertEquals(continuedResult.content[0], <TextContent>{'type: "text", text: "opaque-state"});
    check modernClient->close();

    StreamableHttpClient legacyClient = check new ("http://localhost:3205/mcp", protocolMode = "legacy");
    _ = check legacyClient->connect();
    ListToolsResult legacyTools = check legacyClient->listTools();
    ToolDefinition? legacyScalar = ();
    foreach ToolDefinition toolInfo in legacyTools.tools {
        if toolInfo.name == "scalar" {
            legacyScalar = toolInfo;
            break;
        }
    }
    test:assertTrue(legacyScalar is ToolDefinition);
    if legacyScalar is ToolDefinition {
        test:assertEquals(legacyScalar.outputSchema, ());
    }
    CallToolResult legacyScalarResult = check legacyClient->callTool({name: "scalar"});
    test:assertFalse(legacyScalarResult.hasKey("structuredContent"));
    check legacyClient->close();
}

@test:Config {}
function testProtocolHeaderEncoding() returns error? {
    foreach string headerValue in ["north", "世界", " padded ", "line\nbreak", "=?base64?literal?="] {
        test:assertEquals(check decodeProtocolHeader(encodeProtocolHeader(headerValue)), headerValue);
    }
    test:assertTrue(decodeProtocolHeader("bad\nvalue") is Error);
    test:assertTrue(decodeProtocolHeader("=?base64?SGVsbG8?=") is Error);
    test:assertTrue(toolParameterHeaders({
                                             'type: "object",
                                             properties: {
                                                 first: {'type: "string", "x-mcp-header": "Region"},
                                                 second: {'type: "string", "x-mcp-header": "region"}
                                             }
                                         }, {}) is Error);
}

@test:Config {}
function testModernOriginAndDelete() returns error? {
    http:Response originResponse = check modernPost("server/discover", {}, {"origin": "https://untrusted.example"});
    test:assertEquals(originResponse.statusCode, 403);
    http:Response deleteResponse = check modernHttpClient->delete("/mcp", headers = {
        [PROTOCOL_VERSION_HEADER]: MODERN_PROTOCOL_VERSION
    });
    test:assertEquals(deleteResponse.statusCode, 405);
}

@test:Config {}
function testSchemasRemainMetadataUntilLanguageValidationIsAvailable() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp");
    _ = check modernClient->connect();
    var resultValue = check modernClient->callToolOnce({name: "schemaMetadata", arguments: {"value": "unvalidated"}});
    test:assertTrue(resultValue is CallToolResult);
    if resultValue is CallToolResult {
        test:assertEquals(resultValue?.structuredContent, 42);
    }
    check modernClient->close();
}

@test:Config {}
function testRegularServicesProduceRawStructuredOutputOnlyForModernRequests() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3207/regular", protocolMode = "modern");
    _ = check modernClient->connect();
    ListToolsResult modernTools = check modernClient->listTools();
    map<ToolDefinition> toolsByName = {};
    foreach ToolDefinition toolInfo in modernTools.tools {
        toolsByName[toolInfo.name] = toolInfo;
    }
    ToolDefinition stringTool = check toolsByName["stringValue"].ensureType();
    ToolDefinition arrayTool = check toolsByName["arrayValue"].ensureType();
    ToolDefinition recordTool = check toolsByName["recordValue"].ensureType();
    ToolDefinition nullableTool = check toolsByName["nullableValue"].ensureType();
    ToolDefinition textOnlyTool = check toolsByName["textOnlyValue"].ensureType();
    OutputSchema stringSchema = check stringTool.outputSchema.ensureType();
    OutputSchema arraySchema = check arrayTool.outputSchema.ensureType();
    OutputSchema recordSchema = check recordTool.outputSchema.ensureType();
    OutputSchema nullableSchema = check nullableTool.outputSchema.ensureType();
    test:assertEquals(stringSchema["type"], "string");
    test:assertEquals(arraySchema["type"], "array");
    test:assertEquals(recordSchema["type"], "object");
    test:assertTrue(nullableSchema.hasKey("anyOf"));
    test:assertEquals(textOnlyTool.outputSchema, ());

    CallToolResult stringResult = check modernClient->callTool({name: "stringValue"});
    test:assertEquals(stringResult["structuredContent"], "hello");
    CallToolResult arrayResult = check modernClient->callTool({name: "arrayValue"});
    test:assertEquals(arrayResult["structuredContent"], <json>[1, 2, 3]);
    CallToolResult recordResult = check modernClient->callTool({name: "recordValue"});
    test:assertEquals(recordResult["structuredContent"], <json>{name: "Alice", age: 30});
    CallToolResult nullableResult = check modernClient->callTool({name: "nullableValue"});
    test:assertTrue(nullableResult.hasKey("structuredContent"));
    test:assertEquals(nullableResult["structuredContent"], ());
    CallToolResult textOnlyResult = check modernClient->callTool({name: "textOnlyValue"});
    test:assertFalse(textOnlyResult.hasKey("structuredContent"));
    check modernClient->close();

    StreamableHttpClient legacyClient = check new ("http://localhost:3207/regular", protocolMode = "legacy");
    _ = check legacyClient->connect();
    ListToolsResult legacyTools = check legacyClient->listTools();
    test:assertTrue(legacyTools.tools.every(toolInfo => toolInfo.outputSchema is ()));
    CallToolResult legacyResult = check legacyClient->callTool({name: "arrayValue"});
    test:assertFalse(legacyResult.hasKey("structuredContent"));
    check legacyClient->close();

    StreamableHttpClient genericClient = check new ("http://localhost:3207/generic", protocolMode = "modern");
    _ = check genericClient->connect();
    CallToolResult booleanResult = check genericClient->callTool({name: "booleanValue"});
    test:assertEquals(booleanResult["structuredContent"], true);
    check genericClient->close();
}

@test:Config {}
function testModernResultDiscriminationAndCorrelation() {
    WireResponse missingTag = {jsonrpc: JSONRPC_VERSION, id: 10, result: {"content": []}};
    test:assertTrue(protocolMessageResult(missingTag, 10, true, 200) is ResponseParsingError);
    test:assertTrue(protocolMessageResult(missingTag, 10, false, 200) is Result);
    WireResponse completeResponse = {jsonrpc: JSONRPC_VERSION, id: 11, result: {"resultType": "complete", "content": []}};
    test:assertTrue(protocolMessageResult(completeResponse, 10, true, 200) is ResponseParsingError);
    WireResponse unknownTag = {jsonrpc: JSONRPC_VERSION, id: 10, result: {"resultType": "unknown", "content": []}};
    test:assertTrue(protocolMessageResult(unknownTag, 10, true, 200) is ResponseParsingError);
}

@test:Config {}
function testModernProbeDoesNotDowngradeAuthenticationOrRecognizedErrors() {
    test:assertTrue(shouldUseLegacy(error HttpClientError("legacy rejection", statusCode = 400)));
    test:assertFalse(shouldUseLegacy(error HttpClientError("authentication required", statusCode = 401)));
    test:assertFalse(shouldUseLegacy(error HttpClientError("forbidden", statusCode = 403)));
    test:assertFalse(shouldUseLegacy(error HttpClientError("unavailable", statusCode = 503)));
    test:assertFalse(shouldUseLegacy(error HttpClientError("connection failed")));
    foreach int errorCode in [HEADER_MISMATCH, MISSING_REQUIRED_CLIENT_CAPABILITY] {
        JsonRpcError rpcError = createJsonRpcError(errorCode, "modern rejection", 1);
        test:assertFalse(shouldUseLegacy(error ServerResponseError("modern rejection", rpcError = rpcError)));
    }
}

@test:Config {}
function testModernRejectsLegacyInitializedNotification() returns error? {
    JsonRpcNotification notificationValue = {jsonrpc: JSONRPC_VERSION, method: NOTIFICATION_INITIALIZED};
    http:Response responseValue = check modernHttpClient->post("/mcp", notificationValue, headers = {
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: MODERN_PROTOCOL_VERSION
    });
    test:assertEquals(responseValue.statusCode, 400);
}

@test:Config {}
function testHeaderTraversalIgnoresSchemaDataArrays() returns error? {
    InputSchema toolSchema = {
        'type: "object",
        required: ["count"],
        properties: {
            count: {'type: "integer", "enum": [1, 2, 3]},
            payload: {'type: "object", "default": {"x-mcp-header": "literal data"}}
        }
    };
    map<string> headerValues = check toolParameterHeaders(toolSchema, {});
    test:assertEquals(headerValues.length(), 0);
}

@test:Config {}
function testModernErrorWithoutIdDoesNotTriggerLegacyFallback() returns error? {
    WireMessage errorMessage = check string `{"jsonrpc":"2.0","error":{"code":-32020,"message":"Missing required header"}}`.fromJsonStringWithType();
    Result|ClientError errorResult = protocolMessageResult(errorMessage, 10, true, 400);
    test:assertTrue(errorResult is ClientError);
    if errorResult is ClientError {
        test:assertFalse(shouldUseLegacy(errorResult));
    }
}

isolated function confirmTestElicitation(ElicitRequest inputRequest) returns ElicitResult|ClientError {
    return {action: "accept", content: {confirmed: true}};
}

@test:Config {}
function testHandlerCompletesFormElicitation() returns error? {
    // No capabilities passed to connect(): the configured handler advertises elicitation itself.
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp",
        elicitationHandler = confirmTestElicitation);
    _ = check modernClient->connect();
    CallToolResult callResult = check modernClient->callTool({name: "ask"});
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "accept:true:echo-only-state"});
    check modernClient->close();
}

isolated string[] handledMessages = [];

isolated function recordTestElicitation(ElicitRequest inputRequest) returns ElicitResult|ClientError {
    lock {
        handledMessages.push(inputRequest.params.message);
    }
    return {action: "accept", content: {confirmed: true}};
}

@test:Config {}
function testHandlerAnswersInputRequestsInServerOrder() returns error? {
    lock {
        handledMessages.removeAll();
    }
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp",
        elicitationHandler = recordTestElicitation);
    _ = check modernClient->connect();
    CallToolResult callResult = check modernClient->callTool({name: "survey"});
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "[\"alpha\",\"zeta\"]"});
    lock {
        test:assertEquals(handledMessages, ["First", "Second"]);
    }
    check modernClient->close();
}

@test:Config {}
function testHandlerCapabilityMergesWithConnectCapabilities() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp",
        elicitationHandler = confirmTestElicitation);
    // Declaring only form must not hide the URL mode the handler also answers.
    _ = check modernClient->connect(capabilities = {elicitation: {form: {}}});
    CallToolResult callResult = check modernClient->callTool({name: "openLink"});
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "connected"});
    check modernClient->close();
}

isolated string[] openedUrls = [];

isolated function openTestUrl(ElicitRequest inputRequest) returns ElicitResult|ClientError {
    FormElicitationParams|UrlElicitationParams params = inputRequest.params;
    if params !is UrlElicitationParams {
        return error ClientError("Expected a URL elicitation");
    }
    lock {
        openedUrls.push(params.url);
    }
    return {action: "accept"};
}

@test:Config {}
function testHandlerCompletesUrlElicitation() returns error? {
    lock {
        openedUrls.removeAll();
    }
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp", elicitationHandler = openTestUrl);
    _ = check modernClient->connect();
    CallToolResult callResult = check modernClient->callTool({name: "openLink"});
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "connected"});
    lock {
        test:assertEquals(openedUrls, ["https://example.com/connect"]);
    }
    check modernClient->close();
}

@test:Config {}
function testFormOnlyClientCannotReceiveUrlElicitation() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp");
    _ = check modernClient->connect(capabilities = {elicitation: {form: {}}});
    CallToolResult|InputRequiredResult|ClientError callResult = modernClient->callToolOnce({name: "openLink"});
    if callResult !is ServerResponseError {
        test:assertFail("Expected the missing-capability error");
    }
    JsonRpcError rpcError = check callResult.detail()["rpcError"].ensureType();
    test:assertEquals(rpcError.'error.code, MISSING_REQUIRED_CLIENT_CAPABILITY);
    test:assertEquals(rpcError.'error["data"], {requiredCapabilities: {elicitation: {url: {}}}});
    check modernClient->close();
}

// Answers every elicitation with content, even where the user submitted none.
isolated function overshareTestElicitation(ElicitRequest inputRequest) returns ElicitResult|ClientError {
    string message = inputRequest.params.message;
    "accept"|"decline"|"cancel" action = message == "decline" ? "decline" : message == "cancel" ? "cancel" : "accept";
    return {action, content: {confirmed: true}};
}

@test:Config {}
function testContinuationStripsContentTheUserDidNotSubmit() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp",
        elicitationHandler = overshareTestElicitation);
    _ = check modernClient->connect();
    CallToolResult callResult = check modernClient->callTool({name: "mixedAnswers"});
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "[\"accepted\"]"});
    check modernClient->close();
}

@test:Config {}
function testContinuationLimit() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp",
        elicitationHandler = confirmTestElicitation, maxInputRounds = 2);
    _ = check modernClient->connect();
    var exhaustedResult = modernClient->callTool({name: "loop"});
    test:assertTrue(exhaustedResult is ToolCallError);
    if exhaustedResult is ToolCallError {
        test:assertTrue(exhaustedResult.message().includes("Maximum input-required"));
    }
    check modernClient->close();
}

@test:Config {}
function testContinuationsStopAfterTenRoundsByDefault() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp",
        elicitationHandler = confirmTestElicitation);
    _ = check modernClient->connect();
    CallToolResult|ClientError exhaustedResult = modernClient->callTool({name: "count"});
    if exhaustedResult !is ToolCallError {
        test:assertFail("Expected a tool call error once the rounds ran out");
    }
    // The first call plus ten continuations: the error carries the eleventh result.
    InputRequiredResult lastResult = check exhaustedResult.detail()["inputRequired"].ensureType();
    test:assertEquals((lastResult.inputRequests ?: {})["again"]?.params?.message, "11");
    check modernClient->close();
}

@test:Config {}
function testStateOnlyContinuationOmitsInputResponses() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp");
    _ = check modernClient->connect();
    CallToolResult callResult = check modernClient->callTool({name: "probe"});
    TextContent text = check callResult.content[0].ensureType();
    test:assertTrue(text.text.startsWith("none|"), text.text);
    check modernClient->close();
}

@test:Config {}
function testContinuationEchoesRequestStateExactly() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp");
    _ = check modernClient->connect();
    CallToolResult callResult = check modernClient->callTool({name: "probe"});
    TextContent text = check callResult.content[0].ensureType();
    test:assertEquals(text.text.substring(<int>text.text.indexOf("|") + 1), PROBE_STATE);
    check modernClient->close();
}

@test:Config {}
function testContinuationOmitsRequestStateTheServerDidNotSend() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp",
        elicitationHandler = confirmTestElicitation);
    _ = check modernClient->connect();
    CallToolResult callResult = check modernClient->callTool({name: "dropState"});
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "absent"});
    check modernClient->close();
}

@test:Config {}
function testStateOnlyRoundsBackOffToACap() returns error? {
    lock {
        shedArrivals.removeAll();
    }
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp");
    _ = check modernClient->connect();
    CallToolResult callResult = check modernClient->callTool({name: "shed"});
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "served"});
    decimal[] arrivals;
    lock {
        arrivals = shedArrivals.clone();
    }
    test:assertEquals(arrivals.length(), 6);
    decimal[] minimumGaps = [0.05, 0.1, 0.2, 0.25, 0.25];
    foreach int i in 0 ..< minimumGaps.length() {
        decimal gap = arrivals[i + 1] - arrivals[i];
        test:assertTrue(gap >= minimumGaps[i], string `Round ${i + 1} retried after ${gap}s`);
    }
    // Capped: the last wait stays at 250 ms instead of doubling to 400 ms.
    test:assertTrue(arrivals[5] - arrivals[4] < 0.4d, string `Last retry after ${arrivals[5] - arrivals[4]}s`);
    check modernClient->close();
}

@test:Config {}
function testMissingClientCapabilityRemainsAModernError() returns error? {
    ClientCapabilities[] unsupportedCapabilities = [{}, {elicitation: {url: {}}}];
    foreach ClientCapabilities unsupportedCapability in unsupportedCapabilities {
        StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp");
        _ = check modernClient->connect(capabilities = unsupportedCapability);
        var callResult = modernClient->callToolOnce({name: "ask"});
        test:assertTrue(callResult is ServerResponseError);
        if callResult is ServerResponseError {
            var rpcValue = callResult.detail()["rpcError"];
            test:assertTrue(rpcValue is JsonRpcError);
            if rpcValue is JsonRpcError {
                test:assertEquals(rpcValue.'error.code, MISSING_REQUIRED_CLIENT_CAPABILITY);
            }
        }
        check modernClient->close();
    }
}

@test:Config {}
function testEmptyElicitationCapabilityRetainsFormCompatibility() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp");
    _ = check modernClient->connect(capabilities = {elicitation: {}});
    CallToolResult|InputRequiredResult callResult = check modernClient->callToolOnce({name: "ask"});
    test:assertTrue(callResult is InputRequiredResult);
    check modernClient->close();
}
