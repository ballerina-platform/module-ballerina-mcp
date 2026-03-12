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
import ballerina/log;

isolated service class DispatcherService {
    *http:Service;
}

isolated function getDispatcherService(http:HttpServiceConfig httpServiceConfig) returns DispatcherService {
    return @http:ServiceConfig {
        ...httpServiceConfig
    } isolated service object {
        private map<Session> sessionMap = {};
        private ServiceConfiguration? cachedServiceConfig = ();
        private map<string[]> toolScopes = {};
        private ListToolsResult? listToolsRequest = ();
        private http:ListenerAuthConfig[]? authConfig = ();

        isolated resource function delete .(http:Headers headers) returns http:BadRequest|http:Ok|Error {
            lock {
                if self.authConfig is () {
                    self.authConfig = getServiceAuthConfig(self);
                }
            }
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
                returns http:BadRequest|http:NotAcceptable|http:UnsupportedMediaType|http:Accepted|http:Ok|http:Unauthorized|http:Forbidden|Error {
            http:NotAcceptable|http:UnsupportedMediaType? headerValidationError = validateRequiredHeaders(headers);
            lock {
                if self.authConfig is () {
                    self.authConfig = getServiceAuthConfig(self);
                }
            }
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
            returns http:BadRequest|http:Ok|http:Unauthorized|http:Forbidden|Error {
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
            returns http:BadRequest|http:Ok|http:Forbidden|http:Unauthorized|Error {
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

            http:Unauthorized|http:Forbidden|string? authenticateResult = self.authenticate(headers);
            if authenticateResult is http:Unauthorized || authenticateResult is http:Forbidden {
                return authenticateResult;
            }
            string userName = authenticateResult is string ? authenticateResult : "";

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

                log:printDebug("Connection initialization completed" , agentID= userName, sessionId = newSessionId);

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
            lock {
	            self.listToolsRequest = listToolsResult.cloneReadOnly();
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
            returns http:BadRequest|http:Ok|http:Unauthorized|http:Forbidden|Error {
            CallToolParams|error params = request.params.cloneWithType();
            if params is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Invalid parameters: ${params.message()}`, request.id)
                };
            }
            string userName = "";
            http:ListenerAuthConfig[]? listenerAuthConfig = ();
            lock {
                if !self.toolScopes.hasKey(params.name) {
                    http:BadRequest? toolsResult = self.getTools(request.id);
                    if toolsResult is http:BadRequest {
                        return toolsResult.cloneReadOnly();
                    }
                }
                if self.authConfig is http:ListenerAuthConfig[] {
                    listenerAuthConfig = getListenerAuthConfig(<http:ListenerAuthConfig[]>self.authConfig, 
                                self.toolScopes.get(params.name)).cloneReadOnly();
                }
            }
            http:Unauthorized|http:Forbidden|string? authenticateResult = self.authenticate(headers, config = listenerAuthConfig);
            if authenticateResult is http:Unauthorized || authenticateResult is http:Forbidden{
                return authenticateResult;
            }
            userName = authenticateResult is string ? authenticateResult : "";
            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_CALL_TOOL);

            string? sessionId = ();

            if effectiveSessionMode == STATEFUL {
                sessionId = getSessionIdFromHeaders(headers);
                if sessionId is () {
                    log:printDebug("Tool execution failed" , agentID= userName, sessionId = sessionId, toolName = params.name);
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST,
                                "Missing session ID header", request.id)
                    };
                }

                lock {
                    if !self.sessionMap.hasKey(sessionId) {
                        log:printDebug("Tool execution failed" , agentID= userName, sessionId = sessionId, toolName = params.name);
                        return <http:BadRequest>{
                            body: createJsonRpcError(INVALID_REQUEST,
                                    string `Invalid session ID: ${sessionId}`, request.id)
                        };
                    }
                }
            }

            Session? session;
            lock {
                session = sessionId is string ? self.sessionMap[sessionId] : ();
            }

            CallToolResult|error callToolResult = self.executeOnCallTool(params, session);
            if callToolResult is error {
                log:printDebug("Tool execution failed" , agentID= userName, sessionId = sessionId, toolName = params.name);
                return <http:BadRequest>{
                    body: createJsonRpcError(INTERNAL_ERROR,
                            string `Failed to call tool '${params.name}': ${callToolResult.message()}`, request.id)
                };
            }

            JsonRpcResponse responseBody = {
                jsonrpc: JSONRPC_VERSION,
                id: request.id,
                result: callToolResult.cloneReadOnly()
            };

            log:printInfo("Tool execution succeeded" , agentID = userName, sessionId = sessionId, toolName = params.name);

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

        private isolated function getTools(RequestId requestId) returns http:BadRequest? {
            ToolDefinition[] tools = [];
            lock {
                ListToolsResult? listToolsRequestResult = self.listToolsRequest;
                if listToolsRequestResult is ListToolsResult {
                    tools = listToolsRequestResult.tools.cloneReadOnly();
                } else {
                    ListToolsResult|error listToolsResult = self.executeOnListTools();
                    if listToolsResult is error {
                        return <http:BadRequest>{
                            body: createJsonRpcError(INTERNAL_ERROR,
                                    string `Failed to list tools: ${listToolsResult.message()}`, requestId)
                        };
                    }
                    tools = listToolsResult.tools.cloneReadOnly();
                }
                foreach ToolDefinition tool in tools.cloneReadOnly() {
                    string|string[]? scopes = tool.scopes;
                    string[] scopesArray = [];
                    if scopes is string {
                        scopesArray = re ` `.split(scopes.trim());
                    } else if (scopes is string[]) {
                        scopesArray = scopes;
                    }
                    self.toolScopes[tool.name] = scopesArray;
                }
            }
            return; 
        }

        private isolated function authenticate(http:Headers headers, http:ListenerAuthConfig[]? config = ()) 
                returns http:Unauthorized|http:Forbidden|string? {
            http:ListenerAuthConfig[]? authConfig = ();
            lock {
                authConfig = config.cloneReadOnly();
                if authConfig is () && self.authConfig is () {
                    return;
                }
                if authConfig is () {
                    authConfig = self.authConfig;
                }
            }
            string|http:HeaderNotFoundError header = headers.getHeader(AUTHORIZATION);
            if header is http:HeaderNotFoundError {
                return <http:Unauthorized>{body :"Missing Authorization header"};
            }
            return authenticateResource(<http:ListenerAuthConfig[]>authConfig, header);
        }
    };
}
