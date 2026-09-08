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
    private boolean initialized = false;
    private Implementation clientInfo = {name: "MCP Client", version: "1.0.0"};
    private ClientCapabilities clientCapabilities = {};
    private map<ProtocolToolDefinition> toolSchemas = {};
    private DiscoverResult? discovery = ();

    # Creates a new MCP client with the specified transport configuration.
    #
    # + serverUrl - MCP server URL
    # + config - Client transport configuration
    # + return - `ClientError` if transport creation fails, `()` on success
    public isolated function init(string serverUrl, *StreamableHttpClientTransportConfig config) returns ClientError? {
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

    # Initializes the MCP connection by performing protocol handshake and capability exchange.
    #
    # + clientInfo - Client implementation information
    # + capabilities - Client capabilities to advertise
    # + headers - Optional headers to include with the request
    # + return - `ClientError` if initialization fails, `()` on success
    isolated remote function initialize(Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}, map<string|string[]> headers = {}) returns ClientError? {
        lock {
            if self.initialized {
                return;
            }
            self.clientInfo = clientInfo.cloneReadOnly();
            self.clientCapabilities = capabilities.cloneReadOnly();
            string? sessionId = self.transport.getSessionId();

            // If a session ID exists, assume reconnection and skip initialization.
            if sessionId is string {
                return;
            }
        }

        if self.protocolMode != "legacy" {
            DiscoverResult|ClientError discovered = self.discoverModern(headers);
            if discovered is DiscoverResult {
                if discovered.supportedVersions.some(versionValue => versionValue == MODERN_PROTOCOL_VERSION) {
                    DiscoverResult & readonly discoveredInfo = discovered.cloneReadOnly();
                    lock {
                        self.modernSelected = true;
                        self.initialized = true;
                        self.discovery = discoveredInfo;
                        self.serverCapabilities = discoveredInfo.capabilities;
                        record {} discoveryMeta = (discoveredInfo._meta ?: {}).clone();
                        anydata identity = discoveryMeta[SERVER_INFO_META_KEY];
                        self.serverInfo = identity is Implementation ? identity.cloneReadOnly() : ();
                    }
                    return;
                }
                if self.protocolMode == "modern" {
                    return error ProtocolVersionError("Server does not support the modern protocol version");
                }
            } else if self.protocolMode == "modern" || !shouldUseLegacy(discovered) {
                return discovered;
            }
        }
        // The initialize handshake can negotiate only handshake-era versions.
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
            // Record the negotiated version so it is sent as the MCP-Protocol-Version header
            // on all subsequent requests (including the initialized notification below).
            self.transport.setProtocolVersion(protocolVersion);
        }

        check self.sendNotificationMessage(<InitializedNotification>{}, headers);
        lock {
            self.initialized = true;
        }
    }

    # Opens a server-sent events (SSE) stream for asynchronous server-to-client communication.
    #
    # + return - Stream of JsonRpcMessages or a ClientError.
    isolated remote function subscribeToServerMessages() returns stream<JsonRpcMessage, StreamError?>|ClientError {
        lock {
            if self.modernSelected {
                return error ClientError("Modern MCP uses subscriptions/listen; legacy GET subscriptions are unavailable");
            }
            return self.transport.establishEventStream();
        }
    }

    # Retrieves the list of available tools from the server.
    #
    # + headers - Optional headers to include with the request
    # + return - List of available tools or a ClientError.
    isolated remote function listTools(map<string|string[]> headers = {}) returns ListToolsResult|ClientError {
        check self.ensureInitialized(headers);
        if self.isModern() {
            ProtocolListToolsResult protocolResult = check self->listToolsWithSchemas(headers);
            ListToolsResult|error compatibilityResult = protocolResult.cloneWithType();
            if compatibilityResult is error {
                return error ListToolsError("Tool output schemas require listToolsWithSchemas()", compatibilityResult);
            }
            return compatibilityResult;
        }
        ListToolsRequest listToolsRequest = {};

        ServerResult result = check self.sendRequestMessage(listToolsRequest, headers);
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
    # + params - Tool execution parameters, including name and arguments
    # + headers - Optional headers to include with the request
    # + return - Result of the tool execution or a ClientError.
    isolated remote function callTool(CallToolParams params, map<string|string[]> headers = {})
            returns CallToolResult|ClientError {
        check self.ensureInitialized(headers);
        if self.isModern() {
            CallToolParams currentParams = params.clone();
            foreach int roundNumber in 0 ... self.maxInputRounds {
                ProtocolCallToolResult|InputRequiredResult callResult = check self->callToolWithResult(currentParams, headers);
                if callResult is ProtocolCallToolResult {
                    CallToolResult|error compatibilityResult = callResult.cloneWithType();
                    if compatibilityResult is error {
                        return error ToolCallError("Structured output requires callToolWithResult()", compatibilityResult);
                    }
                    return compatibilityResult;
                }
                if roundNumber == self.maxInputRounds {
                    return error ToolCallError("Maximum input-required continuation rounds exceeded", inputRequired = callResult);
                }
                InputRequiredResult inputResult = <InputRequiredResult>callResult;
                map<InputResponse> inputResponses = {};
                foreach var [inputId, inputRequest] in (inputResult.inputRequests ?: {}).entries() {
                    InputHandler? inputHandler = self.inputHandler;
                    if inputHandler is () {
                        return error ToolCallError("Input handler is not configured; use callToolWithResult() for manual continuation",
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
                check self.transport.terminateSession();
                self.serverCapabilities = ();
                self.serverInfo = ();
                self.initialized = false;
                self.modernSelected = false;
                self.discovery = ();
                self.toolSchemas = {};
                return;
            } on fail error e {
                return error ClientError(string `Failed to disconnect from server: ${e.message()}`, e);
            }
        }
    }

    # Retrieves discovery information without a legacy initialize request.
    # + headers - Additional HTTP request headers
    # + return - Discovery metadata or a client error
    isolated remote function discover(map<string|string[]> headers = {}) returns DiscoverResult|ClientError {
        return self.discoverModern(headers);
    }

    # Lists tools preserving modern output schemas. Invalid header annotations are excluded individually.
    # + headers - Additional HTTP request headers
    # + return - Tool definitions or a client error
    isolated remote function listToolsWithSchemas(map<string|string[]> headers = {}) returns ProtocolListToolsResult|ClientError {
        check self.ensureInitialized(headers);
        if !self.isModern() {
            ListToolsResult legacyResult = check self->listTools(headers);
            ProtocolListToolsResult|error converted = legacyResult.cloneWithType();
            return converted is error ? error ListToolsError(converted.message()) : converted;
        }
        Result wireResult = check self.sendModernRequest(REQUEST_LIST_TOOLS, {}, headers);
        ProtocolListToolsResult|error listResult = wireResult.cloneWithType();
        if listResult is error || wireResult["resultType"] != "complete" || !wireResult.hasKey("ttlMs") ||
                !wireResult.hasKey("cacheScope") {
            return error ListToolsError("Invalid modern tools/list result");
        }
        ProtocolToolDefinition[] acceptedTools = [];
        map<ProtocolToolDefinition> toolSchemas = {};
        foreach ProtocolToolDefinition toolInfo in listResult.tools {
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
        }
        return listResult;
    }

    # Executes a single request, preserving arbitrary structured output and input-required results.
    # Continuations supply inputResponses and the unchanged requestState in params.
    # + params - Tool arguments and optional continuation inputs
    # + headers - Additional HTTP request headers
    # + return - A completed result, input-required result, or client error
    isolated remote function callToolWithResult(CallToolParams params, map<string|string[]> headers = {})
            returns ProtocolCallToolResult|InputRequiredResult|ClientError {
        check self.ensureInitialized(headers);
        if !self.isModern() {
            CallToolResult legacyResult = check self->callTool(params, headers);
            ProtocolCallToolResult|error converted = legacyResult.cloneWithType();
            return converted is error ? error ToolCallError(converted.message()) : converted;
        }
        if params.task !is () {
            return error ToolCallError("Legacy task parameters cannot be sent to modern servers");
        }
        ProtocolToolDefinition? toolInfo;
        lock {
            toolInfo = self.toolSchemas[params.name].cloneReadOnly();
        }
        if toolInfo is () {
            _ = check self->listToolsWithSchemas(headers);
            lock {
                toolInfo = self.toolSchemas[params.name].cloneReadOnly();
            }
        }
        if toolInfo is () {
            return error ToolCallError("Tool is unavailable or has invalid header annotations: " + params.name);
        }
        map<string>|Error mirroredHeaders = toolParameterHeaders(toolInfo.inputSchema, params.arguments ?: {});
        if mirroredHeaders is Error {
            return error ToolCallError(mirroredHeaders.message());
        }
        Result wireResult = check self.sendModernRequest(REQUEST_CALL_TOOL, params, headers, mirroredHeaders);
        if wireResult["resultType"] == "input_required" {
            InputRequiredResult|error inputResult = wireResult.cloneWithType();
            if inputResult is error || (inputResult.inputRequests is () && inputResult.requestState is ()) {
                return error ToolCallError("Invalid input-required result");
            }
            return inputResult;
        }
        ProtocolCallToolResult|error callResult = wireResult.cloneWithType();
        return callResult is error ? error ToolCallError("Invalid tool result", callResult) : callResult;
    }

    private isolated function isModern() returns boolean {
        lock {
            return self.modernSelected;
        }
    }

    private isolated function ensureInitialized(map<string|string[]> headers) returns ClientError? {
        lock {
            if self.initialized || self.transport.getSessionId() is string {
                return;
            }
        }
        return self->initialize(headers = headers);
    }

    private isolated function discoverModern(map<string|string[]> headers) returns DiscoverResult|ClientError {
        Result wireResult = check self.sendModernRequest("server/discover", {}, headers);
        DiscoverResult|error discovery = wireResult.cloneWithType();
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
            Meta requestMeta = {...(wireParams._meta ?: {})};
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
