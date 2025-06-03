// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
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

# Configuration options for initializing an MCP client.
#
# + capabilities - Capabilities to be advertised by this client.
public type ClientConfiguration record {|
    *ProtocolOptions;
    ClientCapabilities capabilities?;
|};

# Represents an MCP client built on top of the Streamable HTTP transport.
public distinct client class Client {
    # MCP server URL.
    private final string serverUrl;
    # Client implementation details (e.g., name and version).
    private final Implementation clientInfo;
    # Capabilities supported by the client.
    private final ClientCapabilities clientCapabilities;

    # Transport for communication with the MCP server.
    private StreamableHttpClientTransport? transport = ();
    # Server capabilities.
    private ServerCapabilities? serverCapabilities = ();
    # Server implementation information.
    private Implementation? serverInfo = ();
    # Request ID generator for tracking requests.
    private int requestId = 0;

    # Initializes a new MCP client with the provided server URL and client details.
    #
    # + serverUrl - MCP server URL.
    # + clientInfo - Client details, such as name and version.
    # + config - Optional configuration containing client capabilities.
    public isolated function init(string serverUrl, Implementation clientInfo, ClientConfiguration? config = ()) {
        self.serverUrl = serverUrl;
        self.clientInfo = clientInfo;
        self.clientCapabilities = config?.capabilities ?: {};
    }

    # Establishes a connection to the MCP server and performs protocol initialization.
    #
    # + return - A ClientError if initialization fails, or nil on success.
    isolated remote function initialize() returns ClientError? {
        lock {
            // Create and initialize transport.
            StreamableHttpClientTransport newTransport = check new StreamableHttpClientTransport(self.serverUrl);
            self.transport = newTransport;

            string? sessionId = newTransport.getSessionId();

            // If a session ID exists, assume reconnection and skip initialization.
            if sessionId is string {
                return;
            }

            // Prepare and send the initialization request.
            InitializeRequest initRequest = {
                method: "initialize",
                params: {
                    protocolVersion: LATEST_PROTOCOL_VERSION,
                    capabilities: self.clientCapabilities,
                    clientInfo: self.clientInfo
                }
            };

            ServerResult response = check self.sendRequestMessage(initRequest);

            if response is InitializeResult {
                final readonly & string protocolVersion = response.protocolVersion;
                // Validate protocol compatibility.
                if (!SUPPORTED_PROTOCOL_VERSIONS.some(v => v == protocolVersion)) {
                    return error ProtocolVersionError(
                        string `Server protocol version '${protocolVersion}' is not supported. Supported versions: ${SUPPORTED_PROTOCOL_VERSIONS.toString()}.`
                    );
                }

                // Store server capabilities and info.
                self.serverCapabilities = response.capabilities;
                self.serverInfo = response.serverInfo;

                // Send notification to complete initialization.
                InitializedNotification initNotification = {
                    method: "notifications/initialized"
                };
                check self.sendNotificationMessage(initNotification);

                return;
            } else {
                return error ClientInitializationError(
                    string `Initialization failed: unexpected response type '${(typeof response).toString()}' received from server.`
                );
            }
        }
    }

    # Opens a server-sent events (SSE) stream for asynchronous server-to-client communication.
    #
    # + return - Stream of JsonRpcMessages or a ClientError.
    isolated remote function subscribeToServerMessages() returns stream<JsonRpcMessage, StreamError?>|ClientError {
        StreamableHttpClientTransport? currentTransport = self.transport;
        if currentTransport is () {
            return error UninitializedTransportError(
                "Subscription failed: client transport is not initialized. Call initialize() first."
            );
        }
        return check currentTransport.establishEventStream();
    }

    # Retrieves the list of available tools from the server.
    #
    # + return - List of available tools or a ClientError.
    isolated remote function listTools() returns ListToolsResult|ClientError {
        ListToolsRequest listToolsRequest = {
            method: "tools/list"
        };

        ServerResult result = check self.sendRequestMessage(listToolsRequest);
        if result is ListToolsResult {
            return result;
        } else {
            return error ListToolsError(
                string `Tool listing failed: unexpected result type '${(typeof result).toString()}' received.`
            );
        }
    }

    # Executes a tool on the server with the given parameters.
    #
    # + params - Tool execution parameters, including name and arguments.
    # + return - Result of the tool execution or a ClientError.
    isolated remote function callTool(CallToolParams params) returns CallToolResult|ClientError {
        CallToolRequest toolCallRequest = {
            method: "tools/call",
            params: params
        };

        ServerResult result = check self.sendRequestMessage(toolCallRequest);
        if result is CallToolResult {
            return result;
        } else {
            return error ToolCallError(
                string `Tool call failed: unexpected result type '${(typeof result).toString()}' received.`
            );
        }
    }

    # Closes the session and disconnects from the server.
    #
    # + return - A ClientError if closure fails, or nil on success.
    isolated remote function close() returns ClientError? {
        StreamableHttpClientTransport? currentTransport = self.transport;
        if currentTransport is () {
            return error UninitializedTransportError(
                "Closure failed: client transport is not initialized. Call initialize() first."
            );
        }

        do {
            check currentTransport.terminateSession();
            lock {
                self.transport = ();
                self.serverCapabilities = ();
                self.serverInfo = ();
            }
            return;
        } on fail error e {
            return error ClientError(string `Failed to disconnect from server: ${e.message()}`, e);
        }
    }

    # Sends a request message to the server and returns the server's response.
    #
    # + request - The request object to send.
    # + return - ServerResult, a stream of results, or a ClientError.
    private isolated function sendRequestMessage(Request request) returns ServerResult|ClientError {
        StreamableHttpClientTransport? currentTransport = self.transport;
        if currentTransport is () {
            return error UninitializedTransportError(
                "Cannot send request: client transport is not initialized. Call initialize() first."
            );
        }

        lock {
            self.requestId += 1;

            JsonRpcRequest jsonRpcRequest = {
                ...request,
                jsonrpc: JSONRPC_VERSION,
                id: self.requestId
            };

            JsonRpcMessage|stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError? response =
                currentTransport.sendMessage(jsonRpcRequest);
            return processServerResponse(response);
        }
    }

    # Sends a notification message to the server.
    #
    # + notification - The notification object to send.
    # + return - A ClientError if sending fails, or nil on success.
    private isolated function sendNotificationMessage(Notification notification) returns ClientError? {
        StreamableHttpClientTransport? currentTransport = self.transport;
        if currentTransport is () {
            return error UninitializedTransportError(
                "Cannot send notification: client transport is not initialized. Call initialize() first."
            );
        }

        JsonRpcNotification jsonRpcNotification = {
            ...notification,
            jsonrpc: JSONRPC_VERSION
        };

        _ = check currentTransport.sendMessage(jsonRpcNotification);
    }
}
