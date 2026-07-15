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

const string PYTHON_COMMAND = "python3";
const string MOCK_STDIO_SERVER = "tests/resources/mock_stdio_server.py";

isolated function createInitializeJsonRpcRequest(int requestId) returns JsonRpcRequest {
    return {
        jsonrpc: JSONRPC_VERSION,
        id: requestId,
        method: REQUEST_INITIALIZE,
        params: {
            "protocolVersion": LATEST_PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": {name: "stdio-transport-test", version: "0.1.0"}
        }
    };
}

@test:Config {groups: ["stdio"]}
isolated function testStdioTransportRequestResponseLifecycle() returns error? {
    StdioClientTransport transport = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER]);

    JsonRpcMessage? initializeResponse = check transport.sendMessage(createInitializeJsonRpcRequest(1));
    if initializeResponse !is JsonRpcResponse {
        test:assertFail("Expected a JsonRpcResponse for the initialize request.");
    }
    test:assertEquals(initializeResponse.id, 1);
    ServerResult initializeResult = initializeResponse.result;
    if initializeResult !is InitializeResult {
        test:assertFail("Expected an InitializeResult in the initialize response.");
    }
    test:assertEquals(initializeResult.protocolVersion, "2025-06-18");

    _ = check transport.sendMessage({jsonrpc: JSONRPC_VERSION, method: NOTIFICATION_INITIALIZED});

    JsonRpcMessage? listToolsResponse = check transport.sendMessage(
            {jsonrpc: JSONRPC_VERSION, id: 2, method: REQUEST_LIST_TOOLS});
    if listToolsResponse !is JsonRpcResponse {
        test:assertFail("Expected a JsonRpcResponse for the tools/list request.");
    }
    ServerResult listToolsResult = listToolsResponse.result;
    if listToolsResult !is ListToolsResult {
        test:assertFail("Expected a ListToolsResult in the tools/list response.");
    }
    test:assertEquals(listToolsResult.tools[0].name, "echo");

    JsonRpcMessage? callToolResponse = check transport.sendMessage({
        jsonrpc: JSONRPC_VERSION,
        id: 3,
        method: REQUEST_CALL_TOOL,
        params: {"name": "echo", "arguments": {inputText: "hello-stdio"}}
    });
    if callToolResponse !is JsonRpcResponse {
        test:assertFail("Expected a JsonRpcResponse for the tools/call request.");
    }
    ServerResult callToolResult = callToolResponse.result;
    if callToolResult !is CallToolResult {
        test:assertFail("Expected a CallToolResult in the tools/call response.");
    }
    ContentBlock firstContentBlock = callToolResult.content[0];
    if firstContentBlock !is TextContent {
        test:assertFail("Expected a TextContent block in the tools/call result.");
    }
    test:assertTrue(firstContentBlock.text.includes("hello-stdio"));

    test:assertTrue(transport.isServerAlive(), "Server process should be alive before termination.");
    check transport.terminateProcess();
    test:assertFalse(transport.isServerAlive(), "Server process should be terminated after close.");

    // Termination is idempotent.
    check transport.terminateProcess();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioTransportBuffersInterleavedServerMessages() returns error? {
    StdioClientTransport transport = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_EMIT_NOTIFICATION: "1"});

    JsonRpcMessage? initializeResponse = check transport.sendMessage(createInitializeJsonRpcRequest(1));
    test:assertTrue(initializeResponse is JsonRpcResponse,
            "Expected the correlated response despite the interleaved notification.");

    readonly & JsonRpcMessage[] pendingMessages = transport.drainPendingServerMessages();
    test:assertEquals(pendingMessages.length(), 1, "Expected exactly one buffered server notification.");
    JsonRpcMessage firstPendingMessage = pendingMessages[0];
    if firstPendingMessage !is JsonRpcNotification {
        test:assertFail("Expected the buffered message to be a JsonRpcNotification.");
    }
    test:assertEquals(firstPendingMessage.method, "notifications/tools/list_changed");
    test:assertEquals(transport.drainPendingServerMessages().length(), 0,
            "Draining should clear the pending buffer.");

    check transport.terminateProcess();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioTransportToleratesBlankLines() returns error? {
    StdioClientTransport transport = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_EMIT_BLANK_LINES: "1"});

    JsonRpcMessage? initializeResponse = check transport.sendMessage(createInitializeJsonRpcRequest(1));
    test:assertTrue(initializeResponse is JsonRpcResponse,
            "Expected the response to be received despite surrounding blank lines.");

    check transport.terminateProcess();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioTransportReportsServerExit() returns error? {
    StdioClientTransport transport = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_EXIT_AFTER_INITIALIZE: "1"});

    JsonRpcMessage? initializeResponse = check transport.sendMessage(createInitializeJsonRpcRequest(1));
    test:assertTrue(initializeResponse is JsonRpcResponse);

    JsonRpcMessage|StdioTransportError? listToolsResponse = transport.sendMessage(
            {jsonrpc: JSONRPC_VERSION, id: 2, method: REQUEST_LIST_TOOLS});
    // Depending on timing, either the EOF is observed on read or the write to the dead pipe fails.
    test:assertTrue(listToolsResponse is ServerProcessExitedError || listToolsResponse is StdioWriteError,
            "Expected a server-exit related transport error.");

    check transport.terminateProcess();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioTransportReadTimeout() returns error? {
    StdioClientTransport transport = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_RESPONSE_DELAY: "5"}, readTimeout = 1, shutdownTimeout = 1);

    JsonRpcMessage|StdioTransportError? initializeResponse =
            transport.sendMessage(createInitializeJsonRpcRequest(1));
    test:assertTrue(initializeResponse is ReadTimeoutError,
            "Expected a ReadTimeoutError when the server responds too slowly.");

    check transport.terminateProcess();
    test:assertFalse(transport.isServerAlive(), "Server process should be terminated after close.");
}

@test:Config {groups: ["stdio"]}
isolated function testStdioTransportSpawnFailure() {
    StdioClientTransport|StdioTransportError transport = new (command = "nonexistent-command-for-mcp-test");
    test:assertTrue(transport is ProcessSpawnError,
            "Expected a ProcessSpawnError for a nonexistent command.");
}

@test:Config {groups: ["stdio"]}
isolated function testStdioTransportRejectsSendAfterClose() returns error? {
    StdioClientTransport transport = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER]);
    check transport.terminateProcess();

    JsonRpcMessage|StdioTransportError? sendResult = transport.sendMessage(createInitializeJsonRpcRequest(1));
    test:assertTrue(sendResult is StdioTransportError,
            "Expected a StdioTransportError when sending on a closed transport.");
}
