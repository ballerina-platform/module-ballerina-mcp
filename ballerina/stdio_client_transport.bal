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
    # Grace period in seconds applied at each stage of the shutdown sequence
    # (close stdin → wait → SIGTERM → wait → SIGKILL)
    decimal shutdownTimeout = 5;
    # How the subprocess stderr output is handled
    StderrMode stderrMode = STDERR_INHERIT;
|};

# Provides stdio-based client transport that launches an MCP server as a subprocess and
# communicates with it over newline-delimited JSON-RPC on its stdin/stdout pipes.
#
# Requests and their response correlation are serialized: one request/response cycle is
# in flight at a time. Server-initiated messages (notifications or requests) received while
# waiting for a response are buffered and can be drained via `drainPendingServerMessages`.
isolated class StdioClientTransport {
    private final decimal readTimeout;
    private final decimal shutdownTimeout;
    private boolean transportClosed = false;
    private JsonRpcMessage[] pendingServerMessages = [];

    # Initializes the transport by spawning the MCP server subprocess.
    #
    # + config - Subprocess launch and transport configuration.
    # + return - A `StdioTransportError` if the process cannot be spawned; otherwise, nil.
    isolated function init(*StdioClientTransportConfig config) returns StdioTransportError? {
        self.readTimeout = config.readTimeout;
        self.shutdownTimeout = config.shutdownTimeout;
        return self.startServerProcess(config.command, config.args.cloneReadOnly(),
                config.env.cloneReadOnly(), config.cwd, config.stderrMode);
    }

    # Sends a JSON-RPC message to the server over stdin.
    #
    # For requests, blocks until the response with the matching id arrives on stdout and returns it.
    # Server-initiated messages received in the meantime are buffered. For notifications, returns
    # immediately after the write.
    #
    # + message - The JSON-RPC message to send.
    # + return - The correlated response for requests, nil for notifications, or a `StdioTransportError`.
    isolated function sendMessage(JsonRpcMessage message) returns JsonRpcMessage|StdioTransportError? {
        readonly & JsonRpcMessage outboundMessage = message.cloneReadOnly();
        lock {
            if self.transportClosed {
                return error StdioTransportError("Cannot send message: transport is closed.");
            }
            check self.writeMessageLine(outboundMessage.toJsonString());
            if outboundMessage !is JsonRpcRequest {
                return;
            }
            RequestId requestId = outboundMessage.id;
            while true {
                string? messageLine = check self.readMessageLine(self.readTimeout);
                if messageLine is () {
                    return self.createServerExitedError();
                }
                JsonRpcMessage|error parsedMessage = messageLine.fromJsonStringWithType();
                if parsedMessage is error {
                    // Tolerate lines that are not valid JSON-RPC instead of failing the in-flight request.
                    continue;
                }
                if parsedMessage is JsonRpcResponse|JsonRpcError {
                    if parsedMessage.id == requestId {
                        return parsedMessage.cloneReadOnly();
                    }
                    // Response to an unknown request id — drop it.
                    continue;
                }
                // Server-initiated request or notification — buffer for later consumption.
                self.pendingServerMessages.push(parsedMessage);
            }
        }
    }

    # Returns the server-initiated messages buffered so far and clears the buffer.
    #
    # + return - The buffered messages in arrival order.
    isolated function drainPendingServerMessages() returns readonly & JsonRpcMessage[] {
        lock {
            readonly & JsonRpcMessage[] drainedMessages = self.pendingServerMessages.cloneReadOnly();
            self.pendingServerMessages = [];
            return drainedMessages;
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

    private isolated function readMessageLine(decimal timeoutSeconds)
            returns string|StdioTransportError? = @java:Method {
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
