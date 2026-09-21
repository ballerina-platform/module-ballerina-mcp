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

// A deliberately misbehaving peer. A conforming MCP server cannot produce these
// responses, so the client-side rejection paths are only reachable through a mock.
const MISBEHAVING_SERVER_URL = "http://localhost:3210/mock";
const SUBSCRIPTION_ID_META_KEY = "io.modelcontextprotocol/subscriptionId";

isolated function mockUrl(string scenario) returns string => string `${MISBEHAVING_SERVER_URL}/${scenario}`;

isolated function mockJson(json body, int statusCode = 200) returns http:Response {
    http:Response mockResponse = new;
    mockResponse.statusCode = statusCode;
    mockResponse.setJsonPayload(body);
    return mockResponse;
}

// Counts calls per scenario so a mock can fail once and then succeed.
isolated map<int> mockCallCounts = {};

isolated function nextMockCall(string scenario) returns int {
    lock {
        int callNumber = (mockCallCounts[scenario] ?: 0) + 1;
        mockCallCounts[scenario] = callNumber;
        return callNumber;
    }
}

isolated function mockDiscoverResult(RequestId requestId, string[] supportedVersions = [MODERN_PROTOCOL_VERSION],
        boolean includeCacheHints = true, string? instructions = ()) returns http:Response {
    map<json> resultValue = {
        "resultType": "complete",
        "supportedVersions": supportedVersions,
        "capabilities": {"tools": {"listChanged": false}},
        "_meta": {[SERVER_INFO_META_KEY]: {"name": "mock", "version": "1"}}
    };
    if includeCacheHints {
        resultValue["ttlMs"] = 0;
        resultValue["cacheScope"] = "private";
    }
    if instructions is string {
        resultValue["instructions"] = instructions;
    }
    return mockJson({"jsonrpc": JSONRPC_VERSION, "id": requestId, "result": resultValue});
}

isolated function mockToolListResult(RequestId requestId, json tools, json? nextCursor = (),
        boolean includeCacheHints = true) returns http:Response {
    map<json> resultValue = {"resultType": "complete", "tools": tools};
    if includeCacheHints {
        resultValue["ttlMs"] = 0;
        resultValue["cacheScope"] = "private";
    }
    if nextCursor !is () {
        resultValue["nextCursor"] = nextCursor;
    }
    return mockJson({"jsonrpc": JSONRPC_VERSION, "id": requestId, "result": resultValue});
}

// Emits a fixed list of SSE payloads and then completes.
class MockSseIterator {
    private string[] payloads;
    private int index = 0;

    isolated function init(string[] payloads) {
        self.payloads = payloads;
    }

    public isolated function next() returns record {|http:SseEvent value;|}? {
        if self.index >= self.payloads.length() {
            return;
        }
        string payload = self.payloads[self.index];
        self.index += 1;
        return {value: {data: payload}};
    }
}

class MockEventOnlyIterator {
    private boolean sent = false;

    public isolated function next() returns record {|http:SseEvent value;|}? {
        lock {
            if self.sent {
                return;
            }
            self.sent = true;
            return {value: {event: "ping"}};
        }
    }
}

isolated function mockSse(string[] payloads) returns http:Response {
    MockSseIterator iterator = new (payloads);
    stream<http:SseEvent, error?> eventStream = new (iterator);
    http:Response sseResponse = new;
    sseResponse.setSseEventStream(eventStream);
    return sseResponse;
}

isolated function mockAckEvent(RequestId subscriptionId, json acceptedFilter) returns string =>
    string `{"jsonrpc":"2.0","method":"notifications/subscriptions/acknowledged","params":` +
        string `{"_meta":{"${SUBSCRIPTION_ID_META_KEY}":${subscriptionId.toString()}},` +
        string `"notifications":${acceptedFilter.toJsonString()}}}`;

