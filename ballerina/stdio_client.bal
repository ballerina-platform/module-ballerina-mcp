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

# Represents an MCP client built on top of the stdio transport. The MCP server is launched
# as a subprocess and the session lasts for the lifetime of that process.
public distinct isolated client class StdioClient {
    # Transport for communication with the MCP server subprocess.
    private final StdioClientTransport transport;
    # Server capabilities.
    private ServerCapabilities? serverCapabilities = ();
    # Server implementation information.
    private Implementation? serverInfo = ();
    # Whether the MCP initialization handshake has completed.
    private boolean initialized = false;
    # Whether an MCP initialization handshake is currently in progress.
    private boolean initializing = false;
    # Request ID generator for tracking requests.
    private int requestId = 0;

    # Creates a new MCP client by launching the MCP server as a subprocess.
    #
    # + config - Subprocess launch and transport configuration
    # + return - `ClientError` if the server process cannot be started, `()` on success
    public isolated function init(*StdioClientTransportConfig config) returns ClientError? {
        self.transport = check new (config);
    }

    # Initializes the MCP connection by performing protocol handshake and capability exchange.
    # Subsequent calls after a successful handshake are no-ops.
    #
    # + clientInfo - Client implementation information
    # + capabilities - Client capabilities to advertise
    # + return - `ClientError` if initialization fails, `()` on success
    isolated remote function initialize(Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}) returns ClientError? {
        lock {
            if self.initialized {
                return;
            }
            if self.initializing {
                return error ClientInitializationError("MCP client initialization is already in progress.");
            }
            self.initializing = true;
        }

        // Prepare and send the initialization request.
        InitializeRequest initRequest = {
            params: {
                protocolVersion: LATEST_PROTOCOL_VERSION,
                capabilities: capabilities,
                clientInfo: clientInfo
            }
        };

        ServerResult|ClientError response = self.sendRequestMessage(initRequest);
        if response is ClientError {
            self.clearInitializing();
            return response;
        }
        InitializeResult|ClientError initializeResult = validateInitializeResponse(response);
        if initializeResult is ClientError {
            self.clearInitializing();
            return initializeResult;
        }

        // Complete the handshake only after sending notifications/initialized.
        ClientError? notificationError = self.sendNotificationMessage(<InitializedNotification>{});
        if notificationError is ClientError {
            self.clearInitializing();
            return notificationError;
        }

        lock {
            self.serverCapabilities = initializeResult.capabilities.cloneReadOnly();
            self.serverInfo = initializeResult.serverInfo.cloneReadOnly();
            self.initialized = true;
            self.initializing = false;
        }
    }

    # Clears the in-progress initialization marker after a failed handshake.
    private isolated function clearInitializing() {
        lock {
            self.initializing = false;
        }
    }

    # Opens a live stream of server-initiated messages (notifications or requests).
    #
    # + return - Stream of JsonRpcMessages until the server subprocess exits, or a ClientError.
    isolated remote function subscribeToServerMessages() returns stream<JsonRpcMessage, StreamError?>|ClientError {
        return check self.transport.establishMessageStream();
    }

    # Retrieves the list of available tools from the server.
    #
    # + return - List of available tools or a ClientError.
    isolated remote function listTools() returns ListToolsResult|ClientError {
        ListToolsRequest listToolsRequest = {};

        ServerResult result = check self.sendRequestMessage(listToolsRequest);
        return ensureListToolsResult(result);
    }

    # Executes a tool on the server with the given parameters.
    #
    # + params - Tool execution parameters, including name and arguments
    # + return - Result of the tool execution or a ClientError.
    isolated remote function callTool(CallToolParams params) returns CallToolResult|ClientError {
        // Reject task-augmented calls when the server hasn't advertised task support.
        if params.task !is () {
            lock {
                if self.serverCapabilities?.tasks?.requests?.tools?.call is () {
                    return error ToolCallError("Server does not support task-augmented tool calls");
                }
            }
        }

        CallToolRequest toolCallRequest = {
            params: params
        };

        ServerResult result = check self.sendRequestMessage(toolCallRequest);
        return ensureCallToolResult(result);
    }

    # Closes the session by terminating the MCP server subprocess.
    #
    # + return - A `ClientError` if closure fails, or `()` on success.
    isolated remote function close() returns ClientError? {
        lock {
            do {
                check self.transport.terminateProcess();
                self.serverCapabilities = ();
                self.serverInfo = ();
                self.initialized = false;
                return;
            } on fail error e {
                return error ClientError(string `Failed to disconnect from server: ${e.message()}`, e);
            }
        }
    }

    # Sends a request message to the server and returns the server's response.
    #
    # + request - The request object to send
    # + return - ServerResult or a ClientError.
    private isolated function sendRequestMessage(Request request) returns ServerResult|ClientError {
        int requestId;
        lock {
            self.requestId += 1;
            requestId = self.requestId;
        }
        JsonRpcRequest jsonRpcRequest = {
            ...request.cloneReadOnly(),
            jsonrpc: JSONRPC_VERSION,
            id: requestId
        };

        JsonRpcMessage|StdioTransportError? response = self.transport.sendMessage(jsonRpcRequest);
        return processServerResponse(response).cloneReadOnly();
    }

    # Sends a notification message to the server.
    #
    # + notification - The notification object to send.
    # + return - A `ClientError` if sending fails, or `()` on success.
    private isolated function sendNotificationMessage(Notification notification) returns ClientError? {
        JsonRpcNotification jsonRpcNotification = {
            ...notification.cloneReadOnly(),
            jsonrpc: JSONRPC_VERSION
        };

        _ = check self.transport.sendMessage(jsonRpcNotification);
    }
}
