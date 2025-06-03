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

# Client options for protocol initialization.
#
# + capabilities - Capabilities to advertise as being supported by this client.
public type ClientOptions record {|
    *ProtocolOptions;
    ClientCapabilities capabilities?;
|};

# An MCP client on top of the Streamable HTTP transport.
public distinct client class Client {
    # The URL of the MCP server.
    private final string url;
    # Information about the client, such as name and version.
    private final Implementation clientInfo;
    # The capabilities of the client.
    private final ClientCapabilities capabilities;

    # The transport used for communication with the MCP server.
    private StreamableHttpClientTransport? transport = ();
    # The server capabilities.
    private ServerCapabilities? serverCapabilities = ();
    # The server version information.
    private Implementation? serverVersion = ();
    # Request message ID for tracking requests.
    private int requestMessageId = 0;

    # Initializes a new MCP client with the given URL and client information.
    # 
    # + url - The URL of the MCP server.
    # + clientInfo - Information about the client, such as name and version.
    # + options - Optional capabilities to advertise as being supported by this client.
    public isolated function init(string url, Implementation clientInfo, ClientOptions? options = ()) {
        self.url = url;
        self.clientInfo = clientInfo;
        self.capabilities = options?.capabilities ?: {};
    }

    # Initializes the transport and establishes a connection with the MCP server.
    # 
    # + return - nil on success, or an `mcp:Error` on failure.
    isolated remote function initialize() returns error? {
        lock {
            self.transport = check new StreamableHttpClientTransport(self.url);

            StreamableHttpClientTransport? transport = self.transport;
            if transport is StreamableHttpClientTransport {
                string? sessionId = transport.getSessionId();
                // If sessionId is non-null, it means the server is trying to reconnect
                if sessionId is string {
                    return;
                }

                // If sessionId is null, it means the server is trying to establish a new connection
                InitializeRequest initRequest = {
                    method: "initialize",
                    params: {
                        protocolVersion: LATEST_PROTOCOL_VERSION,
                        capabilities: self.capabilities,
                        clientInfo: self.clientInfo
                    }
                };
                JsonRpcMessage|stream<JsonRpcMessage, error?>|() response = check self.sendRequest(initRequest);
                final readonly & InitializeResult initResult = (check handleInitializeResponse(response)).cloneReadOnly();

                if (!SUPPORTED_PROTOCOL_VERSIONS.some(v => v == initResult.protocolVersion)) {
                    return error ClientInitializationError("Server's protocol version is not supported: " + initResult.protocolVersion);
                }
                self.serverCapabilities = initResult.capabilities;
                self.serverVersion = initResult.serverInfo;

                // Send the initialized notification
                InitializedNotification initNotification = {
                    method: "notifications/initialized"
                };
                check self.sendNotification(initNotification);
            } else {
                return error UninitializedTransportError("Failed to initialize transport for MCP client");
            }
        }
    }

    # Initializes an SSE stream, allowing the server to communicate with the client asynchronously.
    # 
    # + return - A stream of JSON-RPC messages from the server, or an `mcp:Error` on failure.
    isolated remote function subscribeToServerMessages() returns stream<JsonRpcMessage, error?>|error {
        StreamableHttpClientTransport? transport = self.transport;
        if transport is () {
            return error UninitializedTransportError("Transport is not initialized for sending requests");
        }

        return check transport.startSse();
    }

    # Lists the tools available on the MCP server.
    # 
    # + return - A list of tools available on the server, or an `mcp:Error` on failure.
    isolated remote function listTools() returns ListToolsResult|error {
        ListToolsRequest listToolRequest = {
            method: "tools/list"
        };
        JsonRpcMessage|stream<JsonRpcMessage, error?>|() response = check self.sendRequest(listToolRequest);
        ListToolsResult listToolResult = check handleListToolResult(response);
        return listToolResult;
    }

    # Calls a tool on the MCP server with the specified parameters.
    # 
    # + params - The parameters for the tool call, including the tool name and arguments.
    # + return - The result of the tool call, or an `mcp:Error` on failure.
    isolated remote function callTool(CallToolParams params) returns JsonRpcMessage|stream<JsonRpcMessage, error?>|error {
        CallToolRequest callToolRequest = {
            method: "tools/call",
            params: params
        };
        JsonRpcMessage|stream<JsonRpcMessage, error?>|() response = check self.sendRequest(callToolRequest);
        if response is () {
            return error UninitializedTransportError("Failed to initialize transport for MCP client");
            // return error CallToolError("Received invalid response for tool call");
        }
        return response;
    }

    # Closes the MCP client and terminates the transport session.
    # 
    # + return - nil on success, or an `mcp:Error` on failure.
    isolated remote function close() returns error? {
        StreamableHttpClientTransport? transport = self.transport;
        if transport is () {
            return error UninitializedTransportError("Transport is not initialized for sending requests");
        }

        return transport.terminateSession();
    }

    private isolated function sendRequest(Request request) returns JsonRpcMessage|stream<JsonRpcMessage, error?>|error? {
        StreamableHttpClientTransport? transport = self.transport;
        if transport is () {
            return error UninitializedTransportError("Streamable HTTP transport is not initialized for sending requests");
        }

        self.requestMessageId += 1;
        JsonRpcRequest jsonrpcRequest = {
            ...request,
            jsonrpc: JSONRPC_VERSION,
            id: self.requestMessageId
        };

        return transport.send(jsonrpcRequest);
    }

    private isolated function sendNotification(Notification notification) returns error? {
        StreamableHttpClientTransport? transport = self.transport;
        if transport is () {
            return error UninitializedTransportError("Streamable HTTP transport is not initialized for sending requests");
        }

        JsonRpcNotification jsonrpcNotification = {
            ...notification,
            jsonrpc: JSONRPC_VERSION
        };

        _ = check transport.send(jsonrpcNotification);
    }
}
