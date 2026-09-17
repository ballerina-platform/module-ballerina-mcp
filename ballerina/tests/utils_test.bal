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

import ballerina/test;

// Replays a fixed sequence of messages, then optionally fails or completes.
class ReplayMessageIterator {
    private JsonRpcMessage[] messages;
    private StreamError? terminalError;
    private int index = 0;

    isolated function init(JsonRpcMessage[] messages, StreamError? terminalError = ()) {
        self.messages = messages;
        self.terminalError = terminalError;
    }

    public isolated function next() returns record {|JsonRpcMessage value;|}|StreamError? {
        if self.index >= self.messages.length() {
            return self.terminalError;
        }
        JsonRpcMessage message = self.messages[self.index];
        self.index += 1;
        return {value: message};
    }
}

isolated function replayStream(JsonRpcMessage[] messages, StreamError? terminalError = ())
        returns stream<JsonRpcMessage, StreamError?> {
    ReplayMessageIterator iterator = new (messages, terminalError);
    return new (iterator);
}

@test:Config {}
function testExtractResultFromMessage() {
    JsonRpcResponse successResponse = {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        result: <ListToolsResult>{tools: []}
    };
    ServerResult|ServerResponseError successResult = extractResultFromMessage(successResponse);
    test:assertTrue(successResult is ListToolsResult);

    JsonRpcError errorResponse = {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        'error: {code: INVALID_REQUEST, message: "bad request"}
    };
    ServerResult|ServerResponseError errorResult = extractResultFromMessage(errorResponse);
    test:assertTrue(errorResult is ServerResponseError);
    if errorResult is ServerResponseError {
        test:assertTrue(errorResult.message().includes("Received JSON-RPC error from server"));
    }

    JsonRpcNotification notification = {jsonrpc: JSONRPC_VERSION, method: NOTIFICATION_INITIALIZED};
    test:assertTrue(extractResultFromMessage(notification) is InvalidMessageTypeError);
}

@test:Config {}
function testProcessServerResponseVariants() {
    JsonRpcResponse successResponse = {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        result: <ListToolsResult>{tools: []}
    };
    test:assertTrue(processServerResponse(successResponse) is ListToolsResult);

    // A stream skips notifications until the first response arrives.
    JsonRpcNotification notification = {jsonrpc: JSONRPC_VERSION, method: NOTIFICATION_INITIALIZED};
    test:assertTrue(processServerResponse(replayStream([notification, successResponse])) is ListToolsResult);

    // A stream that ends without a response is reported as an invalid message type.
    test:assertTrue(processServerResponse(replayStream([notification])) is InvalidMessageTypeError);

    // A stream error is surfaced verbatim.
    StreamError streamFailure = error SseEventStreamError("connection reset");
    var streamResult = processServerResponse(replayStream([], streamFailure));
    test:assertTrue(streamResult is StreamError);

    test:assertTrue(processServerResponse(()) is MalformedResponseError);

    var transportResult = processServerResponse(error HttpClientError("socket closed"));
    test:assertTrue(transportResult is ServerResponseError);
    if transportResult is ServerResponseError {
        test:assertTrue(transportResult.message().includes("Transport error connecting to server"));
    }
}

@test:Config {}
function testApplicationResultStripsWireOnlyFields() {
    Result wireResult = {
        "resultType": "complete",
        "ttlMs": 5000,
        "cacheScope": "public",
        "tools": []
    };
    Result applicationValue = applicationResult(wireResult);
    test:assertFalse(applicationValue.hasKey("resultType"));
    test:assertFalse(applicationValue.hasKey("ttlMs"));
    test:assertFalse(applicationValue.hasKey("cacheScope"));
    test:assertFalse(applicationValue.hasKey("_meta"));
    test:assertEquals(applicationValue["tools"], <json>[]);

    Result preservedValue = applicationResult(wireResult, preserveCacheHints = true);
    test:assertEquals(preservedValue["ttlMs"], 5000);
    test:assertEquals(preservedValue["cacheScope"], "public");
    test:assertFalse(preservedValue.hasKey("resultType"));
}

@test:Config {}
function testApplicationResultLiftsWireServerInfo() {
    Result wireResult = {
        _meta: {[SERVER_INFO_META_KEY]: <Implementation>{name: "srv", version: "2.0.0"}},
        "resultType": "complete"
    };
    Result applicationValue = applicationResult(wireResult);
    ResultMetaObject resultMeta = applicationValue._meta ?: {};
    test:assertFalse(resultMeta.hasKey(SERVER_INFO_META_KEY));
    test:assertEquals(resultMeta.serverInfo?.name, "srv");
    test:assertEquals(resultMeta.serverInfo?.version, "2.0.0");

    // A malformed wire serverInfo is dropped rather than surfaced.
    Result malformedResult = applicationResult({_meta: {[SERVER_INFO_META_KEY]: <map<anydata>>{"version": 7}}});
    test:assertFalse(malformedResult.hasKey("_meta"));

    // Unrelated metadata entries survive.
    Result otherMetaResult = applicationResult({_meta: {"vendor/custom": "value"}});
    ResultMetaObject otherMeta = otherMetaResult._meta ?: {};
    test:assertEquals(otherMeta["vendor/custom"], "value");
}

@test:Config {}
function testLegacyToolListResultDropsNonObjectOutputSchemas() returns error? {
    ListToolsResult modernResult = {
        "resultType": "complete",
        ttlMs: 0,
        cacheScope: "private",
        tools: [
            {name: "objectOut", inputSchema: {'type: "object"}, outputSchema: {"type": "object"}},
            {name: "scalarOut", inputSchema: {'type: "object"}, outputSchema: {"type": "integer"}},
            {name: "noOut", inputSchema: {'type: "object"}}
        ]
    };
    ListToolsResult legacyResult = check legacyToolListResult(modernResult);
    test:assertFalse(legacyResult.hasKey("resultType"));
    test:assertFalse(legacyResult.hasKey("ttlMs"));
    test:assertFalse(legacyResult.hasKey("cacheScope"));

    map<ToolDefinition> toolsByName = {};
    foreach ToolDefinition toolInfo in legacyResult.tools {
        toolsByName[toolInfo.name] = toolInfo;
    }
    test:assertEquals((check toolsByName["objectOut"].ensureType(ToolDefinition)).outputSchema, {"type": "object"});
    test:assertEquals((check toolsByName["scalarOut"].ensureType(ToolDefinition)).outputSchema, ());
    test:assertEquals((check toolsByName["noOut"].ensureType(ToolDefinition)).outputSchema, ());
}

@test:Config {}
function testLegacyToolCallResultDropsNonObjectStructuredContent() returns error? {
    CallToolResult objectResult = check legacyToolCallResult({
        resultType: "complete",
        content: [],
        structuredContent: {"value": 1}
    });
    test:assertEquals(objectResult["structuredContent"], <json>{"value": 1});
    test:assertFalse(objectResult.hasKey("resultType"));

    CallToolResult scalarResult = check legacyToolCallResult({
        resultType: "complete",
        content: [],
        structuredContent: 42
    });
    test:assertFalse(scalarResult.hasKey("structuredContent"));

    CallToolResult noneResult = check legacyToolCallResult({content: []});
    test:assertFalse(noneResult.hasKey("structuredContent"));
}
