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

import ballerina/jballerina.java;

# Determines how the stderr output of the MCP server subprocess is handled.
public enum StderrMode {
    # Forward the subprocess stderr (server logs) to the parent process stderr.
    STDERR_INHERIT = "inherit",
    # Discard the subprocess stderr output.
    STDERR_DISCARD = "discard"
}

# Configuration options for the stdio client transport.
public type StdioClientTransportConfig record {|
    # Executable used to launch the MCP server (e.g. `uvx`, `npx`, `python3`)
    string command;
    # Arguments passed to the executable
    string[] args = [];
    # Environment variables set for the subprocess, overlaid on the inherited parent environment
    map<string> env = {};
    # Working directory for the subprocess; defaults to the current working directory
    string cwd?;
    # Seconds to wait for a message from the server before a read times out
    decimal readTimeout = 60;
    # Maximum number of requests that may await responses at the same time
    int maxConcurrentRequests = 32;
    # Grace period in seconds applied at each stage of the shutdown sequence
    # (close stdin → wait → SIGTERM → wait → SIGKILL)
    decimal shutdownTimeout = 5;
    # How the subprocess stderr output is handled
    StderrMode stderrMode = STDERR_INHERIT;
|};

# Provides stdio-based client transport that launches an MCP server as a subprocess and
# communicates with it over newline-delimited JSON-RPC on its stdin/stdout pipes.
#
# A dedicated reader routes each response by JSON-RPC ID, allowing independent requests to be
# in flight concurrently. Server-initiated messages are delivered through a live message stream.
isolated class StdioClientTransport {
    private final decimal readTimeout;
    private final decimal shutdownTimeout;
    private final int maxConcurrentRequests;
    private boolean transportClosed = false;
    private int activeRequestCount = 0;
    private boolean serverMessageStreamOpen = false;

    # Initializes the transport by spawning the MCP server subprocess.
    #
    # + config - Subprocess launch and transport configuration.
    # + return - A `StdioTransportError` if the process cannot be spawned; otherwise, nil.
    isolated function init(*StdioClientTransportConfig config) returns StdioTransportError? {
        self.readTimeout = config.readTimeout;
        self.shutdownTimeout = config.shutdownTimeout;
        self.maxConcurrentRequests = config.maxConcurrentRequests;
        if self.maxConcurrentRequests < 1 {
            return error StdioTransportError("maxConcurrentRequests must be greater than zero.");
        }
        return self.startServerProcess(config.command, config.args.cloneReadOnly(),
                config.env.cloneReadOnly(), config.cwd, config.stderrMode);
    }

    # Sends a JSON-RPC message to the server over stdin.
    #
    # A request waits only for its matching response, allowing other requests to proceed in parallel.
    # Notifications return immediately after the write.
    #
    # + message - The JSON-RPC message to send.
    # + return - The correlated response for requests, nil for notifications, or a `StdioTransportError`.
    isolated function sendMessage(JsonRpcMessage message) returns JsonRpcMessage|StdioTransportError? {
        readonly & JsonRpcMessage outboundMessage = message.cloneReadOnly();
        if outboundMessage is JsonRpcRequest {
            return self.sendRequestMessage(outboundMessage);
        }
        lock {
            if self.transportClosed {
                return error StdioTransportError("Cannot send message: transport is closed.");
            }
            return self.writeMessageLine(outboundMessage.toJsonString());
        }
    }

    # Opens a live stream of server-initiated messages received on stdout.
    #
    # Only one active stream is supported because the subprocess has one stdout channel.
    #
    # + return - Stream of server notifications and requests until the subprocess exits, or a transport error.
    isolated function establishMessageStream() returns stream<JsonRpcMessage, StreamError?>|StdioTransportError {
        lock {
            if self.transportClosed {
                return error StdioTransportError("Cannot subscribe to messages: transport is closed.");
            }
            if self.serverMessageStreamOpen {
                return error StdioTransportError("A server message stream is already open.");
            }
            self.serverMessageStreamOpen = true;
            StdioServerMessageStream messageStream = new (transport = self);
            return new stream<JsonRpcMessage, StreamError?>(messageStream);
        }
    }

    # Reserves a bounded request slot, registers its response queue, sends the request, and waits
    # for the matching response.
    #
    # + request - JSON-RPC request to send.
    # + return - The matching response or a transport error.
    private isolated function sendRequestMessage(JsonRpcRequest request)
            returns JsonRpcMessage|StdioTransportError? {
        check self.acquireRequestSlot();
        RequestId requestId = request.id;
        StdioTransportError? registrationError = self.registerResponseWaiter(requestId = requestId);
        if registrationError is StdioTransportError {
            self.releaseRequestSlot();
            return registrationError;
        }

        StdioTransportError? writeError = self.writeMessageLine(line = request.toJsonString());
        if writeError is StdioTransportError {
            self.unregisterResponseWaiter(requestId = requestId);
            self.releaseRequestSlot();
            return writeError;
        }

        string|StdioTransportError? responseLine = self.awaitResponse(requestId = requestId,
                timeoutSeconds = self.readTimeout);
        self.unregisterResponseWaiter(requestId = requestId);
        self.releaseRequestSlot();
        if responseLine is StdioTransportError {
            return responseLine;
        }
        if responseLine is () {
            return self.createServerExitedError();
        }
        JsonRpcMessage|error response = responseLine.fromJsonStringWithType();
        if response is error {
            return error StdioReadError(string `Failed to parse a correlated server response: ${response.message()}`);
        }
        return response.cloneReadOnly();
    }

    # Reserves a request slot while ensuring the transport remains open.
    #
    # + return - A transport error when closed or at the configured request limit.
    private isolated function acquireRequestSlot() returns StdioTransportError? {
        lock {
            if self.transportClosed {
                return error StdioTransportError("Cannot send message: transport is closed.");
            }
            if self.activeRequestCount >= self.maxConcurrentRequests {
                return error StdioTransportError(string `Maximum concurrent request limit of ${
                        self.maxConcurrentRequests} reached.`);
            }
            self.activeRequestCount += 1;
        }
    }

    # Releases a request slot after a response, timeout, or write failure.
    private isolated function releaseRequestSlot() {
        lock {
            self.activeRequestCount -= 1;
        }
    }

    # Marks the server-message stream as closed so a later subscriber may open a new stream.
    isolated function releaseServerMessageStream() {
        lock {
            self.serverMessageStreamOpen = false;
        }
    }

    # Terminates the server subprocess following the MCP stdio shutdown sequence.
    # Subsequent calls are no-ops.
    #
    # + return - A `StdioTransportError` if termination fails; otherwise, nil.
    isolated function terminateProcess() returns StdioTransportError? {
        lock {
            if self.transportClosed {
                return;
            }
            self.transportClosed = true;
            return self.terminateServerProcess(self.shutdownTimeout);
        }
    }

    # Builds the error describing an unexpected server process exit.
    #
    # + return - A `ServerProcessExitedError` including the exit code when available.
    private isolated function createServerExitedError() returns ServerProcessExitedError {
        int? exitCode = self.serverProcessExitCode();
        string exitDetail = exitCode is int ? string ` (exit code ${exitCode})` : "";
        return error ServerProcessExitedError(
                string `MCP server process closed its stdout unexpectedly${exitDetail}.`);
    }

    private isolated function startServerProcess(string command, string[] & readonly args,
            map<string> & readonly env, string? cwd, string stderrMode)
            returns StdioTransportError? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.StdioProcessHelper"
    } external;

    private isolated function writeMessageLine(string line) returns StdioTransportError? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.StdioProcessHelper"
    } external;

    private isolated function registerResponseWaiter(RequestId requestId) returns StdioTransportError? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.StdioProcessHelper"
    } external;

    private isolated function awaitResponse(RequestId requestId, decimal timeoutSeconds)
            returns string|StdioTransportError? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.StdioProcessHelper"
    } external;

    private isolated function unregisterResponseWaiter(RequestId requestId) = @java:Method {
        'class: "io.ballerina.stdlib.mcp.StdioProcessHelper"
    } external;

    isolated function readServerMessage() returns string|StdioTransportError? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.StdioProcessHelper"
    } external;

    private isolated function terminateServerProcess(decimal graceSeconds)
            returns StdioTransportError? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.StdioProcessHelper"
    } external;

    # Reports whether the server subprocess is currently alive.
    #
    # + return - True if the process has been started and has not yet exited.
    isolated function isServerAlive() returns boolean = @java:Method {
        name: "isServerProcessAlive",
        'class: "io.ballerina.stdlib.mcp.StdioProcessHelper"
    } external;

    private isolated function serverProcessExitCode() returns int? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.StdioProcessHelper"
    } external;
}