isolated function mockNotificationEvent(string method, RequestId subscriptionId) returns string =>
    string `{"jsonrpc":"2.0","method":"${method}","params":` +
        string `{"_meta":{"${SUBSCRIPTION_ID_META_KEY}":${subscriptionId.toString()}}}}`;

isolated function mockCompletionEvent(RequestId subscriptionId, string resultType = "complete") returns string =>
    string `{"jsonrpc":"2.0","id":${subscriptionId.toString()},"result":{"resultType":"${resultType}"}}`;

service /mock on new http:Listener(3210) {

    resource function post [string scenario](http:Request request) returns http:Response|error {
        json payload = check request.getJsonPayload();
        JsonRpcRequest|error parsedRequest = payload.cloneWithType();
        if parsedRequest is error {
            // Notifications carry no id and expect no body in return.
            http:Response acknowledgement = new;
            acknowledgement.statusCode = http:STATUS_ACCEPTED;
            return acknowledgement;
        }
        JsonRpcRequest requestMessage = parsedRequest;
        RequestId requestId = requestMessage.id;
        string method = requestMessage.method;

        if method == "server/discover" {
            match scenario {
                "noCacheHints" => {
                    return mockDiscoverResult(requestId, includeCacheHints = false);
                }
                "legacyOnly" => {
                    return mockDiscoverResult(requestId, [LATEST_LEGACY_PROTOCOL_VERSION]);
                }
                "nonJson" => {
                    http:Response textResponse = new;
                    textResponse.setTextPayload("not json at all");
                    return textResponse;
                }
                "malformedJson" => {
                    return mockJson({"jsonrpc": JSONRPC_VERSION, "unexpected": true});
                }
                "idMismatch" => {
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": 9999,
                        "result": {"resultType": "complete", "ttlMs": 0, "cacheScope": "private"}
                    });
                }
                "errorIdMismatch" => {
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": 9999,
                        "error": {"code": INTERNAL_ERROR, "message": "boom"}
                    }, 500);
                }
                "successWithErrorStatus" => {
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": requestId,
                        "result": {"resultType": "complete", "ttlMs": 0, "cacheScope": "private"}
                    }, 418);
                }
                "sseNoFinalResponse" => {
                    return mockSse([
                        string `{"jsonrpc":"2.0","method":"notifications/progress"}`
                    ]);
                }
                "sseNotificationThenResult" => {
                    return mockSse([
                        "",
                        string `{"jsonrpc":"2.0","method":"notifications/progress"}`,
                        string `{"jsonrpc":"2.0","id":${requestId.toString()},"result":{"resultType":"complete","ttlMs":0,` +
                            string `"cacheScope":"private","supportedVersions":["${MODERN_PROTOCOL_VERSION}"],"capabilities":{}}}`
                    ]);
                }
                "sseMalformedEvent" => {
                    return mockSse(["{not-json"]);
                }
                "withInstructions" => {
                    return mockDiscoverResult(requestId, instructions = "Call echo first.");
                }
            }
            return mockDiscoverResult(requestId);
        }

        if method == REQUEST_INITIALIZE {
            if scenario == "legacyBadInit" {
                return mockJson({"jsonrpc": JSONRPC_VERSION, "id": requestId, "result": {"tools": []}});
            }
            return mockJson({
                "jsonrpc": JSONRPC_VERSION,
                "id": requestId,
                "result": {
                    "protocolVersion": scenario == "legacyBadVersion" ? "1999-01-01" : LATEST_LEGACY_PROTOCOL_VERSION,
                    "capabilities": {},
                    "serverInfo": {"name": "mock", "version": "1"}
                }
            });
        }

        if method == "subscriptions/listen" {
            match scenario {
                "subNoAck" => {
                    return mockSse([mockNotificationEvent("notifications/tools/list_changed", requestId)]);
                }
                "subBadFilter" => {
                    return mockSse([mockAckEvent(requestId, {"promptsListChanged": true})]);
                }
                "subWrongId" => {
                    return mockSse([
                        mockAckEvent(requestId, {"toolsListChanged": true}),
                        mockNotificationEvent("notifications/tools/list_changed", 9999)
                    ]);
                }
                "subDisallowed" => {
                    return mockSse([
                        mockAckEvent(requestId, {"toolsListChanged": true}),
                        mockNotificationEvent("notifications/prompts/list_changed", requestId)
                    ]);
                }
                "subError" => {
                    return mockSse([
                        string `{"jsonrpc":"2.0","id":${requestId.toString()},` +
                            string `"error":{"code":${INTERNAL_ERROR},"message":"subscription failed"}}`
                    ]);
                }
                "subEarlyComplete" => {
                    return mockSse([mockCompletionEvent(requestId)]);
                }
                "subBadComplete" => {
                    return mockSse([
                        mockAckEvent(requestId, {"toolsListChanged": true}),
                        mockCompletionEvent(requestId, "partial")
                    ]);
                }
                "subDisconnect" => {
                    return mockSse([mockAckEvent(requestId, {"toolsListChanged": true})]);
                }
                "subUnexpected" => {
                    return mockSse([string `{"jsonrpc":"2.0","id":7,"method":"ping"}`]);
                }
                "subComplete" => {
                    return mockSse([
                        mockAckEvent(requestId, {"toolsListChanged": true}),
                        mockNotificationEvent("notifications/tools/list_changed", requestId),
                        mockCompletionEvent(requestId)
                    ]);
                }
                "subNotSse" => {
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": requestId,
                        "error": {"code": INVALID_PARAMS, "message": "Invalid subscription filter"}
                    }, 400);
                }
            }
            return mockSse([mockAckEvent(requestId, {"toolsListChanged": true}), mockCompletionEvent(requestId)]);
        }

        if method == REQUEST_LIST_TOOLS {
            match scenario {
                "legacyErrorStatus" => {
                    return mockJson({"error": "unavailable"}, 503);
                }
                "legacyAccepted" => {
                    http:Response acceptedResponse = new;
                    acceptedResponse.statusCode = http:STATUS_ACCEPTED;
                    return acceptedResponse;
                }
                "legacyTextResponse" => {
                    http:Response textResponse = new;
                    textResponse.setTextPayload("plain text body");
                    return textResponse;
                }
                "legacyBadJson" => {
                    return mockJson({"not": "a json-rpc message"});
                }
                "legacyWrongResult" => {
                    return mockJson({"jsonrpc": JSONRPC_VERSION, "id": requestId, "result": {"content": []}});
                }
                "legacySseResult" => {
                    return mockSse([
                        string `{"jsonrpc":"2.0","id":${requestId.toString()},"result":{"tools":[]}}`
                    ]);
                }
                "noToolListCacheHints" => {
                    return mockToolListResult(requestId, [], includeCacheHints = false);
                }
                "malformedToolList" => {
                    return mockToolListResult(requestId, "not-an-array");
                }
                "cursorLoop" => {
                    return mockToolListResult(requestId, [], "same-cursor");
                }
                "unknownTool" => {
                    return mockToolListResult(requestId, []);
                }
                "paginatedTool" => {
                    RequestParams listParams = requestMessage.params ?: {};
                    if listParams["cursor"] is () {
                        return mockToolListResult(requestId, [], "page-2");
                    }
                    return mockToolListResult(requestId,
                            [{"name": "paged", "inputSchema": {"type": "object"}}]);
                }
                "unmirrorableTool" => {
                    // Duplicate mirrored header names are rejected, so the tool is skipped.
                    return mockToolListResult(requestId, [
                        {
                            "name": "conflicting",
                            "inputSchema": {
                                "type": "object",
                                "properties": {
                                    "first": {"type": "string", "x-mcp-header": "Region"},
                                    "second": {"type": "string", "x-mcp-header": "region"}
                                }
                            }
                        }
                    ]);
                }
                "missingStructured" => {
                    return mockToolListResult(requestId, [
                        {"name": "structured", "inputSchema": {"type": "object"}, "outputSchema": {"type": "object"}}
                    ]);
                }
            }
            return mockToolListResult(requestId, [{"name": "echo", "inputSchema": {"type": "object"}}]);
        }

        if method == REQUEST_CALL_TOOL {
            match scenario {
                "inputRequiredNoHandler" => {
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": requestId,
                        "result": {
                            "resultType": "input_required",
                            "inputRequests": {
                                "answer": {
                                    "method": "elicitation/create",
                                    "params": {"mode": "form", "message": "Confirm"}
                                }
                            }
                        }
                    });
                }
                "unknownResultType" => {
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": requestId,
                        "result": {"resultType": "partial", "content": []}
                    });
                }
                "headerMismatchRetry" => {
                    if nextMockCall(scenario) == 1 {
                        return mockJson({
                            "jsonrpc": JSONRPC_VERSION,
                            "id": requestId,
                            "error": {"code": HEADER_MISMATCH, "message": "Mcp-Name must match the tool name"}
                        }, 400);
                    }
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": requestId,
                        "result": {"resultType": "complete", "content": []}
                    });
                }
                "legacyWrongResult" => {
                    return mockJson({"jsonrpc": JSONRPC_VERSION, "id": requestId, "result": {"tools": []}});
                }
                "badToolResult" => {
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": requestId,
                        "result": {"resultType": "input_required"}
                    });
                }
                "malformedToolResult" => {
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": requestId,
                        "result": {"resultType": "complete", "content": "not-an-array"}
                    });
                }
                "missingStructured" => {
                    return mockJson({
                        "jsonrpc": JSONRPC_VERSION,
                        "id": requestId,
                        "result": {"resultType": "complete", "content": []}
                    });
                }
            }
            return mockJson({
                "jsonrpc": JSONRPC_VERSION,
                "id": requestId,
                "result": {"resultType": "complete", "content": []}
            });
        }

        return mockJson({
            "jsonrpc": JSONRPC_VERSION,
            "id": requestId,
            "error": {"code": METHOD_NOT_FOUND, "message": "Method not found"}
        }, 404);
    }

    resource function get [string scenario]() returns http:Response {
        if scenario == "sseMalformedStream" {
            return mockSse(["{not-json"]);
        }
        if scenario == "sseMissingData" {
            MockEventOnlyIterator iterator = new;
            stream<http:SseEvent, error?> eventStream = new (iterator);
            http:Response sseResponse = new;
            sseResponse.setSseEventStream(eventStream);
            return sseResponse;
        }
        return mockSse([
            string `{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}`
        ]);
    }

    resource function delete [string scenario]() returns http:Response {
        http:Response deleteResponse = new;
        // 405 signals a peer that does not support session termination.
        deleteResponse.statusCode = scenario == "noTermination" ? 405 : 200;
        return deleteResponse;
    }
}

