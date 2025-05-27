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

type ServerMessageHandler function (JSONRPCServerMessage serverMessage) returns error?;

public distinct client class Client {
    private final string url;
    private StreamableHttpClientTransport? transport = ();
    private ServerCapabilities? serverCapabilities = ();
    private Implementation? serverVersion = ();
    private final Implementation clientInfo;
    private ClientCapabilities capabilities;
    private int requestMessageId = 0;

    private ServerMessageHandler? serverMessageHandler = ();

    function init(string url, Implementation clientInfo, ClientOptions? options = ()) {
        self.url = url;
        self.clientInfo = clientInfo;
        self.capabilities = options?.capabilities ?: {};
    }

    public function connect() returns error? {
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
            JSONRPCServerMessage|stream<JSONRPCServerMessage, error?>|() response = check self.sendRequest(initRequest);
            InitializeResult initResult = check handleInitializeResponse(response);

            if (!SUPPORTED_PROTOCOL_VERSIONS.some(v => v == initResult.protocolVersion)) {
                return error ClientInitializationError("Server's protocol version is not supported: " + initResult.protocolVersion);
            }
            self.serverCapabilities = initResult.capabilities;
            self.serverVersion = initResult.serverInfo;

            // Set the notification response handler
            transport.setSseHandler(self.handleSseStream);

            // Send the initialized notification
            InitializedNotification initNotification = {
                method: "notifications/initialized"
            };
            check self.sendNotification(initNotification);
        } else {
            return error TransportInitializationError("Failed to initialize transport for MCP client");
        }
    }

    public function listTools() returns ListToolsResult|error {
        ListToolsRequest listToolRequest = {
            method: "tools/list"
        };
        JSONRPCServerMessage|stream<JSONRPCServerMessage, error?>|() response = check self.sendRequest(listToolRequest);
        ListToolsResult listToolResult = check handleListToolResult(response);
        return listToolResult;
    }

    public function callTool(CallToolParams params) returns JSONRPCServerMessage|stream<JSONRPCServerMessage, error?>|error {
        CallToolRequest callToolRequest = {
            method: "tools/call",
            params: params
        };
        JSONRPCServerMessage|stream<JSONRPCServerMessage, error?>|() response = check self.sendRequest(callToolRequest);
        if response is () {
            return error CallToolError("Received invalid response for tool call");
        }
        return response;
    }

    public function waitForCompletion() returns error? {
        StreamableHttpClientTransport? transport = self.transport;
        if transport is () {
            return error UninitializedTransportError("Transport is not initialized for sending requests");
        }

        return transport.waitForCompletion();
    }

    public function setNotificationHandler(function (JSONRPCServerMessage) returns error? serverMessageHandler) returns error? {
        self.serverMessageHandler = serverMessageHandler;
    }

    private function sendRequest(Request request) returns JSONRPCServerMessage|stream<JSONRPCServerMessage, error?>|error? {
        StreamableHttpClientTransport? transport = self.transport;
        if transport is () {
            return error UninitializedTransportError("Transport is not initialized for sending requests");
        }

        self.requestMessageId += 1;
        JSONRPCRequest jsonrpcRequest = {
            ...request,
            jsonrpc: JSONRPC_VERSION,
            id: self.requestMessageId
        };

        return transport.send(jsonrpcRequest);
    }

    private function sendNotification(Notification notification) returns error? {
        StreamableHttpClientTransport? transport = self.transport;
        if transport is () {
            return error UninitializedTransportError("Transport is not initialized for sending requests");
        }

        JSONRPCNotification jsonrpcNotification = {
            ...notification,
            jsonrpc: JSONRPC_VERSION
        };

        _ = check transport.send(jsonrpcNotification);

    }

    private function handleSseStream(stream<JSONRPCServerMessage, error?> 'stream) returns future<error?> {
        worker SseWorker returns error? {
            check from JSONRPCServerMessage serverMessage in 'stream
                do {
                    ServerMessageHandler? handler = self.serverMessageHandler;
                    if handler is ServerMessageHandler {
                        check handler(serverMessage);
                    }
                };
        }
        return SseWorker;
    }
}
