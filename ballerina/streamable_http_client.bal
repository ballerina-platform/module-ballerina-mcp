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

# Represents an MCP client built on top of the Streamable HTTP transport.
public distinct isolated client class StreamableHttpClient {
    # Transport for communication with the MCP server.
    private final StreamableHttpClientTransport transport;
    # Server capabilities.
    private ServerCapabilities? serverCapabilities = ();
    # Server implementation information.
    private Implementation? serverInfo = ();
    # Request ID generator for tracking requests.
    private int requestId = 0;
    private final ProtocolMode protocolMode;
    private final int maxInputRounds;
    private final InputHandler? inputHandler;
    private boolean modernSelected = false;
    private boolean connected = false;
    private string? negotiatedProtocolVersion = ();
    private Implementation clientInfo = {name: "MCP Client", version: "1.0.0"};
    private ClientCapabilities clientCapabilities = {};
    private map<ToolDefinition> toolSchemas = {};
    private map<string|string[]> schemaHeaders = {};
    private DiscoverResult? discovery = ();

    # Creates a new MCP client with the specified transport configuration.
    #
    # + serverUrl - MCP server URL
    # + config - Client transport configuration
    # + return - `ClientError` if transport creation fails, `()` on success
    public isolated function init(string serverUrl, *StreamableHttpClientConfig config) returns ClientError? {
        if config.maxInputRounds < 0 {
            return error ClientInitializationError("maxInputRounds must be non-negative");
        }
        if config.protocolMode == "modern" && config.sessionId is string {
            return error ClientInitializationError("A legacy session ID cannot be used in modern protocol mode");
        }
        self.protocolMode = config.sessionId is string ? "legacy" : config.protocolMode;
        self.maxInputRounds = config.maxInputRounds;
        self.inputHandler = config.inputHandler;
        self.transport = check new (serverUrl, config);
    }

    # Connects to the MCP server and negotiates the protocol version.
    #
    # + clientInfo - Client implementation information
    # + capabilities - Client capabilities to advertise
    # + headers - Optional headers to include with the request
    # + return - Negotiated connection information or a client error
    isolated remote function connect(Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}, map<string|string[]> headers = {})
            returns ConnectionInfo|ClientError {
        lock {
            if self.connected {
                return self.getConnectionInfo();
            }
            self.clientInfo = clientInfo.cloneReadOnly();
            self.clientCapabilities = capabilities.cloneReadOnly();
            string? sessionId = self.transport.getSessionId();

            // If a session ID exists, assume reconnection and skip initialization.
            if sessionId is string {
                self.negotiatedProtocolVersion = LATEST_LEGACY_PROTOCOL_VERSION;
                self.transport.setProtocolVersion(LATEST_LEGACY_PROTOCOL_VERSION);
                self.serverCapabilities = {};
                self.connected = true;
                return self.getConnectionInfo();
            }
        }

        if self.protocolMode != "legacy" {
            DiscoverResult|ClientError discovered = self.discoverModern(headers);
            if discovered is DiscoverResult {
                if discovered.supportedVersions.some(versionValue => versionValue == MODERN_PROTOCOL_VERSION) {
                    DiscoverResult & readonly discoveredInfo = discovered.cloneReadOnly();
                    lock {
                        self.modernSelected = true;
                        self.connected = true;
                        self.negotiatedProtocolVersion = MODERN_PROTOCOL_VERSION;
                        self.transport.setProtocolVersion(MODERN_PROTOCOL_VERSION);
                        self.discovery = discoveredInfo;
                        self.serverCapabilities = discoveredInfo.capabilities;
                        self.serverInfo = discoveredInfo._meta?.serverInfo;
                    }
                    return self.getConnectionInfo();
                }
                if self.protocolMode == "modern" {
                    return error ProtocolVersionError("Server does not support the modern protocol version");
                }
            } else if self.protocolMode == "modern" || !shouldUseLegacy(discovered) {
                return discovered;
            }
        }
        return self.initializeLegacyConnection(clientInfo, capabilities, headers);
    }

    # Performs the legacy initialize handshake explicitly and connects this client.
    #
    # + clientInfo - Client implementation information
    # + capabilities - Client capabilities to advertise
    # + headers - Optional headers to include with the request
    # + return - Negotiated legacy connection information or a client error
    isolated remote function initializeLegacy(
            Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}, map<string|string[]> headers = {})
            returns ConnectionInfo|ClientError {
        lock {
            if self.connected {
                return error ClientInitializationError("Client is already connected");
            }
            self.clientInfo = clientInfo.cloneReadOnly();
            self.clientCapabilities = capabilities.cloneReadOnly();
        }
        return self.initializeLegacyConnection(clientInfo, capabilities, headers);
    }

    private isolated function initializeLegacyConnection(Implementation clientInfo,
            ClientCapabilities capabilities, map<string|string[]> headers) returns ConnectionInfo|ClientError {
        InitializeRequest initRequest = {
            params: {
                protocolVersion: LATEST_LEGACY_PROTOCOL_VERSION,
                capabilities: capabilities,
                clientInfo: clientInfo
            }
        };

        ServerResult response = check self.sendRequestMessage(initRequest, headers);

        if response !is InitializeResult {
            return error ClientInitializationError(
                    string `Initialization failed: unexpected response type '${
                        (typeof response).toString()}' received from server.`
                );
        }

        // Validate protocol compatibility.
        final string protocolVersion = response.protocolVersion;
        if (protocolVersion == MODERN_PROTOCOL_VERSION || !SUPPORTED_PROTOCOL_VERSIONS.some(v => v == protocolVersion)) {
            return error ProtocolVersionError(
                    string `Server protocol version '${
                        protocolVersion}' is not supported. Supported versions: ${
                        SUPPORTED_PROTOCOL_VERSIONS.toString()}.`
                );
        }

        lock {
            self.serverCapabilities = response.capabilities.cloneReadOnly();
            self.serverInfo = response.serverInfo.cloneReadOnly();
            self.negotiatedProtocolVersion = protocolVersion;
            // Record the negotiated version so it is sent as the MCP-Protocol-Version header
            // on all subsequent requests (including the initialized notification below).
            self.transport.setProtocolVersion(protocolVersion);
        }

        check self.sendNotificationMessage(<InitializedNotification>{}, headers);
        lock {
            self.connected = true;
        }
        return self.getConnectionInfo();
    }

    # Retrieves the list of available tools from the server.
    #
    # + headers - Optional headers to include with the request
    # + cursor - Optional cursor returned by a previous tools/list response
    # + return - List of available tools or a ClientError.
    isolated remote function listTools(map<string|string[]> headers = {}, Cursor? cursor = ())
            returns ListToolsResult|ClientError {
        check self.ensureConnected();
        RequestParams listParams = {};
        if cursor is Cursor {
            listParams["cursor"] = cursor;
        }
        if !self.isModern() {
            ServerResult legacyResult = check self.sendRequestMessage(
                {method: REQUEST_LIST_TOOLS, params: listParams}, headers);
            if legacyResult is ListToolsResult {
                return legacyResult;
            }
            return error ListToolsError(
                string `Tool listing failed: unexpected result type '${(typeof legacyResult).toString()}' received.`
            );
        }
        Result wireResult = check self.sendModernRequest(REQUEST_LIST_TOOLS, listParams, headers);
        if wireResult["resultType"] != "complete" || !wireResult.hasKey("ttlMs") ||
                !wireResult.hasKey("cacheScope") {
            return error ListToolsError("Invalid modern tools/list result");
        }
        ListToolsResult|error listResult = applicationResult(wireResult, preserveCacheHints = true).cloneWithType();
        if listResult is error {
            return error ListToolsError("Invalid modern tools/list result: " + listResult.message(), listResult);
        }
        ToolDefinition[] acceptedTools = [];
        map<ToolDefinition> toolSchemas = {};
        foreach ToolDefinition toolInfo in listResult.tools {
            var validationResult = toolParameterHeaders(toolInfo.inputSchema, {});
            if validationResult is Error {
                continue;
            }
            acceptedTools.push(toolInfo);
            toolSchemas[toolInfo.name] = toolInfo;
        }
        listResult.tools = acceptedTools;
        lock {
            self.toolSchemas = toolSchemas.cloneReadOnly();
            self.schemaHeaders = headers.cloneReadOnly();
        }
        return listResult;
    }

    # Executes a tool on the server with the given parameters.
    #
    # + params - Tool execution parameters, including name and arguments
    # + headers - Optional headers to include with the request
    # + return - Result of the tool execution or a ClientError.
    isolated remote function callTool(CallToolParams params, map<string|string[]> headers = {})
            returns CallToolResult|ClientError {
        check self.ensureConnected();
        if self.isModern() {
            CallToolParams currentParams = params.clone();
            foreach int roundNumber in 0 ... self.maxInputRounds {
                CallToolResult|InputRequiredResult callResult = check self->callToolOnce(currentParams, headers);
                if callResult is CallToolResult {
                    return callResult.cloneReadOnly();
                }
                if roundNumber == self.maxInputRounds {
                    return error ToolCallError("Maximum input-required continuation rounds exceeded", inputRequired = callResult);
                }
                InputRequiredResult inputResult = <InputRequiredResult>callResult;
                map<InputResponse> inputResponses = {};
                foreach var [inputId, inputRequest] in (inputResult.inputRequests ?: {}).entries() {
                    InputHandler? inputHandler = self.inputHandler;
                    if inputHandler is () {
                        return error ToolCallError("Input handler is not configured; use callToolOnce() for manual continuation",
                                inputRequired = callResult);
                    }
                    inputResponses[inputId] = check inputHandler(inputRequest);
                }
                currentParams.inputResponses = inputResponses;
                if inputResult.requestState is string {
                    currentParams.requestState = inputResult.requestState;
                } else {
                    _ = currentParams.removeIfHasKey("requestState");
                }
            }
            return error ToolCallError("Input-required continuation did not complete");
        }
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

        ServerResult result = check self.sendRequestMessage(toolCallRequest, headers);
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
    # + return - A `ClientError` if closure fails, or `()` on success.
    isolated remote function close() returns ClientError? {
        lock {
            do {
                StreamError? subscriptionError = self.transport.closeSubscriptions();
                check self.transport.terminateSession();
                self.serverCapabilities = ();
                self.serverInfo = ();
                self.connected = false;
                self.negotiatedProtocolVersion = ();
                self.modernSelected = false;
                self.discovery = ();
                self.toolSchemas = {};
                self.schemaHeaders = {};
                return subscriptionError;
            } on fail error e {
                return error ClientError(string `Failed to disconnect from server: ${e.message()}`, e);
            }
        }
    }

    # Opens a notification stream. Modern peers use subscriptions/listen; legacy peers use the GET event stream.
    # + notifications - Requested notification types
    # + headers - Additional request headers
    # + return - Notification stream, or a client error; close the stream to cancel it
    isolated remote function listen(SubscriptionFilter notifications = {toolsListChanged: true},
            map<string|string[]> headers = {}) returns stream<JsonRpcMessage, StreamError?>|ClientError {
        check self.ensureConnected();
        if !self.isModern() {
            return self.transport.establishEventStream();
        }
        JsonRpcRequest requestMessage;
        lock {
            self.requestId += 1;
            requestMessage = {
                jsonrpc: JSONRPC_VERSION,
                id: self.requestId,
                method: "subscriptions/listen",
                params: {
                    "notifications": notifications.cloneReadOnly(),
                    _meta: {
                        [PROTOCOL_META_KEY]: MODERN_PROTOCOL_VERSION,
                        [CLIENT_INFO_META_KEY]: self.clientInfo.cloneReadOnly(),
                        [CAPABILITIES_META_KEY]: self.clientCapabilities.cloneReadOnly()
                    }
                }
            };
        }
        return self.transport.openProtocolSubscription(requestMessage, notifications, headers);
    }

    # Retrieves discovery information without a legacy initialize request.
    # + headers - Additional HTTP request headers
    # + return - Discovery metadata or a client error
    isolated remote function discover(map<string|string[]> headers = {}) returns DiscoverResult|ClientError {
        return self.discoverModern(headers);
    }

    # Adopts a previously obtained modern discovery result without another network request.
    #
    # + discovered - Previously obtained discovery result
    # + clientInfo - Client implementation information
    # + capabilities - Client capabilities to advertise on subsequent requests
    # + return - Adopted connection information or a client error
    public isolated function adoptDiscovery(DiscoverResult discovered,
            Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}) returns ConnectionInfo|ClientError {
        if !discovered.supportedVersions.some(versionValue => versionValue == MODERN_PROTOCOL_VERSION) {
            return error ProtocolVersionError("Discovery result does not advertise the modern protocol version");
        }
        Implementation? discoveredServerInfo = discovered._meta?.serverInfo;
        lock {
            if self.connected {
                return error ClientInitializationError("Client is already connected");
            }
            self.clientInfo = clientInfo.cloneReadOnly();
            self.clientCapabilities = capabilities.cloneReadOnly();
            self.modernSelected = true;
            self.connected = true;
            self.negotiatedProtocolVersion = MODERN_PROTOCOL_VERSION;
            self.transport.setProtocolVersion(MODERN_PROTOCOL_VERSION);
            self.discovery = discovered.cloneReadOnly();
            self.serverCapabilities = discovered.capabilities.cloneReadOnly();
            self.serverInfo = discoveredServerInfo is Implementation ? discoveredServerInfo.cloneReadOnly() : ();
        }
        return self.getConnectionInfo();
    }

    # Executes a single request, preserving arbitrary structured output and input-required results.
    # Continuations supply inputResponses and the unchanged requestState in params.
    # + params - Tool arguments and optional continuation inputs
    # + headers - Additional HTTP request headers
    # + return - A completed result, input-required result, or client error
    isolated remote function callToolOnce(CallToolParams params, map<string|string[]> headers = {})
            returns CallToolResult|InputRequiredResult|ClientError {
        check self.ensureConnected();
        if !self.isModern() {
            return self->callTool(params, headers);
        }
        return self.callModernTool(params, headers, true);
    }

    private isolated function callModernTool(CallToolParams params, map<string|string[]> headers, boolean refreshAllowed)
            returns CallToolResult|InputRequiredResult|ClientError {
        if params.task !is () {
            return error ToolCallError("Legacy task parameters cannot be sent to modern servers");
        }
        ToolDefinition? toolInfo = ();
        lock {
            if self.schemaHeaders == headers.cloneReadOnly() {
                toolInfo = self.toolSchemas[params.name].cloneReadOnly();
            }
        }
        Cursor? nextCursor = ();
        map<boolean> visitedCursors = {};
        while toolInfo is () {
            ListToolsResult pageResult = check self->listTools(headers, nextCursor);
            foreach ToolDefinition listedTool in pageResult.tools {
                if listedTool.name == params.name {
                    toolInfo = listedTool;
                    break;
                }
            }
            nextCursor = pageResult.nextCursor;
            if nextCursor is () {
                break;
            }
            if visitedCursors.hasKey(nextCursor) || visitedCursors.length() >= 1000 {
                return error ToolCallError("Tool pagination repeated a cursor or exceeded the page limit");
            }
            visitedCursors[nextCursor] = true;
        }
        if toolInfo is () {
            return error ToolCallError("Tool is unavailable or has invalid header annotations: " + params.name);
        }
        map<string>|Error mirroredHeaders = toolParameterHeaders(toolInfo.inputSchema, params.arguments ?: {});
        if mirroredHeaders is Error {
            return error ToolCallError(mirroredHeaders.message());
        }
        Result|ClientError responseValue = self.sendModernRequest(REQUEST_CALL_TOOL, params, headers, mirroredHeaders);
        if responseValue is ClientError {
            var rpcValue = responseValue.detail()["rpcError"];
            if refreshAllowed && rpcValue is JsonRpcError && rpcValue.'error.code == HEADER_MISMATCH {
                lock {
                    self.toolSchemas = {};
                }
                return self.callModernTool(params, headers, false);
            }
            return responseValue;
        }
        Result wireResult = responseValue;
        if wireResult["resultType"] == "input_required" {
            InputRequiredResult|error inputResult = wireResult.cloneWithType();
            if inputResult is error || (inputResult.inputRequests is () && inputResult.requestState is ()) {
                return error ToolCallError("Invalid input-required result");
            }
            return inputResult;
        }
        if wireResult["resultType"] != "complete" {
            return error ToolCallError("Invalid tool result");
        }
        CallToolResult|error callResult = applicationResult(wireResult).cloneWithType();
        if callResult is error {
            return error ToolCallError("Invalid tool result", callResult);
        }
        OutputSchema? outputSchema = toolInfo.outputSchema;
        if outputSchema is OutputSchema && callResult.isError != true {
            if !callResult.hasKey("structuredContent") {
                return error ToolCallError("Server omitted structuredContent required by outputSchema");
            }
        }
        return callResult;
    }

    private isolated function isModern() returns boolean {
        lock {
            return self.modernSelected;
        }
    }

    private isolated function getConnectionInfo() returns ConnectionInfo|ClientError {
        lock {
            string? protocolVersion = self.negotiatedProtocolVersion;
            ServerCapabilities? capabilities = self.serverCapabilities;
            if protocolVersion is () || capabilities is () {
                return error ClientInitializationError("Client connection information is unavailable");
            }
            ConnectionInfo connection = {protocolVersion, capabilities};
            if self.serverInfo is Implementation {
                connection.serverInfo = self.serverInfo;
            }
            string? instructions = self.discovery?.instructions;
            if instructions is string {
                connection.instructions = instructions;
            }
            return connection.cloneReadOnly();
        }
    }

    private isolated function ensureConnected() returns ClientError? {
        lock {
            if self.connected {
                return;
            }
            return error ClientInitializationError("Client is not connected; call connect() first");
        }
    }

    private isolated function discoverModern(map<string|string[]> headers) returns DiscoverResult|ClientError {
        Result wireResult = check self.sendModernRequest("server/discover", {}, headers);
        DiscoverResult|error discovery = applicationResult(wireResult, preserveCacheHints = true).cloneWithType();
        if discovery is error || wireResult["resultType"] != "complete" || !wireResult.hasKey("ttlMs") ||
                !wireResult.hasKey("cacheScope") {
            return error ResponseParsingError("Invalid discovery result");
        }
        return discovery;
    }

    private isolated function sendModernRequest(string methodName, RequestParams requestParams,
            map<string|string[]> headers, map<string> parameterHeaders = {}) returns Result|ClientError {
        JsonRpcRequest requestMessage;
        lock {
            self.requestId += 1;
            RequestParams wireParams = {...requestParams.cloneReadOnly()};
            RequestMetaObject requestMeta = {...(wireParams._meta ?: {})};
            requestMeta[PROTOCOL_META_KEY] = MODERN_PROTOCOL_VERSION;
            requestMeta[CLIENT_INFO_META_KEY] = self.clientInfo;
            requestMeta[CAPABILITIES_META_KEY] = self.clientCapabilities;
            wireParams._meta = requestMeta;
            requestMessage = {jsonrpc: JSONRPC_VERSION, id: self.requestId, method: methodName, params: wireParams.cloneReadOnly()};
        }
        return self.transport.sendProtocolRequest(requestMessage, headers, parameterHeaders);
    }

    # Sends a request message to the server and returns the server's response.
    #
    # + request - The request object to send
    # + headers - Optional headers to include with the request
    # + return - ServerResult, a stream of results, or a ClientError.
    private isolated function sendRequestMessage(Request request, map<string|string[]> headers = {})
            returns ServerResult|ClientError {
        lock {
            self.requestId += 1;

            JsonRpcRequest jsonRpcRequest = {
                ...request.cloneReadOnly(),
                jsonrpc: JSONRPC_VERSION,
                id: self.requestId
            };

            JsonRpcMessage|stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError? response =
                self.transport.sendMessage(jsonRpcRequest, headers.cloneReadOnly());
            return processServerResponse(response).cloneReadOnly();
        }
    }

    # Sends a notification message to the server.
    #
    # + notification - The notification object to send.
    # + headers - Additional HTTP request headers
    # + return - A `ClientError` if sending fails, or `()` on success.
    private isolated function sendNotificationMessage(Notification notification, map<string|string[]> headers = {}) returns ClientError? {
        lock {
            JsonRpcNotification jsonRpcNotification = {
                ...notification.cloneReadOnly(),
                jsonrpc: JSONRPC_VERSION
            };

            _ = check self.transport.sendMessage(jsonRpcNotification, headers.cloneReadOnly());
        }
    }
}