@test:Config {}
function testClientInitRejectsInvalidConfiguration() {
    StreamableHttpClient|ClientError negativeRounds = new (mockUrl("ok"), maxInputRounds = -1);
    test:assertTrue(negativeRounds is ClientInitializationError);

    StreamableHttpClient|ClientError modernWithSession = new (mockUrl("ok"), protocolMode = "modern",
        sessionId = "legacy-session"
    );
    test:assertTrue(modernWithSession is ClientInitializationError);

    StreamableHttpClient|ClientError badUrl = new ("htp://localhost:9");
    test:assertTrue(badUrl is ClientError);
    if badUrl is ClientError {
        test:assertTrue(badUrl.message().includes("Unable to initialize HTTP client"));
    }
}

@test:Config {}
function testModernClientRejectsInvalidDiscovery() returns error? {
    StreamableHttpClient missingHints = check new (mockUrl("noCacheHints"), protocolMode = "modern");
    var missingHintsResult = missingHints->connect();
    test:assertTrue(missingHintsResult is ResponseParsingError);

    StreamableHttpClient legacyOnly = check new (mockUrl("legacyOnly"), protocolMode = "modern");
    var legacyOnlyResult = legacyOnly->connect();
    test:assertTrue(legacyOnlyResult is ProtocolVersionError);
    if legacyOnlyResult is ProtocolVersionError {
        test:assertTrue(legacyOnlyResult.message().includes("does not support the modern protocol version"));
    }
}

