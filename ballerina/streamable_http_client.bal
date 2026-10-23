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

import ballerina/lang.runtime;

# Picks the newest modern revision that the server lists.
#
# + offeredVersions - The versions listed by the server
# + return - The selected modern version, or nil if none is listed
isolated function selectModernProtocolVersion(string[] offeredVersions) returns string? {
    foreach string modernVersion in MODERN_PROTOCOL_VERSIONS {
        if offeredVersions.some(offeredVersion => offeredVersion == modernVersion) {
            return modernVersion;
        }
    }
    return ();
}

// Adds the configured MCP authorization extension to the advertised capabilities.
isolated function withOAuthExtensionCapability(ClientCapabilities capabilities, string? extension)
        returns ClientCapabilities {
    ClientCapabilities advertised = capabilities.clone();
    if extension is () {
        return advertised;
    }
    map<record {}> extensions = {};
    map<record {}>? configuredExtensions = advertised.extensions;
    if configuredExtensions is map<record {}> {
        extensions = configuredExtensions.clone();
    }
    extensions[extension] = {};
    advertised.extensions = extensions;
    return advertised;
}

// Legacy initialize never carries this: the client cannot answer server-initiated elicitation.
isolated function withElicitationCapability(ClientCapabilities capabilities) returns ClientCapabilities {
    ClientCapabilities advertised = capabilities.clone();
    record {map<anydata> form?; map<anydata> url?;} elicitation = {...(advertised.elicitation ?: {})};
    elicitation.form = elicitation.form ?: {};
    elicitation.url = elicitation.url ?: {};
    advertised.elicitation = elicitation;
    return advertised;
}

// Only an accepted form carries what the user submitted; a URL answer has nothing to submit.
isolated function withSubmittedContentOnly(ElicitRequest elicitRequest, ElicitResult answer) returns ElicitResult {
    if answer.action == "accept" && elicitRequest.params is FormElicitationParams {
        return answer;
    }
    ElicitResult stripped = answer.clone();
    _ = stripped.removeIfHasKey("content");
    return stripped;
}

// No server supports task-augmented tool calls, so the client never sends `task`.
isolated function withoutTask(CallToolParams params) returns CallToolParams {
    // A spread copies even read-only params, which `clone()` would return as they are.
    CallToolParams sentParams = {...params};
    _ = sentParams.removeIfHasKey("task");
    return sentParams;
}

