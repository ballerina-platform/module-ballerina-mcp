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

    private map<string> sessionMap = {};

    isolated resource function delete .(http:Headers headers) returns http:BadRequest|http:Ok {
        string? sessionId = self.getSessionIdFromHeaders(headers);
        if sessionId is () {
            return <http:BadRequest>{
                body: self.createJsonRpcError(INVALID_REQUEST, "Missing session ID header")
            };
        }

        lock {
            if !self.sessionMap.hasKey(sessionId) {
                return <http:BadRequest>{
                    body: self.createJsonRpcError(INVALID_REQUEST, string `Invalid session ID: ${sessionId}`)
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
        http:NotAcceptable|http:UnsupportedMediaType? headerValidationError = self.validateHeaders(headers);
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
            body: self.createJsonRpcError(INVALID_REQUEST, "Unsupported request type")
        };
    }

    private isolated function validateHeaders(http:Headers headers)
            returns http:NotAcceptable|http:UnsupportedMediaType? {
        string|http:HeaderNotFoundError acceptHeader = headers.getHeader(ACCEPT_HEADER);
        if acceptHeader is http:HeaderNotFoundError {
            return <http:NotAcceptable>{
                body: self.createJsonRpcError(NOT_ACCEPTABLE,
                    "Not Acceptable: Client must accept both application/json and text/event-stream")
            };
        }

        if !acceptHeader.includes(CONTENT_TYPE_JSON) || !acceptHeader.includes(CONTENT_TYPE_SSE) {
            return <http:NotAcceptable>{
                body: self.createJsonRpcError(NOT_ACCEPTABLE,
                    "Not Acceptable: Client must accept both application/json and text/event-stream")
            };
        }

        string|http:HeaderNotFoundError contentTypeHeader = headers.getHeader(CONTENT_TYPE_HEADER);
        if contentTypeHeader is http:HeaderNotFoundError {
            return <http:UnsupportedMediaType>{
                body: self.createJsonRpcError(UNSUPPORTED_MEDIA_TYPE,
                    "Unsupported Media Type: Content-Type must be application/json")
            };
        }

        if !contentTypeHeader.includes(CONTENT_TYPE_JSON) {
            return <http:UnsupportedMediaType>{
                body: self.createJsonRpcError(UNSUPPORTED_MEDIA_TYPE,
                    "Unsupported Media Type: Content-Type must be application/json")
            };
        }

        return;
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
                    body: self.createJsonRpcError(METHOD_NOT_FOUND, "Method not found", request.id)
                };
            }
        }
    }

    private isolated function processJsonRpcNotification(JsonRpcNotification notification) returns http:Accepted|http:BadRequest {
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

    private isolated function getSessionIdFromHeaders(http:Headers headers) returns string? {
        string|http:HeaderNotFoundError sessionHeader = headers.getHeader(SESSION_ID_HEADER);
        return sessionHeader is string ? sessionHeader : ();
    }

    private isolated function handleInitializeRequest(JsonRpcRequest jsonRpcRequest, http:Headers headers) returns http:BadRequest|http:Ok|Error {
        JsonRpcRequest {jsonrpc: _, id, ...request} = jsonRpcRequest;
        InitializeRequest|error initRequest = request.cloneWithType();
        if initRequest is error {
            return <http:BadRequest>{
                body: self.createJsonRpcError(INVALID_REQUEST,
                    string `Invalid request: ${initRequest.message()}`, id)
            };
        }

        // Check if there's a session ID in the headers
        string? existingSessionId = self.getSessionIdFromHeaders(headers);

        lock {
            // If there's an existing session ID and it's already in the map, return error
            if existingSessionId is string && self.sessionMap.hasKey(existingSessionId) {
                return <http:BadRequest>{
                    body: self.createJsonRpcError(INVALID_REQUEST,
                        string `Session already initialized: ${existingSessionId}`, id)
                };
            }

            Service|AdvancedService mcpService = check getMcpServiceFromDispatcher(self);
            ServiceConfiguration serviceConfig = getServiceConfiguration(mcpService);

            // Create new session ID
            string newSessionId = uuid:createRandomUuid();
            self.sessionMap[newSessionId] = "initialized";

            string requestedVersion = initRequest.params.protocolVersion;
            string protocolVersion = self.selectProtocolVersion(requestedVersion);

            return <http:Ok>{
                headers: {[SESSION_ID_HEADER]: newSessionId},
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: id,
                    result: <InitializeResult>{
                        protocolVersion: protocolVersion,
                        capabilities: (serviceConfig.options?.capabilities ?: {}).cloneReadOnly(),
                        serverInfo: serviceConfig.info.cloneReadOnly()
                    }
                }
            };
        }
    }

    private isolated function handleListToolsRequest(JsonRpcRequest request, http:Headers headers) returns http:BadRequest|http:Ok {
        // Validate session ID
        string? sessionId = self.getSessionIdFromHeaders(headers);
        if sessionId is () {
            return <http:BadRequest>{
                body: self.createJsonRpcError(INVALID_REQUEST,
                    "Missing session ID header", request.id)
            };
        }

        lock {
            // Check if session exists
            if !self.sessionMap.hasKey(sessionId) {
                return <http:BadRequest>{
                    body: self.createJsonRpcError(INVALID_REQUEST,
                        string `Invalid session ID: ${sessionId}`, request.id)
                };
            }
        }

        ListToolsResult|error listToolsResult = self.executeOnListTools();
        if listToolsResult is error {
            return <http:BadRequest>{
                body: self.createJsonRpcError(INTERNAL_ERROR,
                    string `Failed to list tools: ${listToolsResult.message()}`, request.id)
            };
        }

        return <http:Ok>{
            headers: {[SESSION_ID_HEADER]: sessionId},
            body: {
                jsonrpc: JSONRPC_VERSION,
                id: request.id,
                result: listToolsResult.cloneReadOnly()
            }
        };
    }

    private isolated function handleCallToolRequest(JsonRpcRequest request, http:Headers headers) returns http:BadRequest|http:Ok {
        // Validate session ID
        string? sessionId = self.getSessionIdFromHeaders(headers);
        if sessionId is () {
            return <http:BadRequest>{
                body: self.createJsonRpcError(INVALID_REQUEST,
                    "Missing session ID header", request.id)
            };
        }

        lock {
            // Check if session exists
            if !self.sessionMap.hasKey(sessionId) {
                return <http:BadRequest>{
                    body: self.createJsonRpcError(INVALID_REQUEST,
                        string `Invalid session ID: ${sessionId}`, request.id)
                };
            }
        }

        // Extract and validate parameters
        CallToolParams|error params = request.params.cloneWithType();
        if params is error {
            return <http:BadRequest>{
                body: self.createJsonRpcError(INVALID_PARAMS,
                    string `Invalid parameters: ${params.message()}`, request.id)
            };
        }

        CallToolResult|error callToolResult = self.executeOnCallTool(params);
        if callToolResult is error {
            return <http:BadRequest>{
                body: self.createJsonRpcError(INTERNAL_ERROR,
                    string `Failed to call tool '${params.name}': ${callToolResult.message()}`, request.id)
            };
        }

        return <http:Ok>{
            headers: {[SESSION_ID_HEADER]: sessionId},
            body: {
                jsonrpc: JSONRPC_VERSION,
                id: request.id,
                result: callToolResult.cloneReadOnly()
            }
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

    private isolated function createJsonRpcError(int code, string message, RequestId? id = ()) returns JsonRpcError & readonly => {
        jsonrpc: JSONRPC_VERSION,
        id: id,
        'error: {
            code: code,
            message: message
        }
    };

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

    private isolated function executeOnCallTool(CallToolParams params) returns CallToolResult|Error {
        Service|AdvancedService mcpService = check getMcpServiceFromDispatcher(self);
        if mcpService is AdvancedService {
            return invokeOnCallTool(mcpService, params.cloneReadOnly());
        }
        if mcpService is Service {
            return callToolForRemoteFunctions(mcpService, params.cloneReadOnly());
        }
        return error DispatcherError("MCP Service is not attached");
    }
};