@test:Config {}
function testAdoptDiscoveryValidation() returns error? {
    StreamableHttpClient legacyClient = check new (mockUrl("ok"), protocolMode = "modern");
    DiscoverResult legacyDiscovery = {supportedVersions: [LATEST_LEGACY_PROTOCOL_VERSION], capabilities: {}};
    var adoptResult = legacyClient.adoptDiscovery(legacyDiscovery);
    test:assertTrue(adoptResult is ProtocolVersionError);

    StreamableHttpClient modernClient = check new (mockUrl("ok"), protocolMode = "modern");
    _ = check modernClient->connect();
    var reAdoptResult = modernClient.adoptDiscovery({
        supportedVersions: [MODERN_PROTOCOL_VERSION],
        capabilities: {}
    });
    test:assertTrue(reAdoptResult is ClientInitializationError);

    var reInitializeResult = modernClient->initializeLegacy();
    test:assertTrue(reInitializeResult is ClientInitializationError);
    check modernClient->close();
}

@test:Config {}
function testModernClientRejectsMalformedHttpResponses() returns error? {
    map<string> expectedMessages = {
        "nonJson": "non-JSON response",
        "malformedJson": "Malformed JSON-RPC response",
        "idMismatch": "JSON-RPC response ID does not match the request",
        "errorIdMismatch": "JSON-RPC error response ID does not match the request",
        "successWithErrorStatus": "HTTP error response contained a success result",
        "sseNoFinalResponse": "Response stream ended before a final response",
        "sseMalformedEvent": "Malformed JSON-RPC SSE event"
    };
    foreach var [scenario, expectedMessage] in expectedMessages.entries() {
        StreamableHttpClient mockClient = check new (mockUrl(scenario), protocolMode = "modern");
        var discoverResult = mockClient->discover();
        test:assertTrue(discoverResult is ClientError, string `${scenario} should fail`);
        if discoverResult is ClientError {
            test:assertTrue(discoverResult.message().includes(expectedMessage),
                    string `${scenario}: unexpected message '${discoverResult.message()}'`);
        }
    }
}

