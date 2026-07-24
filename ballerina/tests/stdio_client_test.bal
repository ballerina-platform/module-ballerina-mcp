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

@test:Config {groups: ["stdio"]}
isolated function testStdioClientEndToEnd() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER]);

    check mcpClient->initialize(clientInfo = {name: "stdio-client-test", version: "0.1.0"});
    // A second initialize after a successful handshake is a no-op.
    check mcpClient->initialize();

    ListToolsResult listToolsResult = check mcpClient->listTools();
    test:assertEquals(listToolsResult.tools[0].name, "echo");

    CallToolResult callToolResult = check mcpClient->callTool({
        name: "echo",
        arguments: {"inputText": "hello-from-client"}
    });
    ContentBlock firstContentBlock = callToolResult.content[0];
    if firstContentBlock !is TextContent {
        test:assertFail("Expected a TextContent block in the tools/call result.");
    }
    test:assertTrue(firstContentBlock.text.includes("hello-from-client"));

    check mcpClient->close();
    // A second close is a no-op.
    check mcpClient->close();
}

// Regression: if the notifications/initialized write fails, initialize() must not have
// marked the client as initialized, so a retry re-attempts the handshake instead of
// returning a silent no-op success.
@test:Config {groups: ["stdio"]}
isolated function testStdioClientInitializeNotMarkedWhenNotificationFails() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_CLOSE_STDIN_AFTER_INITIALIZE: "1"}, readTimeout = 2, shutdownTimeout = 1);

    // The server answers initialize but has closed its stdin, so sending
    // notifications/initialized fails and initialize() surfaces that error.
    ClientError? firstInitialize = mcpClient->initialize();
    test:assertTrue(firstInitialize is ClientError,
            "initialize() should fail when the notifications/initialized write fails.");

    // Since the handshake never completed, a retry must not be a silent success.
    ClientError? secondInitialize = mcpClient->initialize();
    test:assertTrue(secondInitialize is ClientError,
            "A retry after a failed handshake must re-attempt, not return a no-op success.");

    check mcpClient->close();
}

// Only one initialization handshake may be active at a time. A concurrent attempt must
// fail instead of sending a second initialize request before the first handshake completes.
@test:Config {groups: ["stdio"]}
isolated function testStdioClientRejectsConcurrentInitialization() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_RESPONSE_DELAY: "0.5"});

    future<ClientError?> firstInitialization = start mcpClient->initialize();
    future<ClientError?> secondInitialization = start mcpClient->initialize();
    ClientError? firstResult = wait firstInitialization;
    ClientError? secondResult = wait secondInitialization;

    test:assertTrue((firstResult is () && secondResult is ClientInitializationError) ||
            (secondResult is () && firstResult is ClientInitializationError),
            "Exactly one concurrent initialize() call must complete the handshake.");

    check mcpClient->close();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioClientRejectsUnsupportedProtocolVersion() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_PROTOCOL_VERSION: "1999-01-01"});

    ClientError? initializeResult = mcpClient->initialize();
    test:assertTrue(initializeResult is ProtocolVersionError,
            "Expected a ProtocolVersionError for an unsupported server protocol version.");

    check mcpClient->close();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioClientRejectsTaskAugmentedCallWithoutCapability() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER]);
    check mcpClient->initialize();

    CallToolResult|ClientError callToolResult = mcpClient->callTool({name: "echo", task: {}});
    test:assertTrue(callToolResult is ToolCallError,
            "Expected a ToolCallError since the mock server does not advertise task support.");

    check mcpClient->close();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioClientSubscribeToServerMessages() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_EMIT_NOTIFICATION: "1"});
    check mcpClient->initialize();
    _ = check mcpClient->listTools();

    stream<JsonRpcMessage, StreamError?> serverMessageStream = check mcpClient->subscribeToServerMessages();
    record {|JsonRpcMessage value;|}|StreamError? firstStreamItem = serverMessageStream.next();
    if firstStreamItem is StreamError {
        return firstStreamItem;
    }
    if firstStreamItem is () {
        test:assertFail("Expected a server notification.");
    }
    JsonRpcMessage firstServerMessage = firstStreamItem.value;
    if firstServerMessage !is JsonRpcNotification {
        test:assertFail("Expected a streamed message to be a JsonRpcNotification.");
    }
    test:assertEquals(firstServerMessage.method, "notifications/tools/list_changed");

    record {|JsonRpcMessage value;|}|StreamError? secondStreamItem = serverMessageStream.next();
    if secondStreamItem is StreamError {
        return secondStreamItem;
    }
    test:assertTrue(secondStreamItem is record {|JsonRpcMessage value;|},
            "Expected the notification produced during tools/list.");

    ClientError|stream<JsonRpcMessage, StreamError?> secondSubscription = mcpClient->subscribeToServerMessages();
    test:assertTrue(secondSubscription is StdioTransportError,
            "Expected a second active server-message subscription to be rejected.");

    check serverMessageStream.close();
    stream<JsonRpcMessage, StreamError?> reopenedSubscription = check mcpClient->subscribeToServerMessages();
    check reopenedSubscription.close();

    check mcpClient->close();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioClientStreamsIdleServerMessages() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_EMIT_IDLE_NOTIFICATION: "1"});
    check mcpClient->initialize();

    stream<JsonRpcMessage, StreamError?> serverMessageStream = check mcpClient->subscribeToServerMessages();
    record {|JsonRpcMessage value;|}|StreamError? streamItem = serverMessageStream.next();
    if streamItem is StreamError {
        return streamItem;
    }
    if streamItem is () {
        test:assertFail("Expected the notification sent while the client was idle.");
    }
    JsonRpcMessage serverMessage = streamItem.value;
    if serverMessage !is JsonRpcNotification {
        test:assertFail("Expected an idle server notification.");
    }
    test:assertEquals(serverMessage.method, "notifications/resources/list_changed");

    check mcpClient->close();
}
