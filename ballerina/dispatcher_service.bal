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

import ballerina/crypto;
import ballerina/http;
import ballerina/jwt;
import ballerina/log;
import ballerina/uuid;

isolated service class DispatcherService {
    *http:Service;
}

isolated function getDispatcherService(http:HttpServiceConfig httpServiceConfig,
                                       JwtConfig|IntrospectionConfig? authConfig) returns DispatcherService {
    final (JwtConfig|IntrospectionConfig?) & readonly readonlyAuth =
        authConfig is JwtConfig|IntrospectionConfig
        ? authConfig.cloneReadOnly()
        : ();
    return @http:ServiceConfig {
        ...httpServiceConfig
    } isolated service object {
        private map<Session> sessionMap = {};
        private ServiceConfiguration? cachedServiceConfig = ();
        private map<string[]> toolScopes = {};

        isolated resource function delete .(http:Headers headers) returns http:BadRequest|http:Ok|Error {
            http:authenticateResource(self, "delete", []);
            ServiceConfiguration config = check self.getCachedServiceConfiguration();
            SessionMode sessionMode = config.sessionMode;

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
                if !self.sessionMap.hasKey(sessionId) {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST, string `Invalid session ID: ${sessionId}`)
                    };
                }

                _ = self.sessionMap.remove(sessionId);
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

        isolated resource function post .(@http:Payload JsonRpcMessage request, http:Headers headers)
                returns http:BadRequest|http:NotAcceptable|http:UnsupportedMediaType|http:Accepted|http:Ok|Error {
            http:authenticateResource(self, "post", []);
            http:NotAcceptable|http:UnsupportedMediaType? headerValidationError = validateRequiredHeaders(headers);
            if headerValidationError !is () {
                return headerValidationError;
            }

            if request is JsonRpcRequest {
                return self.processJsonRpcRequest(request, headers);
            }

            if request is JsonRpcNotification {
                return self.processJsonRpcNotification(request);
            }

            return <http:BadRequest>{
                body: createJsonRpcError(INVALID_REQUEST, "Unsupported request type")
            };
        }

        private isolated function getCachedServiceConfiguration() returns ServiceConfiguration|Error {
            lock {
                if self.cachedServiceConfig is () {
                    Service|AdvancedService mcpService = check getMcpServiceFromDispatcher(self);
                    self.cachedServiceConfig = getServiceConfiguration(mcpService);
                }
                return <ServiceConfiguration>self.cachedServiceConfig.clone();
            }
        }

        private isolated function processJsonRpcRequest(JsonRpcRequest request, http:Headers headers)
            returns http:BadRequest|http:Ok|Error {
            match request.method {
                REQUEST_INITIALIZE => {
                    return self.handleInitializeRequest(request, headers);
                }
                REQUEST_LIST_TOOLS => {
                    return self.handleListToolsRequest(request, headers);
                }
                REQUEST_CALL_TOOL => {
                    return self.handleCallToolRequest(request, headers);
                }
                _ => {
                    return <http:BadRequest>{
                        body: createJsonRpcError(METHOD_NOT_FOUND, "Method not found", request.id)
                    };
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

        private isolated function handleInitializeRequest(JsonRpcRequest jsonRpcRequest, http:Headers headers)
            returns http:BadRequest|http:Ok|Error {
            JsonRpcRequest {jsonrpc: _, id, ...request} = jsonRpcRequest;
            InitializeRequest|error initRequest = request.cloneWithType();
            if initRequest is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_REQUEST,
                            string `Invalid request: ${initRequest.message()}`, id)
                };
            }

            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_INITIALIZE);

            string requestedVersion = initRequest.params.protocolVersion;
            string protocolVersion = self.selectProtocolVersion(requestedVersion);

            InitializeResult initResult = {
                protocolVersion: protocolVersion,
                capabilities: (serviceConfig.options?.capabilities ?: {
                    tools: {}
                }).cloneReadOnly(),
                serverInfo: serviceConfig.info.cloneReadOnly()
            };

            if effectiveSessionMode == STATELESS {
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
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST,
                                string `Session already initialized: ${existingSessionId}`, id)
                    };
                }

                string newSessionId = uuid:createRandomUuid();
                Session session = new (newSessionId);
                self.sessionMap[newSessionId] = session;

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

        private isolated function handleListToolsRequest(JsonRpcRequest request, http:Headers headers)
            returns http:BadRequest|http:Ok|Error {
            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_LIST_TOOLS);

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
                    if !self.sessionMap.hasKey(sessionId) {
                        return <http:BadRequest>{
                            body: createJsonRpcError(INVALID_REQUEST,
                                    string `Invalid session ID: ${sessionId}`, request.id)
                        };
                    }
                }
            }

            ListToolsResult|error listToolsResult = self.executeOnListTools();
            if listToolsResult is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INTERNAL_ERROR,
                            string `Failed to list tools: ${listToolsResult.message()}`, request.id)
                };
            }

            
            JsonRpcResponse responseBody = {
                jsonrpc: JSONRPC_VERSION,
                id: request.id,
                result: listToolsResult.cloneReadOnly()
            };

            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: responseBody
            };
        }

        private isolated function handleCallToolRequest(JsonRpcRequest request, http:Headers headers)
            returns http:BadRequest|http:Ok|Error {
            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_CALL_TOOL);

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
                    if !self.sessionMap.hasKey(sessionId) {
                        return <http:BadRequest>{
                            body: createJsonRpcError(INVALID_REQUEST,
                                    string `Invalid session ID: ${sessionId}`, request.id)
                        };
                    }
                }
            }

            CallToolParams|error params = request.params.cloneWithType();
            if params is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Invalid parameters: ${params.message()}`, request.id)
                };
            }

            Session? session;
            map<string[]> tool = {};
            lock {
                session = sessionId is string ? self.sessionMap[sessionId] : ();
                tool = self.toolScopes.cloneReadOnly();
            }
            CallToolResult callToolResult = {content: [], isError: false};
            TokenValidationError? validateResult = validateTool(tool, readonlyAuth, headers, params.name);
            if validateResult is TokenValidationError {
                callToolResult = {
                    content: [
                        {
                            'type: "text",
                            text: validateResult.message()
                        }
                    ],
                    isError: true
                };
            } else {
                CallToolResult|error executionResult = self.executeOnCallTool(params, session);
                if executionResult is error {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INTERNAL_ERROR,
                                string `Failed to call tool '${params.name}': ${executionResult.message()}`, request.id)
                    };
                }
                callToolResult = executionResult;
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

        private isolated function selectProtocolVersion(string requestedVersion) returns string {
            foreach string supportedVersion in SUPPORTED_PROTOCOL_VERSIONS {
                if supportedVersion == requestedVersion {
                    return requestedVersion;
                }
            }
            return LATEST_PROTOCOL_VERSION;
        }

        private isolated function executeOnListTools() returns ListToolsResult|Error {
            Service|AdvancedService mcpService = check getMcpServiceFromDispatcher(self);
            if mcpService is AdvancedService {
                return invokeOnListTools(mcpService);
            }
            if mcpService is Service {
                map<string[]> scopes = check getToolScopes(mcpService);
                lock {
	                self.toolScopes = scopes.cloneReadOnly();
                }
                return listToolsForRemoteFunctions(mcpService);
            }
            return error DispatcherError("MCP Service is not attached");
        }

        private isolated function executeOnCallTool(CallToolParams params, Session? session)
                returns CallToolResult|Error {
            Service|AdvancedService mcpService = check getMcpServiceFromDispatcher(self);
            if mcpService is AdvancedService {
                return invokeOnCallTool(mcpService, params.cloneReadOnly(), session);
            }
            if mcpService is Service {
                CallToolResult|error result = callToolForRemoteFunctions(mcpService, params.cloneReadOnly(), session);
                if result is error {
                    return error DispatcherError(result.message());
                }
                return result;
            }
            return error DispatcherError("MCP Service is not attached");
        }
    };
}

isolated function validateTool(map<string[]> toolScopes, JwtConfig|IntrospectionConfig? auth,
        http:Headers headers, string toolName) returns TokenValidationError? {
    if auth !is () {
        string|http:HeaderNotFoundError header = headers.getHeader(AUTORIZATION);
        if header is http:HeaderNotFoundError {
            return error TokenValidationError("Missing Authorization header");
        }
        if (toolScopes.hasKey(toolName)) {
            string[] scopes = toolScopes.get(toolName);
            if (scopes.length() > 0) {
                ValidationResponse validateTokenResult = check validateToken(auth, header); 
                if validateTokenResult is ValidationResponse {
                    boolean? active = validateTokenResult.active;
                    if (active is boolean && active) || active is () {
                        InsufficientScopeError? validateToolResult = validateToolScope(scopes, validateTokenResult.scope, toolName);
                        if validateToolResult is InsufficientScopeError {
                            return error TokenValidationError("Tool scope validation failed: " + validateToolResult.message());
                        }
                    } else {
                        return error TokenValidationError("Token is not active. Active state: " + active.toString());
                    }
                }
            }
        }
        
    }
    return;
}

isolated function validateToolScope(string[] requiredScopes, string? scopes, string toolName) returns InsufficientScopeError? {
    foreach string scope in requiredScopes {
        if requiredScopes.indexOf(scope) is () {
            log:printDebug("Requested OAuth scope is not permitted or does not match " +
                    "the existing token scopes: " + scope);
            return error InsufficientScopeError("Requested OAuth scope is not permitted or " +
                "does not match the existing token scopes: " + scope);
        }
    }
}

isolated function validateToken(JwtConfig|IntrospectionConfig authConfig, string accessToken)
                returns TokenValidationError|ValidationResponse {
    if authConfig is IntrospectionConfig {
        ValidationResponse|error usingIntrosepctionResult = usingIntrosepction(authConfig, accessToken);
        if usingIntrosepctionResult is ValidationResponse {
            return usingIntrosepctionResult;
        }
        return error TokenValidationError("Failed to validate token using introspection: " +
                    usingIntrosepctionResult.message());
    }
    record {string url;}? jwks = authConfig?.jwksConfig;
    if (jwks is record {string url;}) {
        ValidationResponse|error usingJwksResult = usingJwks(accessToken, jwks.url);
        if usingJwksResult is ValidationResponse {
            return usingJwksResult;
        }
        return error TokenValidationError("Failed to validate token using JWKS: " + usingJwksResult.message());
    } else {
        string|crypto:PublicKey? certFile = authConfig?.certFile;
        if (certFile is string|crypto:PublicKey) {
            ValidationResponse|error usingCertificateResult = usingCertificate(accessToken, certFile);
            if usingCertificateResult is ValidationResponse {
                return usingCertificateResult;
            }
            return error TokenValidationError("Failed to validate token using certificate: " + usingCertificateResult.message());
        }
    }
    return error TokenValidationError("No valid token validation configuration found");
}

isolated function usingJwks(string token, string url) returns ValidationResponse|error {
    jwt:ValidatorConfig validatorConfig = {
        signatureConfig: {
            jwksConfig: {
                url: url
            }
        }
    };
    jwt:Payload result = check jwt:validate(token, validatorConfig);
    return result.cloneWithType(ValidationResponse);
}

isolated function usingCertificate(string token, string|crypto:PublicKey certificate) returns error|ValidationResponse {
    jwt:ValidatorConfig validatorConfig = {
        signatureConfig: {
            certFile: certificate
        }
    };
    jwt:Payload result = check jwt:validate(token, validatorConfig);
    return result.cloneWithType(ValidationResponse);
}

isolated function usingIntrosepction(IntrospectionConfig authConfig, string accessToken)
                returns ValidationResponse|error {
    string textPayload = TOKEN_PREFIX + accessToken;
    textPayload += TOKEN_TYPE_HINT + authConfig.tokenTypeHint;
    http:Client httpclient = check new (authConfig.url,
        auth = {username: authConfig.clientConfig.clientId, password: authConfig.clientConfig.clientSecret}
    );
    http:Request req = new;
    req.setHeader(CONTENT_TYPE_HEADER, CONTENT_TYPE_FORM_URL_ENCODED);
    req.setPayload(textPayload);
    return httpclient->post("", req);
}

# Represents the validation response.
#
# + scope - A JSON string containing a space-separated list of scopes associated with this token
# + client_id - Client identifier for the OAuth 2.0 client, which requested this token
# + exp - Expiry time (seconds since the Epoch)
# + active - Indicates whether the token is currently active.
type ValidationResponse record {
    string scope?;
    string client_id;
    int exp;
    boolean active?;
};