@test:Config {}
function testModernClientSkipsNotificationsInSseResponses() returns error? {
    StreamableHttpClient mockClient = check new (mockUrl("sseNotificationThenResult"), protocolMode = "modern");
    DiscoverResult discovered = check mockClient->discover();
    test:assertEquals(discovered.supportedVersions, [MODERN_PROTOCOL_VERSION]);
}

@test:Config {}
function testModernClientRejectsInvalidToolListResults() returns error? {
    StreamableHttpClient missingHints = check new (mockUrl("noToolListCacheHints"), protocolMode = "modern");
    _ = check missingHints->connect();
    var missingHintsResult = missingHints->listTools();
    test:assertTrue(missingHintsResult is ListToolsError);
    if missingHintsResult is ListToolsError {
        test:assertEquals(missingHintsResult.message(), "Invalid modern tools/list result");
    }

    StreamableHttpClient malformed = check new (mockUrl("malformedToolList"), protocolMode = "modern");
    _ = check malformed->connect();
    var malformedResult = malformed->listTools();
    test:assertTrue(malformedResult is ListToolsError);
    if malformedResult is ListToolsError {
        test:assertTrue(malformedResult.message().startsWith("Invalid modern tools/list result: "));
    }
}

@test:Config {}
function testModernClientToolLookupAcrossPages() returns error? {
    StreamableHttpClient paginated = check new (mockUrl("paginatedTool"), protocolMode = "modern");
    _ = check paginated->connect();
    CallToolResult pagedResult = check paginated->callTool({name: "paged"});
    test:assertEquals(pagedResult.content, []);

    StreamableHttpClient looping = check new (mockUrl("cursorLoop"), protocolMode = "modern");
    _ = check looping->connect();
    var loopResult = looping->callTool({name: "never-listed"});
    test:assertTrue(loopResult is ToolCallError);
    if loopResult is ToolCallError {
        test:assertTrue(loopResult.message().includes("Tool pagination repeated a cursor"));
    }

    StreamableHttpClient unknown = check new (mockUrl("unknownTool"), protocolMode = "modern");
    _ = check unknown->connect();
    var unknownResult = unknown->callTool({name: "absent"});
    test:assertTrue(unknownResult is ToolCallError);
    if unknownResult is ToolCallError {
        test:assertTrue(unknownResult.message().includes("Tool is unavailable"));
    }

    // Tools with conflicting mirrored headers are dropped from the listing entirely.
    StreamableHttpClient unmirrorable = check new (mockUrl("unmirrorableTool"), protocolMode = "modern");
    _ = check unmirrorable->connect();
    ListToolsResult filteredTools = check unmirrorable->listTools();
    test:assertEquals(filteredTools.tools, []);
}

