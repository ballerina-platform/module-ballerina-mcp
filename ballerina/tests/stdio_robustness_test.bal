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

# Number of parallel tool calls in the concurrency stress test.
# Deliberately above the runtime's carrier-thread count (CPU cores) so blocked reads
# would starve the scheduler if they did not yield.
const int CONCURRENT_CALL_COUNT = 24;
# Number of sequential tool calls in the long-session test.
const int LONG_SESSION_CALL_COUNT = 60;
# Stdout notifications flooded before the initialize response. Exceeds the native stdout
# queue capacity (1024) so the reader thread must block and apply backpressure.
const int STDOUT_FLOOD_COUNT = 3000;

// A response arriving after its request timed out must be discarded on the next
// request's cycle — never returned as the answer to a different request.
@test:Config {groups: ["stdio"]}
isolated function testStdioTransportRecoversAfterReadTimeout() returns error? {
    StdioClientTransport transport = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_RESPONSE_DELAY: "1.5", MOCK_DELAY_ONLY_FIRST: "1"},
            readTimeout = 1, shutdownTimeout = 1);

    JsonRpcMessage|StdioTransportError? timedOutResponse =
            transport.sendMessage(createInitializeJsonRpcRequest(1));
    test:assertTrue(timedOutResponse is ReadTimeoutError,
            "Expected the delayed first response to time out.");

    // The stale response to request 1 arrives during request 2's cycle.
    JsonRpcMessage? listToolsResponse = check transport.sendMessage(
            {jsonrpc: JSONRPC_VERSION, id: 2, method: REQUEST_LIST_TOOLS});
    if listToolsResponse !is JsonRpcResponse {
        test:assertFail("Expected a JsonRpcResponse for the request issued after the timeout.");
    }
    test:assertEquals(listToolsResponse.id, 2,
            "The stale response must be dropped and request 2 must receive its own response.");

    check transport.terminateProcess();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioClientConcurrentToolCalls() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_CONCURRENT_RESPONSES: "1", MOCK_CONCURRENT_REQUEST_TARGET:
                    CONCURRENT_CALL_COUNT.toString()}, readTimeout = 2,
            maxConcurrentRequests = CONCURRENT_CALL_COUNT);
    check mcpClient->initialize();

    future<CallToolResult|ClientError>[] pendingCalls = [];
    foreach int callIndex in 0 ..< CONCURRENT_CALL_COUNT {
        future<CallToolResult|ClientError> pendingCall = start invokeEchoTool(mcpClient, callIndex);
        pendingCalls.push(pendingCall);
    }

    foreach int callIndex in 0 ..< CONCURRENT_CALL_COUNT {
        CallToolResult|ClientError callResult = wait pendingCalls[callIndex];
        if callResult is ClientError {
            test:assertFail(string `Concurrent call ${callIndex} failed: ${callResult.message()}`);
        }
        ContentBlock firstContentBlock = callResult.content[0];
        if firstContentBlock !is TextContent {
            test:assertFail("Expected a TextContent block in the echo result.");
        }
        // Each caller must receive its own response — no cross-wiring under concurrency.
        test:assertTrue(firstContentBlock.text.includes(string `: ${callIndex}}`),
                string `Call ${callIndex} received a response meant for another request: ${
                    firstContentBlock.text}`);
    }

    check mcpClient->close();
}

isolated function invokeEchoTool(StdioClient mcpClient, int callIndex) returns CallToolResult|ClientError {
    return mcpClient->callTool({name: "echo", arguments: {"callIndex": callIndex}});
}

@test:Config {groups: ["stdio"]}
isolated function testStdioTransportHonorsWorkingDirectory() returns error? {
    // The script path is relative to the configured cwd, so spawning only succeeds
    // if the working directory is actually applied.
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = ["mock_stdio_server.py"],
            cwd = "tests/resources");
    check mcpClient->initialize();

    CallToolResult cwdResult = check mcpClient->callTool({name: "cwd"});
    ContentBlock firstContentBlock = cwdResult.content[0];
    if firstContentBlock !is TextContent {
        test:assertFail("Expected a TextContent block in the cwd result.");
    }
    test:assertTrue(firstContentBlock.text.endsWith("tests/resources"),
            string `Expected the server cwd to end with 'tests/resources', got: ${firstContentBlock.text}`);

    check mcpClient->close();
}

@test:Config {groups: ["stdio"]}
isolated function testStdioClientSustainsLongSession() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER]);
    check mcpClient->initialize();

    foreach int sequenceNumber in 0 ..< LONG_SESSION_CALL_COUNT {
        CallToolResult callResult = check mcpClient->callTool({
            name: "echo",
            arguments: {"sequenceNumber": sequenceNumber}
        });
        ContentBlock firstContentBlock = callResult.content[0];
        if firstContentBlock !is TextContent {
            test:assertFail("Expected a TextContent block in the echo result.");
        }
        test:assertTrue(firstContentBlock.text.includes(string `: ${sequenceNumber}}`),
                string `Sequential call ${sequenceNumber} received the wrong response.`);
    }

    check mcpClient->close();
}

// A stdout burst with no message consumer must backpressure the child and time out rather than
// allowing the client to accumulate an unbounded number of server-initiated messages.
@test:Config {groups: ["stdio"]}
isolated function testStdioTransportBackpressuresUnconsumedStdoutBurst() returns error? {
    StdioClientTransport transport = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_FLOOD_NOTIFICATIONS: STDOUT_FLOOD_COUNT.toString()}, readTimeout = 1,
            shutdownTimeout = 1);

    JsonRpcMessage|StdioTransportError? initializeResponse =
            transport.sendMessage(createInitializeJsonRpcRequest(1));
    test:assertTrue(initializeResponse is ReadTimeoutError,
            "An unconsumed notification burst must not bypass the configured read timeout.");

    check transport.terminateProcess();
}

// EOF must wake response waiters even if the server-message queue is full and its EOF sentinel
// cannot be added until a subscriber drains it.
@test:Config {groups: ["stdio"]}
isolated function testStdioTransportReportsExitAfterUnconsumedStdoutBurst() returns error? {
    StdioClientTransport transport = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_FLOOD_NOTIFICATIONS: "1024", MOCK_EXIT_AFTER_FLOOD: "1"}, readTimeout = 2,
            shutdownTimeout = 1);

    JsonRpcMessage|StdioTransportError? initializeResponse =
            transport.sendMessage(createInitializeJsonRpcRequest(1));
    test:assertTrue(initializeResponse is ServerProcessExitedError,
            "A server exit behind a full message queue must not wait for the read timeout.");

    check transport.terminateProcess();
}

// A server flooding stderr must not block the session: inherit and discard modes
// never create a stderr pipe that could fill up and backpressure the child.
@test:Config {groups: ["stdio"]}
isolated function testStdioClientUnaffectedByStderrSpam() returns error? {
    StdioClient mcpClient = check new (command = PYTHON_COMMAND, args = [MOCK_STDIO_SERVER],
            env = {MOCK_STDERR_SPAM: "1"}, stderrMode = STDERR_DISCARD);
    check mcpClient->initialize();

    CallToolResult callResult = check mcpClient->callTool({name: "echo", arguments: {"probe": 1}});
    test:assertEquals(callResult.isError, false);

    check mcpClient->close();
}
