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

isolated function getDispatcherService(http:HttpServiceConfig httpServiceConfig) returns DispatcherService {
    return @http:ServiceConfig {
        ...httpServiceConfig
    } isolated service object {
        private map<Session> sessionMap = {};
        private StreamableHttpServiceConfiguration? cachedServiceConfig = ();

        isolated resource function delete .(http:Headers headers)
                returns http:BadRequest|http:NotFound|http:Ok|Error {
            http:authenticateResource(self, "delete", []);
            http:BadRequest? protocolVersionError =
                    validateProtocolVersionHeader(getProtocolVersionFromHeaders(headers));
            if protocolVersionError !is () {
                return protocolVersionError;
            }
            StreamableHttpServiceConfiguration config = check self.getCachedServiceConfiguration();
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
                    return createSessionNotFoundResponse(sessionId);
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

        isolated resource function post .(http:Request httpRequest, http:Headers headers)
                returns http:BadRequest|http:NotAcceptable|http:UnsupportedMediaType|http:NotFound|
                        http:Accepted|http:Ok|Error {
            http:authenticateResource(self, "post", []);
            http:NotAcceptable|http:UnsupportedMediaType? headerValidationError = validateRequiredHeaders(headers);
            if headerValidationError !is () {
                return headerValidationError;
            }

            JsonRpcMessage|http:BadRequest request = parseJsonRpcMessage(httpRequest);
            if request is http:BadRequest {
                return request;
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
                return self.processJsonRpcRequest(request, httpRequest, headers);
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
                    Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService mcpService =
                            check getMcpServiceFromDispatcher(self);
                    self.cachedServiceConfig = getServiceConfiguration(mcpService);
                }
                return <StreamableHttpServiceConfiguration>self.cachedServiceConfig.clone();
            }
        }

        private isolated function processJsonRpcRequest(JsonRpcRequest request, http:Request httpRequest,
                http:Headers headers)
            returns http:BadRequest|http:NotFound|http:Ok|Error {
            match request.method {
                REQUEST_INITIALIZE => {
                    return self.handleInitializeRequest(request, headers);
                }
                REQUEST_LIST_TOOLS => {
                    return self.handleListToolsRequest(request, httpRequest, headers);
                }
                REQUEST_CALL_TOOL => {
                    return self.handleCallToolRequest(request, httpRequest, headers);
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

        private isolated function handleInitializeRequest(JsonRpcRequest jsonRpcRequest, http:Headers headers)
            returns http:Ok|Error {
            JsonRpcRequest {jsonrpc: _, id, ...request} = jsonRpcRequest;
            InitializeRequest|error initRequest = request.cloneWithType();
            if initRequest is error {
                return createJsonRpcErrorResponse(INVALID_REQUEST,
                        string `Invalid request: ${initRequest.message()}`, id);
            }

            StreamableHttpServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_INITIALIZE);

            string requestedVersion = initRequest.params.protocolVersion;
            string protocolVersion = selectProtocolVersion(requestedVersion);

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
                    return createJsonRpcErrorResponse(INVALID_REQUEST,
                            string `Session already initialized: ${existingSessionId}`, id);
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

        private isolated function handleListToolsRequest(JsonRpcRequest request, http:Request httpRequest,
                http:Headers headers)
            returns http:BadRequest|http:NotFound|http:Ok|Error {
            StreamableHttpServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
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
                        return createSessionNotFoundResponse(sessionId, request.id);
                    }
                }
            }

            ListToolsResult|error listToolsResult = self.executeOnListTools(headers, httpRequest,
                    serviceConfig.httpConfig.treatNilableAsOptional);
            if listToolsResult is error {
                // Parameter binding failures are caller errors, reported as invalid params
                int errorCode = listToolsResult is ParameterBindingError ? INVALID_PARAMS : INTERNAL_ERROR;
                return createJsonRpcErrorResponse(errorCode,
                        string `Failed to list tools: ${listToolsResult.message()}`, request.id);
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

        private isolated function handleCallToolRequest(JsonRpcRequest request, http:Request httpRequest,
                http:Headers headers)
            returns http:BadRequest|http:NotFound|http:Ok|Error {
            StreamableHttpServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
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
                        return createSessionNotFoundResponse(sessionId, request.id);
                    }
                }
            }

            CallToolParams|error params = request.params.cloneWithType();
            if params is error {
                return createJsonRpcErrorResponse(INVALID_PARAMS,
                        string `Invalid parameters: ${params.message()}`, request.id);
            }

            // Task-augmented tool calls are not yet supported.
            if params.task !is () {
                return createJsonRpcErrorResponse(INVALID_REQUEST,
                        "Task-augmented tool calls are not supported", request.id);
            }

            Session? session;
            lock {
                session = sessionId is string ? self.sessionMap[sessionId] : ();
            }

            CallToolResult|error callToolResult = self.executeOnCallTool(params, session, headers, httpRequest,
                    serviceConfig.httpConfig.treatNilableAsOptional);
            if callToolResult is error {
                // Parameter binding failures are caller errors, reported as invalid params
                int errorCode = callToolResult is ParameterBindingError ? INVALID_PARAMS : INTERNAL_ERROR;
                return createJsonRpcErrorResponse(errorCode,
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

        private isolated function executeOnListTools(http:Headers headers, http:Request httpRequest,
                boolean treatNilableAsOptional) returns ListToolsResult|Error {
            Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService mcpService =
                    check getMcpServiceFromDispatcher(self);
            if mcpService is StreamableHttpAdvancedService {
                return invokeAdvancedOnListTools(mcpService, headers, httpRequest, extractHeaderValues(headers),
                        treatNilableAsOptional);
            }
            if mcpService is AdvancedService {
                return invokeOnListTools(mcpService);
            }
            if mcpService is Service|StreamableHttpService {
                return listToolsForRemoteFunctions(mcpService);
            }
            return error DispatcherError("MCP service is not available");
        }

        private isolated function executeOnCallTool(CallToolParams params, Session? session, http:Headers headers,
                http:Request httpRequest, boolean treatNilableAsOptional) returns CallToolResult|Error {
            Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService mcpService =
                    check getMcpServiceFromDispatcher(self);
            if mcpService is StreamableHttpAdvancedService {
                return invokeAdvancedOnCallTool(mcpService, params.cloneReadOnly(), session, headers, httpRequest,
                        extractHeaderValues(headers), treatNilableAsOptional);
            }
            if mcpService is AdvancedService {
                return invokeOnCallTool(mcpService, params.cloneReadOnly(), session);
            }
            if mcpService is Service|StreamableHttpService {
                CallToolResult|error result = callToolForRemoteFunctions(mcpService, params.cloneReadOnly(), session,
                        headers, httpRequest, extractHeaderValues(headers), treatNilableAsOptional);
                if result is ParameterBindingError {
                    return result;
                }
                if result is error {
                    return error DispatcherError(result.message());
                }
                return result;
            }
            return error DispatcherError("MCP service is not available");
        }
    };
}