@test:Config {}
function testModernClientRejectsInvalidToolResults() returns error? {
    StreamableHttpClient badResult = check new (mockUrl("badToolResult"), protocolMode = "modern");
    _ = check badResult->connect();
    var inputRequiredResult = badResult->callToolOnce({name: "echo"});
    test:assertTrue(inputRequiredResult is ToolCallError);
    if inputRequiredResult is ToolCallError {
        test:assertEquals(inputRequiredResult.message(), "Invalid input-required result");
    }

    StreamableHttpClient malformed = check new (mockUrl("malformedToolResult"), protocolMode = "modern");
    _ = check malformed->connect();
    var malformedResult = malformed->callTool({name: "echo"});
    test:assertTrue(malformedResult is ToolCallError);
    if malformedResult is ToolCallError {
        test:assertEquals(malformedResult.message(), "Invalid tool result");
    }

    StreamableHttpClient missingStructured = check new (mockUrl("missingStructured"), protocolMode = "modern");
    _ = check missingStructured->connect();
    var missingStructuredResult = missingStructured->callTool({name: "structured"});
    test:assertTrue(missingStructuredResult is ToolCallError);
    if missingStructuredResult is ToolCallError {
        test:assertTrue(missingStructuredResult.message().includes("omitted structuredContent"));
    }
}

@test:Config {}
function testModernClientRejectsTaskAugmentedCalls() returns error? {
    StreamableHttpClient modernClient = check new (mockUrl("ok"), protocolMode = "modern");
    _ = check modernClient->connect();
    var taskResult = modernClient->callToolOnce({name: "echo", task: {ttl: 1000}});
    test:assertTrue(taskResult is ToolCallError);
    if taskResult is ToolCallError {
        test:assertTrue(taskResult.message().includes("Legacy task parameters cannot be sent"));
    }
    check modernClient->close();
}

@test:Config {}
function testOperationsBeforeConnectAreRejected() returns error? {
    StreamableHttpClient modernClient = check new (mockUrl("ok"), protocolMode = "modern");
    var listResult = modernClient->listTools();
    test:assertTrue(listResult is ClientInitializationError);
    var callResult = modernClient->callTool({name: "echo"});
    test:assertTrue(callResult is ClientInitializationError);
    var listenResult = modernClient->listen();
    test:assertTrue(listenResult is ClientInitializationError);
}

@test:Config {}
function testLegacySessionReconnectSkipsHandshake() returns error? {
    StreamableHttpClient reconnectClient = check new (mockUrl("ok"), sessionId = "existing-session");
    ConnectionInfo connection = check reconnectClient->connect();
    test:assertEquals(connection.protocolVersion, LATEST_LEGACY_PROTOCOL_VERSION);

    // A legacy peer streams notifications over the GET event stream.
    stream<JsonRpcMessage, StreamError?> eventStream = check reconnectClient->listen();
    var firstEvent = check eventStream.next();
    test:assertTrue(firstEvent is record {|JsonRpcMessage value;|});
    check eventStream.close();
    check reconnectClient->close();
}

