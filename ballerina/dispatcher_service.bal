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

import ballerina/http;
import ballerina/uuid;

isolated service class DispatcherService {
    *http:Service;
}

isolated function getDispatcherService(http:HttpServiceConfig httpServiceConfig,
        ServerAuthenticator? serviceAuthenticator, SubscriptionRegistry subscriptionRegistry,
        RequestStateSigner serviceRequestStateSigner) returns DispatcherService {
    return @http:ServiceConfig {
        ...httpServiceConfig
    } isolated service object {
        private map<HttpSession> sessionMap = {};
        // Principal that created each session, when the service uses an `mcp:OAuthProtectedResourceConfig`.
        private map<string> sessionOwners = {};
        private final ServerAuthenticator? authenticator = serviceAuthenticator;
        private final SubscriptionRegistry subscriptions = subscriptionRegistry;
        private final RequestStateSigner requestStateSigner = serviceRequestStateSigner;
        private StreamableHttpServiceConfiguration? cachedServiceConfig = ();

        isolated resource function delete .(http:Headers headers)
                returns http:BadRequest|http:NotFound|http:InternalServerError|http:Ok|http:MethodNotAllowed|
                        http:Unauthorized|http:Forbidden|http:ServiceUnavailable {
            StreamableHttpServiceConfiguration|Error config = self.getCachedServiceConfiguration();
            if config is Error {
                return <http:InternalServerError>{
                    body: createJsonRpcError(INTERNAL_ERROR, config.message())
                };
            }
            http:Forbidden? originError = validateOrigin(headers, config);
            if originError is http:Forbidden {
                return originError;
            }
            readonly & AuthContext? authContext = ();
            ServerAuthenticator? authenticator = self.authenticator;
            if authenticator is ServerAuthenticator {
                readonly & AuthContext|AuthenticationFailure authenticated =
                        authenticator.authenticate(headers);
                if authenticated is AuthenticationFailure {
                    return authenticated;
                }
                authContext = authenticated;
            } else {
                http:authenticateResource(self, "delete", []);
            }
            string? protocolVersion = getProtocolVersionFromHeaders(headers);
            // Modern requests have no sessions to delete, so the legacy header check does not apply to them.
            if config.protocolMode == "modern" || isModernProtocolVersion(protocolVersion) {
                return http:METHOD_NOT_ALLOWED;
            }
            http:BadRequest? protocolVersionError = validateProtocolVersionHeader(protocolVersion);
            if protocolVersionError !is () {
                return protocolVersionError;
            }
            HttpSessionMode sessionMode = config.sessionMode;

            if sessionMode == STATELESS {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_REQUEST, "Session deletion not supported in stateless mode")
                };
            }

            string? sessionId = getSessionIdFromHeaders(headers);
            if sessionId is () {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_REQUEST, "Missing session ID header")
                };
            }

            lock {
                if !self.sessionMap.hasKey(sessionId) || !isSessionOwner(self.sessionOwners[sessionId], authContext) {
                    return createSessionNotFoundResponse(sessionId);
                }

                _ = self.sessionMap.remove(sessionId);
                _ = self.sessionOwners.removeIfHasKey(sessionId);
            }

            return <http:Ok>{
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    result: {
                        message: string `Session ${sessionId} deleted successfully`
                    }
                }
            };
        }

        isolated resource function post .(http:Request httpRequest, http:Headers headers)
                returns http:BadRequest|http:NotAcceptable|http:UnsupportedMediaType|http:NotFound|
                        http:Accepted|http:Ok|http:Unauthorized|http:Forbidden|http:Response|http:ServiceUnavailable|
                        http:InternalServerError {
            StreamableHttpServiceConfiguration|Error routeConfig = self.getCachedServiceConfiguration();
            if routeConfig is Error {
                return createJsonRpcErrorResponse(INTERNAL_ERROR, routeConfig.message());
            }
            // Origin is checked first, so a cross-origin request gets 403 with or without a token.
            http:Forbidden? originError = validateOrigin(headers, routeConfig);
            if originError is http:Forbidden {
                return originError;
            }
            // Authentication runs before any other validation, so an unauthenticated caller learns
            // nothing about the service beyond where to obtain a token.
            readonly & AuthContext? authContext = ();
            ServerAuthenticator? authenticator = self.authenticator;
            if authenticator is ServerAuthenticator {
                readonly & AuthContext|AuthenticationFailure authenticated =
                        authenticator.authenticate(headers);
                if authenticated is AuthenticationFailure {
                    return authenticated;
                }
                authContext = authenticated;
            } else {
                http:authenticateResource(self, "post", []);
            }
            http:NotAcceptable|http:UnsupportedMediaType? headerValidationError = validateRequiredHeaders(headers);
            if headerValidationError !is () {
                return headerValidationError;
            }

            JsonRpcMessage|http:BadRequest request = parseJsonRpcMessage(httpRequest);
            if request is http:BadRequest {
                return request;
            }

            if request is JsonRpcNotification && isModernRequest(request, headers) {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_REQUEST,
                            "No core client notifications are supported by modern Streamable HTTP")
                };
            }
            if request is JsonRpcRequest && isModernRequest(request, headers) {
                var mcpService = getMcpServiceFromDispatcher(self);
                if mcpService is Error {
                    return createJsonRpcErrorResponse(INTERNAL_ERROR, mcpService.message(), request.id);
                }
                var modernResponse = trap handleModernRequest(mcpService, request, httpRequest, headers, routeConfig,
                        self.subscriptions, self.requestStateSigner, self.authenticator, authContext);
                if modernResponse is error {
                    return createJsonRpcErrorResponse(INTERNAL_ERROR, "Failed to process MCP request", request.id);
                }
                return modernResponse;
            }
            if routeConfig.protocolMode == "modern" {
                return unsupportedProtocolResponse(getProtocolVersionFromHeaders(headers) ?: "legacy",
                        MODERN_PROTOCOL_VERSIONS, request is JsonRpcRequest ? request.id : ());
            }

            // The MCP-Protocol-Version header is required on all requests after initialization. The
            // initialize request itself establishes the version, so it is exempt from this validation.
            boolean isInitializeRequest = request is JsonRpcRequest && request.method == REQUEST_INITIALIZE;
            if !isInitializeRequest {
                http:BadRequest? protocolVersionError =
                        validateProtocolVersionHeader(getProtocolVersionFromHeaders(headers));
                if protocolVersionError !is () {
                    return protocolVersionError;
                }
            }

            if request is JsonRpcRequest {
                return self.processJsonRpcRequest(request, httpRequest, headers, authContext);
            }

            if request is JsonRpcNotification {
                return self.processJsonRpcNotification(request);
            }

            return <http:BadRequest>{
                body: createJsonRpcError(INVALID_REQUEST, "Unsupported request type")
            };
        }

        private isolated function getCachedServiceConfiguration() returns StreamableHttpServiceConfiguration|Error {
            lock {
                if self.cachedServiceConfig is () {
                    StreamableHttpService|StreamableHttpAdvancedService mcpService =
                            check getMcpServiceFromDispatcher(self);
                    self.cachedServiceConfig = getServiceConfiguration(mcpService);
                }
                return <StreamableHttpServiceConfiguration>self.cachedServiceConfig.clone();
            }
        }

        private isolated function processJsonRpcRequest(JsonRpcRequest request, http:Request httpRequest,
                http:Headers headers, readonly & AuthContext? authContext)
            returns http:BadRequest|http:NotFound|http:Ok|http:Forbidden|http:InternalServerError {
            match request.method {
                REQUEST_INITIALIZE => {
                    return self.handleInitializeRequest(request, headers, authContext);
                }
                REQUEST_LIST_TOOLS => {
                    return self.handleListToolsRequest(request, httpRequest, headers, authContext);
                }
                REQUEST_CALL_TOOL => {
                    return self.handleCallToolRequest(request, httpRequest, headers, authContext);
                }
                _ => {
                    return createJsonRpcErrorResponse(METHOD_NOT_FOUND, "Method not found", request.id);
                }
            }
        }

        private isolated function processJsonRpcNotification(JsonRpcNotification notification)
            returns http:Accepted|http:BadRequest {
            if notification.method == NOTIFICATION_INITIALIZED {
                return http:ACCEPTED;
            }

            return <http:BadRequest>{
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    'error: {
                        code: METHOD_NOT_FOUND,
                        message: "Unknown notification method"
                    }
                }
            };
        }

        private isolated function handleInitializeRequest(JsonRpcRequest jsonRpcRequest, http:Headers headers,
                readonly & AuthContext? authContext)
            returns http:Ok {
            JsonRpcRequest {jsonrpc: _, id, ...request} = jsonRpcRequest;
            InitializeRequest|error initRequest = request.cloneWithType();
            if initRequest is error {
                // The conversion failure names the internal record types it walked, which describe
                // nothing the caller sent, so the request is reported without them.
                return createJsonRpcErrorResponse(INVALID_PARAMS,
                        string `Invalid parameters for '${REQUEST_INITIALIZE}'`, id);
            }

            StreamableHttpServiceConfiguration|Error serviceConfig = self.getCachedServiceConfiguration();
            if serviceConfig is Error {
                return createJsonRpcErrorResponse(INTERNAL_ERROR, serviceConfig.message(), id);
            }
            HttpSessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_INITIALIZE);

            string requestedVersion = initRequest.params.protocolVersion;
            string protocolVersion = selectProtocolVersion(requestedVersion);

            InitializeResult initResult = {
                protocolVersion: protocolVersion,
                capabilities: (serviceConfig.options?.capabilities ?: {
                    tools: {}
                }).cloneReadOnly(),
                serverInfo: serviceConfig.info.cloneReadOnly()
            };

            // A session must belong to the principal that creates it. A token naming neither a subject
            // nor a client cannot own one, so it gets a sessionless connection, or none if sessions are required.
            string? sessionOwner = authContext is AuthContext ? principalOf(authContext) : ();
            boolean unownable = authContext is AuthContext && sessionOwner is ();
            boolean requiresSession = false;
            if unownable {
                StreamableHttpService|StreamableHttpAdvancedService|Error mcpService =
                        getMcpServiceFromDispatcher(self);
                if mcpService is Error {
                    return createJsonRpcErrorResponse(INTERNAL_ERROR, mcpService.message(), id);
                }
                requiresSession = requiresLegacySession(mcpService);
            }
            if unownable && (serviceConfig.sessionMode == STATEFUL || requiresSession) {
                return createJsonRpcErrorResponse(INVALID_REQUEST, "A session cannot be bound to this access " +
                        "token: it names neither a subject nor a client", id);
            }

            if effectiveSessionMode == STATELESS || unownable {
                return <http:Ok>{
                    body: {
                        jsonrpc: JSONRPC_VERSION,
                        id: id,
                        result: initResult
                    }
                };
            }

            string? existingSessionId = getSessionIdFromHeaders(headers);

            lock {
                // If there's an existing session ID and it's already in the map, return error
                if existingSessionId is string && self.sessionMap.hasKey(existingSessionId) {
                    return createJsonRpcErrorResponse(INVALID_REQUEST,
                            string `Session already initialized: ${existingSessionId}`, id);
                }

                string newSessionId = uuid:createRandomUuid();
                HttpSession session = new (newSessionId);
                self.sessionMap[newSessionId] = session;
                if sessionOwner is string {
                    // A session belongs to the principal that created it; others cannot use it.
                    self.sessionOwners[newSessionId] = sessionOwner;
                }

                return <http:Ok>{
                    headers: {[SESSION_ID_HEADER]: newSessionId},
                    body: {
                        jsonrpc: JSONRPC_VERSION,
                        id: id,
                        result: initResult.clone()
                    }
                };
            }
        }

        private isolated function handleListToolsRequest(JsonRpcRequest request, http:Request httpRequest,
                http:Headers headers, readonly & AuthContext? authContext)
            returns http:BadRequest|http:NotFound|http:Ok|http:Forbidden|http:InternalServerError {
            StreamableHttpServiceConfiguration|Error serviceConfig = self.getCachedServiceConfiguration();
            if serviceConfig is Error {
                return createJsonRpcErrorResponse(INTERNAL_ERROR, serviceConfig.message(), request.id);
            }
            HttpSessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_LIST_TOOLS);

            string? sessionId = ();

            if effectiveSessionMode == STATEFUL {
                sessionId = getSessionIdFromHeaders(headers);
                if sessionId is () {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST,
                                "Missing session ID header", request.id)
                    };
                }

                lock {
                    if !self.sessionMap.hasKey(sessionId) ||
                            !isSessionOwner(self.sessionOwners[sessionId], authContext) {
                        return createSessionNotFoundResponse(sessionId, request.id);
                    }
                }
            }

            Cursor?|http:Ok cursor = requestCursor(request);
            if cursor is http:Ok {
                return cursor;
            }
            ListToolsResult|error listToolsResult = self.executeOnListTools(cursor, headers, httpRequest,
                    serviceConfig.httpConfig.treatNilableAsOptional, authContext);
            if listToolsResult is InsufficientScopeError {
                return insufficientScopeFor(self.authenticator, listToolsResult);
            }
            if listToolsResult is InvalidParamsError {
                return createJsonRpcErrorResponse(INVALID_PARAMS, listToolsResult.message(), request.id);
            }
            if listToolsResult is error {
                return createJsonRpcErrorResponse(INTERNAL_ERROR,
                        string `Failed to list tools: ${listToolsResult.message()}`, request.id);
            }

            // Cache hints are not part of the legacy protocol.
            ListToolsResult legacyResult = {...listToolsResult};
            foreach string fieldName in ["resultType", "ttlMs", "cacheScope"] {
                _ = legacyResult.removeIfHasKey(fieldName);
            }
            JsonRpcResponse responseBody = {
                jsonrpc: JSONRPC_VERSION,
                id: request.id,
                result: legacyResult.cloneReadOnly()
            };

            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: responseBody
            };
        }

        private isolated function handleCallToolRequest(JsonRpcRequest request, http:Request httpRequest,
                http:Headers headers, readonly & AuthContext? authContext)
            returns http:BadRequest|http:NotFound|http:Ok|http:Forbidden|http:InternalServerError {
            StreamableHttpServiceConfiguration|Error serviceConfig = self.getCachedServiceConfiguration();
            if serviceConfig is Error {
                return createJsonRpcErrorResponse(INTERNAL_ERROR, serviceConfig.message(), request.id);
            }
            HttpSessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_CALL_TOOL);

            string? sessionId = ();

            if effectiveSessionMode == STATEFUL {
                sessionId = getSessionIdFromHeaders(headers);
                if sessionId is () {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST,
                                "Missing session ID header", request.id)
                    };
                }

                lock {
                    if !self.sessionMap.hasKey(sessionId) ||
                            !isSessionOwner(self.sessionOwners[sessionId], authContext) {
                        return createSessionNotFoundResponse(sessionId, request.id);
                    }
                }
            }

            CallToolParams|error params = request.params.cloneWithType();
            if params is error {
                return createJsonRpcErrorResponse(INVALID_PARAMS,
                        string `Invalid parameters for '${REQUEST_CALL_TOOL}'`, request.id);
            }

            ServerAuthenticator? authenticator = self.authenticator;
            if authenticator is ServerAuthenticator && authContext is AuthContext {
                http:Forbidden? denied = authenticator.authorizeTool(authContext, params.name);
                if denied is http:Forbidden {
                    return denied;
                }
            }

            HttpSession? session;
            lock {
                session = sessionId is string ? self.sessionMap[sessionId] : ();
            }

            CallToolResult|error callToolResult = self.executeOnCallTool(params, session, headers, httpRequest,
                    serviceConfig.httpConfig.treatNilableAsOptional, authContext);
            if callToolResult is InsufficientScopeError {
                return insufficientScopeFor(self.authenticator, callToolResult);
            }
            if callToolResult is InvalidParamsError {
                return createJsonRpcErrorResponse(INVALID_PARAMS, callToolResult.message(), request.id);
            }
            if callToolResult is error {
                return createJsonRpcErrorResponse(INTERNAL_ERROR,
                        string `Failed to call tool '${params.name}': ${callToolResult.message()}`, request.id);
            }

            JsonRpcResponse responseBody = {
                jsonrpc: JSONRPC_VERSION,
                id: request.id,
                result: callToolResult.cloneReadOnly()
            };

            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: responseBody
            };
        }

        private isolated function executeOnListTools(Cursor? cursor, http:Headers headers, http:Request httpRequest,
                boolean treatNilableAsOptional, readonly & AuthContext? authContext) returns ListToolsResult|Error {
            StreamableHttpService|StreamableHttpAdvancedService mcpService =
                    check getMcpServiceFromDispatcher(self);
            if mcpService is StreamableHttpAdvancedService {
                ListToolsResult|error advancedResult =
                        trap invokeAdvancedOnListTools(mcpService, cursor, headers, httpRequest,
                            extractHeaderValues(headers), treatNilableAsOptional, authContext);
                if advancedResult is error {
                    return trapListToolsFailure(advancedResult);
                }
                ListToolsResult|error legacyResult = legacyToolListResult(advancedResult);
                return legacyResult is error ? error ServerError(legacyResult.message()) : legacyResult;
            }
            if mcpService is StreamableHttpService {
                return trapListToolsFailure(trap listToolsForRemoteFunctions(mcpService));
            }
            return error DispatcherError("MCP service is not available");
        }

        private isolated function executeOnCallTool(CallToolParams params, HttpSession? session, http:Headers headers,
                http:Request httpRequest, boolean treatNilableAsOptional, readonly & AuthContext? authContext)
                returns CallToolResult|Error {
            StreamableHttpService|StreamableHttpAdvancedService mcpService =
                    check getMcpServiceFromDispatcher(self);
            if mcpService is StreamableHttpAdvancedService {
                // Legacy calls have no continuations, so state and answers here were never verified.
                CallToolParams legacyParams = params.clone();
                _ = legacyParams.removeIfHasKey("requestState");
                _ = legacyParams.removeIfHasKey("inputResponses");
                CallToolResult|InputRequiredResult|error result =
                        trap invokeAdvancedOnCallTool(mcpService, legacyParams.cloneReadOnly(), session, headers,
                            httpRequest, extractHeaderValues(headers), treatNilableAsOptional, authContext);
                if result is InputRequiredResult {
                    return error ServerError(INPUT_REQUIRED_ON_LEGACY);
                }
                if result is InsufficientScopeError {
                    return result;
                }
                if result is error {
                    return toServerError(result, params.name);
                }
                CallToolResult|error completedResult = result.cloneWithType();
                if completedResult is error {
                    return error ServerError(INPUT_REQUIRED_ON_LEGACY);
                }
                CallToolResult|error legacyResult = legacyToolCallResult(completedResult);
                return legacyResult is error ? error ServerError(legacyResult.message()) : legacyResult;
            }
            if mcpService is StreamableHttpService {
                CallToolResult|InputRequiredResult|error result = trap callToolForRemoteFunctions(mcpService,
                        params.cloneReadOnly(), session, headers, httpRequest, extractHeaderValues(headers),
                        treatNilableAsOptional, authContext, new);
                if result is ParameterBindingError || result is InsufficientScopeError {
                    return result;
                }
                if result is error {
                    return toToolExecutionError(result, params.name);
                }
                if result is InputRequiredResult {
                    return error ServerError(INPUT_REQUIRED_ON_LEGACY);
                }
                return <CallToolResult>result;
            }
            return error DispatcherError("MCP service is not available");
        }
    };
}