# Represents an MCP client built on top of the Streamable HTTP transport.
public distinct isolated client class StreamableHttpClient2 {
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
    private final ElicitationHandler? elicitationHandler;
    private boolean modernSelected = false;
    private boolean connected = false;
    private string? negotiatedProtocolVersion = ();
    private Implementation clientInfo = {name: "MCP Client", version: "1.0.0"};
    private ClientCapabilities clientCapabilities = {};
    private DiscoverResult? discovery = ();

    # Creates a new MCP client with the specified transport configuration.
    #
    # Set `config.auth` to an `mcp:OAuth2DiscoveryConfig` to have the client obtain its own
    # access tokens through MCP authorization, rather than supplying an `http:ClientAuthConfig`
    # credential yourself.
    #
    # + serverUrl - MCP server URL
    # + config - Client transport configuration
    # + return - `ClientError` if transport creation fails, `()` on success
    public isolated function init(string serverUrl, *StreamableHttpClientConfig config) returns ClientError? {
        if config.maxInputRounds < 0 {
            return error ClientInitializationError("maxInputRounds must be non-negative");
        }
        if (config.resultCache?.maxTtlMs ?: 0) < 0 || (config.resultCache?.maxEntries ?: 0) < 0 {
            return error ClientInitializationError("resultCache limits must be non-negative");
        }
        if config.protocolMode == "modern" && config.sessionId is string {
            return error ClientInitializationError("A legacy session ID cannot be used in modern protocol mode");
        }
        if config.httpConfig.auth is OAuth2DiscoveryConfig && config.httpConfig.followRedirects?.enabled == true {
            return error ClientInitializationError("Redirects cannot be enabled with MCP authorization");
        }
        self.protocolMode = config.sessionId is string ? "legacy" : config.protocolMode;
        self.maxInputRounds = config.maxInputRounds;
        self.elicitationHandler = config.elicitationHandler;
        self.transport = check new (serverUrl, config);
        // discover() can run before connect(), so its first modern request must already
        // advertise the configured authorization extension.
        self.clientCapabilities = self.withHandlerCapabilities(
            withOAuthExtensionCapability({}, self.transport.oauthExtension()));
    }

    private isolated function withHandlerCapabilities(ClientCapabilities capabilities) returns ClientCapabilities =>
        self.elicitationHandler is () ? capabilities : withElicitationCapability(capabilities);

    # Connects to the MCP server and negotiates the protocol version.
    #
    # + clientInfo - Client implementation information
    # + capabilities - Client capabilities to advertise
    # + headers - Optional headers to include with the request
    # + return - Negotiated connection information or a client error
    isolated remote function connect(Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}, map<string|string[]> headers = {})
            returns ConnectionInfo|ClientError {
        ClientCapabilities withExtension = withOAuthExtensionCapability(capabilities, self.transport.oauthExtension());
        ClientCapabilities & readonly advertisedCapabilities = withExtension.cloneReadOnly();
        ClientCapabilities & readonly modernCapabilities = self.withHandlerCapabilities(withExtension).cloneReadOnly();
        Implementation & readonly connectingClient = clientInfo.cloneReadOnly();
        map<string|string[]> & readonly requestHeaders = headers.cloneReadOnly();
        // Held through the handshake, so a concurrent first connect() waits and reuses its result.
        lock {
            if self.connected {
                return self.getConnectionInfo();
            }
            return self.handshake(connectingClient, advertisedCapabilities, modernCapabilities, requestHeaders);
        }
    }

    private isolated function handshake(Implementation & readonly clientInfo,
            ClientCapabilities & readonly advertisedCapabilities, ClientCapabilities & readonly modernCapabilities,
            map<string|string[]> & readonly headers) returns ConnectionInfo|ClientError {
        lock {
            self.clientInfo = clientInfo;
            self.clientCapabilities = modernCapabilities;
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
                string? modernVersion = selectModernProtocolVersion(discovered.supportedVersions);
                if modernVersion is string {
                    DiscoverResult & readonly discoveredInfo = discovered.cloneReadOnly();
                    lock {
                        self.modernSelected = true;
                        self.connected = true;
                        self.negotiatedProtocolVersion = modernVersion;
                        self.transport.setProtocolVersion(modernVersion);
                        self.discovery = discoveredInfo;
                        self.serverCapabilities = discoveredInfo.capabilities;
                        self.serverInfo = discoveredInfo._meta?.serverInfo;
                    }
                    return self.getConnectionInfo();
                }
                if self.protocolMode == "modern" {
                    return error ProtocolVersionError("Server does not support the modern protocol version");
                }
                if !discovered.supportedVersions.some(isLegacyProtocolVersion) {
                    return error ProtocolVersionError("Server lists no supported protocol version");
                }
            } else if self.protocolMode == "modern" || !shouldUseLegacy(discovered) {
                return discovered;
            }
        }
        return self.initializeLegacyConnection(clientInfo, advertisedCapabilities, headers);
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
        ClientCapabilities advertisedCapabilities =
            withOAuthExtensionCapability(capabilities, self.transport.oauthExtension());
        lock {
            if self.connected {
                return error ClientInitializationError("Client is already connected");
            }
            self.clientInfo = clientInfo.cloneReadOnly();
            self.clientCapabilities = advertisedCapabilities.cloneReadOnly();
        }
        return self.initializeLegacyConnection(clientInfo, advertisedCapabilities, headers);
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

        LegacyServerResult response = check self.sendRequestMessage(initRequest, headers);

        if response !is InitializeResult {
            return error ClientInitializationError(
                    string `Initialization failed: unexpected response type '${
                        (typeof response).toString()}' received from server.`
                );
        }

        // Validate protocol compatibility.
        final string protocolVersion = response.protocolVersion;
        if !isLegacyProtocolVersion(protocolVersion) {
            return error ProtocolVersionError(
                    string `Server protocol version '${
                        protocolVersion}' is not supported. Supported versions: ${
                        LEGACY_PROTOCOL_VERSIONS.toString()}.`
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

    # Retrieves the list of available tools from the server. A modern result is reused while its
    # caching hints keep it fresh, unless `cacheMode` says otherwise. A call whose `headers` carry
    # its own `Authorization` header always bypasses the cache.
    #
    # + headers - Optional headers to include with the request
    # + cursor - Optional cursor returned by a previous tools/list response
    # + cacheMode - How this call uses the result cache
    # + return - List of available tools or a ClientError.
    isolated remote function listTools(map<string|string[]> headers = {}, Cursor? cursor = (),
            CacheMode cacheMode = "use") returns ToolPage|ClientError {
        check self.ensureConnected();
        RequestParams listParams = {};
        if cursor is Cursor {
            listParams["cursor"] = cursor;
        }
        if !self.isModern() {
            LegacyServerResult legacyResult = check self.sendRequestMessage(
                {method: REQUEST_LIST_TOOLS, params: listParams}, headers);
            if legacyResult is ToolPage {
                return legacyResult;
            }
            return error ListToolsError(
                string `Tool listing failed: unexpected result type '${(typeof legacyResult).toString()}' received.`
            );
        }
        ResultCache resultCache = self.transport.cache();
        // A credential passed on one call is not the client's authorization context, so it never shares the cache.
        CacheMode effectiveMode = hasAuthorizationHeader(headers) ? "bypass" : cacheMode;
        if effectiveMode == "use" {
            WireResult? cachedResult = resultCache.get(REQUEST_LIST_TOOLS, cursor);
            ToolPage|error cachedList = cachedResult is WireResult ? cachedResult.cloneWithType() : error("Cache miss");
            if cachedList is ToolPage {
                return cachedList;
            }
        }
        int fetchNumber = resultCache.beginFetch();
        WireResult|ClientError wireResponse = self.sendModernRequest(REQUEST_LIST_TOOLS, listParams, headers);
        if wireResponse is ClientError {
            var rpcValue = wireResponse.detail()["rpcError"];
            // A rejected cursor means the cached pages no longer describe one listing.
            if cursor is Cursor && rpcValue is JsonRpcError && rpcValue.'error.code == INVALID_PARAMS {
                resultCache.invalidate(REQUEST_LIST_TOOLS);
            }
            return wireResponse;
        }
        WireResult wireResult = wireResponse;
        if wireResult["resultType"] != "complete" || !wireResult.hasKey("ttlMs") ||
                !wireResult.hasKey("cacheScope") {
            return error ListToolsError("Invalid modern tools/list result");
        }
        ToolPage|error listResult = applicationResult(wireResult, preserveCacheHints = true).cloneWithType();
        if listResult is error {
            return error ListToolsError("Invalid modern tools/list result: " + listResult.message(), listResult);
        }
        if (listResult.ttlMs ?: 0) < 0 {
            listResult.ttlMs = 0;
        }
        listResult.tools = listResult.tools.filter(toolInfo => toolParameterHeaders(toolInfo.inputSchema, {}) !is Error);
        if effectiveMode != "bypass" {
            resultCache.put(REQUEST_LIST_TOOLS, cursor, listResult, fetchNumber);
            resultCache.recordToolSchemas(cursor, listResult.tools, fetchNumber);
        }
        return listResult;
    }

    # Executes a tool on the server with the given parameters.
    #
    # + params - Tool execution parameters, including name and arguments
    # + headers - Optional headers to include with the request
    # + return - Result of the tool execution or a ClientError.
    isolated remote function callTool(CallToolParams params, map<string|string[]> headers = {})
            returns ToolResult|ClientError {
        check self.ensureConnected();
        CallToolParams callParams = withoutTask(params);
        if self.isModern() {
            CallToolParams currentParams = callParams.clone();
            decimal stateOnlyDelay = STATE_ONLY_RETRY_DELAY;
            foreach int roundNumber in 0 ... self.maxInputRounds {
                ToolResult|InputRequiredResult callResult = check self->callToolOnce(currentParams, headers);
                if callResult is ToolResult {
                    return callResult.cloneReadOnly();
                }
                if roundNumber == self.maxInputRounds {
                    return error ToolCallError("Maximum input-required continuation rounds exceeded", inputRequired = callResult);
                }
                InputRequiredResult inputResult = <InputRequiredResult>callResult;
                map<InputResponse> inputResponses = {};
                foreach var [inputId, inputRequest] in (inputResult.inputRequests ?: {}).entries() {
                    ElicitationHandler? elicitationHandler = self.elicitationHandler;
                    if elicitationHandler is () {
                        return error ToolCallError("Elicitation handler is not configured; use callToolOnce() for manual continuation",
                                inputRequired = callResult);
                    }
                    inputResponses[inputId] = withSubmittedContentOnly(inputRequest,
                            check elicitationHandler(inputRequest));
                }
                if inputResponses.length() > 0 {
                    currentParams.inputResponses = inputResponses;
                } else {
                    _ = currentParams.removeIfHasKey("inputResponses");
                    // Nothing for the user to answer, so pace the retries of a server shedding load.
                    runtime:sleep(stateOnlyDelay);
                    stateOnlyDelay = decimal:min(stateOnlyDelay * 2, STATE_ONLY_RETRY_MAX_DELAY);
                }
                if inputResult.requestState is string {
                    currentParams.requestState = inputResult.requestState;
                } else {
                    _ = currentParams.removeIfHasKey("requestState");
                }
            }
            return error ToolCallError("Input-required continuation did not complete");
        }
        CallToolRequest toolCallRequest = {
            params: callParams
        };

        LegacyServerResult result = check self.sendRequestMessage(toolCallRequest, headers);
        if result is ToolResult {
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
            StreamableHttpTransportError? terminationError = self.transport.terminateSession();
            // Local state is reset even when the server could not be told, so the client can connect again.
            self.serverCapabilities = ();
            self.serverInfo = ();
            self.connected = false;
            self.negotiatedProtocolVersion = ();
            self.modernSelected = false;
            self.discovery = ();
            self.transport.cache().clear();
            if terminationError is StreamableHttpTransportError {
                return error ClientError(string `Failed to disconnect from server: ${terminationError.message()}`,
                        terminationError);
            }
        }
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
        string? modernVersion = selectModernProtocolVersion(discovered.supportedVersions);
        if modernVersion is () {
            return error ProtocolVersionError("Discovery result does not advertise the modern protocol version");
        }
        Implementation? discoveredServerInfo = discovered._meta?.serverInfo;
        ClientCapabilities advertisedCapabilities =
            withOAuthExtensionCapability(capabilities, self.transport.oauthExtension());
        ClientCapabilities modernCapabilities = self.withHandlerCapabilities(advertisedCapabilities);
        lock {
            if self.connected {
                return error ClientInitializationError("Client is already connected");
            }
            self.clientInfo = clientInfo.cloneReadOnly();
            self.clientCapabilities = modernCapabilities.cloneReadOnly();
            self.modernSelected = true;
            self.connected = true;
            self.negotiatedProtocolVersion = modernVersion;
            self.transport.setProtocolVersion(modernVersion);
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
            returns ToolResult|InputRequiredResult|ClientError {
        check self.ensureConnected();
        CallToolParams callParams = withoutTask(params);
        if !self.isModern() {
            return self->callTool(callParams, headers);
        }
        return self.callModernTool(callParams, headers, true);
    }

    private isolated function callModernTool(CallToolParams params, map<string|string[]> headers, boolean refreshAllowed)
            returns ToolResult|InputRequiredResult|ClientError {
        ToolInfo? toolInfo = hasAuthorizationHeader(headers) ? () : self.transport.cache().toolSchema(params.name);
        Cursor? nextCursor = ();
        map<boolean> visitedCursors = {};
        while toolInfo is () {
            ToolPage pageResult = check self->listTools(headers, nextCursor);
            foreach ToolInfo listedTool in pageResult.tools {
                if listedTool.name == params.name {
                    toolInfo = listedTool;
                    break;
                }
            }
            nextCursor = pageResult.nextCursor;
            if nextCursor is () {
                break;
            }
            if visitedCursors.hasKey(nextCursor) || visitedCursors.length() >= MAX_TOOL_LIST_PAGES - 1 {
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
        WireResult|ClientError responseValue = self.sendModernRequest(REQUEST_CALL_TOOL, params, headers, mirroredHeaders);
        if responseValue is ClientError {
            var rpcValue = responseValue.detail()["rpcError"];
            if refreshAllowed && rpcValue is JsonRpcError && rpcValue.'error.code == HEADER_MISMATCH {
                self.transport.cache().invalidate(REQUEST_LIST_TOOLS);
                return self.callModernTool(params, headers, false);
            }
            return responseValue;
        }
        WireResult wireResult = responseValue;
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
        ToolResult|error callResult = applicationResult(wireResult).cloneWithType();
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
        // A discovery result that omits resultType, ttlMs or cacheScope still comes from a modern server, so
        // they default to complete, 0 and private rather than failing the probe into a legacy fallback.
        WireResult wireResult = check self.sendModernRequest("server/discover", {}, headers, requireResultType = false);
        DiscoverResult|error discovery = applicationResult(wireResult, preserveCacheHints = true).cloneWithType();
        if discovery is error || (wireResult["resultType"] ?: "complete") != "complete" {
            return error ResponseParsingError("Invalid discovery result");
        }
        return discovery;
    }

    // Discovery runs before a version is negotiated, so it offers the newest one.
    private isolated function metaProtocolVersion() returns string {
        lock {
            string? negotiatedVersion = self.negotiatedProtocolVersion;
            return self.modernSelected && negotiatedVersion is string ? negotiatedVersion : LATEST_MODERN_PROTOCOL_VERSION;
        }
    }

    private isolated function sendModernRequest(string methodName, RequestParams requestParams,
            map<string|string[]> headers, map<string> parameterHeaders = {}, boolean requireResultType = true)
            returns WireResult|ClientError {
        JsonRpcRequest requestMessage;
        lock {
            self.requestId += 1;
            RequestParams wireParams = {...requestParams.cloneReadOnly()};
            Meta requestMeta = {...(wireParams._meta ?: {})};
            requestMeta[PROTOCOL_META_KEY] = self.metaProtocolVersion();
            requestMeta[CLIENT_INFO_META_KEY] = self.clientInfo;
            requestMeta[CAPABILITIES_META_KEY] = self.clientCapabilities;
            wireParams._meta = requestMeta;
            requestMessage = {jsonrpc: JSONRPC_VERSION, id: self.requestId, method: methodName, params: wireParams.cloneReadOnly()};
        }
        return self.transport.sendProtocolRequest(requestMessage, headers, parameterHeaders, requireResultType);
    }

    # Sends a request message to the server and returns the server's response.
    #
    # + request - The request object to send
    # + headers - Optional headers to include with the request
    # + return - LegacyServerResult, a stream of results, or a ClientError.
    private isolated function sendRequestMessage(Request request, map<string|string[]> headers = {})
            returns LegacyServerResult|ClientError {
        lock {
            self.requestId += 1;

            JsonRpcRequest jsonRpcRequest = {
                ...request.cloneReadOnly(),
                jsonrpc: JSONRPC_VERSION,
                id: self.requestId
            };

            LegacyMessage|stream<LegacyMessage, StreamError?>|StreamableHttpTransportError? response =
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