@test:Config {}
function testCloseTreatsSessionTerminationNotSupportedAsSuccess() returns error? {
    StreamableHttpClient terminationClient = check new (mockUrl("noTermination"), sessionId = "existing-session");
    _ = check terminationClient->connect();
    ClientError? closeError = terminationClient->close();
    test:assertTrue(closeError is (), closeError is ClientError ? closeError.message() : "");
}

@test:Config {}
function testModernClientRequiresAnInputHandlerForContinuations() returns error? {
    StreamableHttpClient noHandler = check new (mockUrl("inputRequiredNoHandler"), protocolMode = "modern");
    _ = check noHandler->connect(capabilities = {elicitation: {form: {}}});
    var callResult = noHandler->callTool({name: "echo"});
    test:assertTrue(callResult is ToolCallError);
    if callResult is ToolCallError {
        test:assertTrue(callResult.message().includes("Input handler is not configured"));
        test:assertTrue(callResult.detail()["inputRequired"] is InputRequiredResult);
    }
}

@test:Config {}
function testModernClientRejectsUnknownResultTypes() returns error? {
    StreamableHttpClient unknownType = check new (mockUrl("unknownResultType"), protocolMode = "modern");
    _ = check unknownType->connect();
    // An unrecognised discriminator is rejected while decoding, before the tool result is interpreted.
    var callResult = unknownType->callTool({name: "echo"});
    test:assertTrue(callResult is ResponseParsingError);
    if callResult is ResponseParsingError {
        test:assertEquals(callResult.message(), "Unsupported resultType");
    }
}

@test:Config {}
function testModernClientRefreshesToolSchemasOnHeaderMismatch() returns error? {
    StreamableHttpClient retryClient = check new (mockUrl("headerMismatchRetry"), protocolMode = "modern");
    _ = check retryClient->connect();
    // The first attempt is rejected as a header mismatch; the client re-lists tools and retries once.
    CallToolResult callResult = check retryClient->callTool({name: "echo"});
    test:assertEquals(callResult.content, []);
}

@test:Config {}
function testDiscoveredInstructionsReachTheConnectionInfo() returns error? {
    StreamableHttpClient guidedClient = check new (mockUrl("withInstructions"), protocolMode = "modern");
    ConnectionInfo connection = check guidedClient->connect();
    test:assertEquals(connection.instructions, "Call echo first.");
}

@test:Config {}
function testLegacyCallToolOnceDelegatesToCallTool() returns error? {
    StreamableHttpClient legacyClient = check new (mockUrl("ok"), sessionId = "legacy-session");
    _ = check legacyClient->connect();
    CallToolResult|InputRequiredResult callResult = check legacyClient->callToolOnce({name: "echo"});
    test:assertTrue(callResult is CallToolResult);
}

@test:Config {}
function testAdditionalRequestHeadersAreReconciledWithProtocolHeaders() returns error? {
    StreamableHttpClient modernClient = check new (mockUrl("ok"), protocolMode = "modern");
    _ = check modernClient->connect();

    // Transport-owned headers supplied by the caller are dropped rather than forwarded.
    ListToolsResult toolList = check modernClient->listTools({
        [SESSION_ID_HEADER]: "ignored",
        "last-event-id": "ignored",
        "x-trace-id": "trace-1"
    });
    test:assertEquals(toolList.tools.length(), 1);

    // A caller header that contradicts a generated protocol header is a client error.
    var conflictResult = modernClient->listTools({[METHOD_HEADER]: "server/discover"});
    test:assertTrue(conflictResult is HttpClientError);
    if conflictResult is HttpClientError {
        test:assertTrue(conflictResult.message().includes("conflicts with generated protocol header"));
    }
    check modernClient->close();
}
