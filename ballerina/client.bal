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
public type ClientConfiguration record {|
    *StreamableHttpClientTransportConfig;
    # Client information such as name and version.
    Implementation info;
    # Client capabilities configuration.
    ClientCapabilityConfiguration capabilityConfig?;
|};

# Configuration options for initializing an MCP client.
public type ClientCapabilityConfiguration record {|
    # Capabilities to be advertised by this client.
    ClientCapabilities capabilities?;
    # Whether to enforce strict capabilities compliance.
    boolean enforceStrictCapabilities?;
|};

# Represents an MCP client built on top of the Streamable HTTP transport.
public distinct isolated client class Client {
    # Transport for communication with the MCP server.
    private StreamableHttpClientTransport transport;
    # Server capabilities.
    private ServerCapabilities? serverCapabilities = ();
    # Server implementation information.
    private Implementation? serverInfo = ();
    # Request ID generator for tracking requests.
    private int requestId = 0;

    # Initializes a new MCP client and establishes connection to the server.
    # Performs protocol handshake and capability exchange. Client is ready for use after construction.
    #
    # + serverUrl - MCP server URL
    # + config - Client configuration including info and capabilities
    # + return - ClientError if initialization fails, nil on success
    public isolated function init(string serverUrl, *ClientConfiguration config) returns ClientError? {
        // Create and initialize transport.
        StreamableHttpClientTransport newTransport = check new StreamableHttpClientTransport(serverUrl);
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
                capabilities: config.capabilityConfig?.capabilities ?: {},
                clientInfo: config.info
            }
        };

        ServerResult response = check self.sendRequestMessage(initRequest);

        if response is InitializeResult {
            final readonly & string protocolVersion = response.protocolVersion;
            // Validate protocol compatibility.
            if (!SUPPORTED_PROTOCOL_VERSIONS.some(v => v == protocolVersion)) {
                return error ProtocolVersionError(
                    string `Server protocol version '${
                        protocolVersion}' is not supported. Supported versions: ${
                        SUPPORTED_PROTOCOL_VERSIONS.toString()}.`
                );
            }

            // Store server capabilities and info.
            self.serverCapabilities = response.capabilities.cloneReadOnly();
            self.serverInfo = response.serverInfo.cloneReadOnly();

            // Send notification to complete initialization.
            InitializedNotification initNotification = {
                method: "notifications/initialized"
            };
            check self.sendNotificationMessage(initNotification);
        } else {
            return error ClientInitializationError(
                string `Initialization failed: unexpected response type '${
                    (typeof response).toString()}' received from server.`
            );
        }
    }

    # Opens a server-sent events (SSE) stream for asynchronous server-to-client communication.
    #
    # + return - Stream of JsonRpcMessages or a ClientError.
    isolated remote function subscribeToServerMessages() returns stream<JsonRpcMessage, StreamError?>|ClientError {
        lock {
            return self.transport.establishEventStream();
        }
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
        lock {
            do {
                check self.transport.terminateSession();
                self.serverCapabilities = ();
                self.serverInfo = ();
                return;
            } on fail error e {
                return error ClientError(string `Failed to disconnect from server: ${e.message()}`, e);
            }
        }
    }

    # Sends a request message to the server and returns the server's response.
    #
    # + request - The request object to send.
    # + return - ServerResult, a stream of results, or a ClientError.
    private isolated function sendRequestMessage(Request request) returns ServerResult|ClientError {
        lock {
            self.requestId += 1;

            JsonRpcRequest jsonRpcRequest = {
                ...request.cloneReadOnly(),
                jsonrpc: JSONRPC_VERSION,
                id: self.requestId
            };

            JsonRpcMessage|stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError? response =
                self.transport.sendMessage(jsonRpcRequest);
            return processServerResponse(response).cloneReadOnly();
        }
    }

    # Sends a notification message to the server.
    #
    # + notification - The notification object to send.
    # + return - A ClientError if sending fails, or nil on success.
    private isolated function sendNotificationMessage(Notification notification) returns ClientError? {
        lock {
            JsonRpcNotification jsonRpcNotification = {
                ...notification.cloneReadOnly(),
                jsonrpc: JSONRPC_VERSION
            };

            _ = check self.transport.sendMessage(jsonRpcNotification);
        }
    }
}
