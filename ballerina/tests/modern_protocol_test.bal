import ballerina/http;
import ballerina/test;

@StreamableHttpServiceConfig {info: {name: "modern-test", version: "1"}}
service ProtocolService /mcp on new StreamableHttpListener(3205) {
    remote isolated function onListTools() returns ProtocolListToolsResult {
        return {tools: [
            {name: "scalar", inputSchema: {'type: "object"}, outputSchema: {"type": "integer"}},
            {name: "echo", inputSchema: {'type: "object", properties: {
                region: {'type: "string", "x-mcp-header": "Region"}}}},
            {name: "continue", inputSchema: {'type: "object"}}
        ]};
    }
    remote isolated function onCallTool(CallToolParams callParams) returns ProtocolCallToolResult|InputRequiredResult {
        if callParams.name == "scalar" {
            return {resultType: "complete", content: [], structuredContent: 42};
        }
        if callParams.name == "continue" && callParams.requestState is () {
            return {resultType: "input_required", requestState: "opaque-state"};
        }
        return {resultType: "complete", content: [{'type: "text", text: callParams.requestState ?: "ok"}]};
    }
}

final http:Client modernHttpClient = check new ("http://localhost:3205");

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
    check modernClient->initialize();
    ProtocolListToolsResult toolList = check modernClient->listToolsWithSchemas();
    test:assertEquals(toolList.tools.length(), 3);
    ProtocolCallToolResult|InputRequiredResult scalarResult = check modernClient->callToolWithResult({name: "scalar"});
    test:assertTrue(scalarResult is ProtocolCallToolResult);
    if scalarResult is ProtocolCallToolResult {
        test:assertEquals(scalarResult?.structuredContent, 42);
    }
    var echoResult = check modernClient->callToolWithResult({name: "echo", arguments: {"region": "世界"}});
    test:assertTrue(echoResult is ProtocolCallToolResult);
    CallToolResult continuedResult = check modernClient->callTool({name: "continue"});
    test:assertEquals(continuedResult.content[0], <TextContent>{'type: "text", text: "opaque-state"});
    check modernClient->close();
}

@test:Config {}
function testProtocolHeaderEncoding() returns error? {
    foreach string headerValue in ["north", "世界", " padded ", "line\nbreak", "=?base64?literal?="] {
        test:assertEquals(check decodeProtocolHeader(encodeProtocolHeader(headerValue)), headerValue);
    }
    test:assertTrue(decodeProtocolHeader("bad\nvalue") is Error);
    test:assertTrue(toolParameterHeaders({'type: "object", properties: {
        first: {'type: "string", "x-mcp-header": "Region"},
        second: {'type: "string", "x-mcp-header": "region"}
    }}, {}) is Error);
}
