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

# Represents the dispatcher service type definition.
type DispatcherService distinct service object {
    *http:Service;

    isolated function addServiceRef(Service|AdvancedService mcpService);
    isolated function removeServiceRef();
    isolated function setServerConfigs(ServerConfiguration serverConfigs);
};

DispatcherService dispatcherService = isolated service object {
    private ServerConfiguration? serverConfigs = ();
    private Service|AdvancedService? mcpService = ();
    private boolean isInitialized = false;
    private string? sessionId = ();

    isolated function addServiceRef(Service|AdvancedService mcpService) {
        lock {
            self.mcpService = mcpService;
        }
    }

    isolated function removeServiceRef() {
        lock {
            self.mcpService = ();
        }
    }

    isolated function setServerConfigs(ServerConfiguration serverConfigs) {
        lock {
            self.serverConfigs = serverConfigs.cloneReadOnly();
        }
    }

    isolated resource function post .(@http:Payload JsonRpcMessage request, http:Headers headers)
            returns http:BadRequest|http:NotAcceptable|http:UnsupportedMediaType|http:Accepted|http:Ok|ServerError {

        http:NotAcceptable|http:UnsupportedMediaType? headerValidationError = self.validateHeaders(headers);
        if !(headerValidationError is ()) {
            return headerValidationError;
        }

        lock {
            if request is JsonRpcRequest {
                return self.processJsonRpcRequest(request.cloneReadOnly());
            }
            else if request is JsonRpcNotification {
                return self.processJsonRpcNotification(request.cloneReadOnly());
            }

            JsonRpcError jsonRpcError = self.createErrorResponse(null, INVALID_REQUEST, "Unsupported request type");
            return <http:BadRequest>{
                body: jsonRpcError.cloneReadOnly()
            };
        }
    }

    private isolated function validateHeaders(http:Headers headers)
            returns http:NotAcceptable|http:UnsupportedMediaType? {

        // Validate Accept header
        string|http:HeaderNotFoundError acceptHeader = headers.getHeader(ACCEPT_HEADER);
        if acceptHeader is http:HeaderNotFoundError {
            JsonRpcError jsonRpcError = self.createErrorResponse(1, NOT_ACCEPTABLE,
                "Not Acceptable: Client must accept both application/json and text/event-stream");
            return <http:NotAcceptable>{
                body: jsonRpcError
            };
        }

        if !acceptHeader.includes(CONTENT_TYPE_JSON) || !acceptHeader.includes(CONTENT_TYPE_SSE) {
            JsonRpcError jsonRpcError = self.createErrorResponse(1, NOT_ACCEPTABLE,
                "Not Acceptable: Client must accept both application/json and text/event-stream");
            return <http:NotAcceptable>{
                body: jsonRpcError
            };
        }

        // Validate Content-Type header
        string|http:HeaderNotFoundError contentTypeHeader = headers.getHeader(CONTENT_TYPE_HEADER);
        if contentTypeHeader is http:HeaderNotFoundError {
            JsonRpcError jsonRpcError = self.createErrorResponse(null, UNSUPPORTED_MEDIA_TYPE,
                "Unsupported Media Type: Content-Type must be application/json");
            return <http:UnsupportedMediaType>{
                body: jsonRpcError
            };
        }

        if !contentTypeHeader.includes(CONTENT_TYPE_JSON) {
            JsonRpcError jsonRpcError = self.createErrorResponse(null, UNSUPPORTED_MEDIA_TYPE,
                "Unsupported Media Type: Content-Type must be application/json");
            return <http:UnsupportedMediaType>{
                body: jsonRpcError
            };
        }

        return ();
    }

    private isolated function processJsonRpcRequest(JsonRpcRequest request) returns http:BadRequest|http:Ok {
        match request.method {
            "initialize" => {
                return self.handleInitializeRequest(request);
            }
            "tools/list" => {
                return self.handleListToolsRequest(request);
            }
            "tools/call" => {
                return self.handleCallToolRequest(request);
            }
            _ => {
                JsonRpcError jsonRpcError = self.createErrorResponse(request.id, METHOD_NOT_FOUND, "Method not found");
                return <http:BadRequest>{
                    body: jsonRpcError
                };
            }
        }
    }

    private isolated function processJsonRpcNotification(JsonRpcNotification notification) returns http:Accepted|http:BadRequest {
        match notification.method {
            "notifications/initialized" => {
                return http:ACCEPTED;
            }
            _ => {
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
        }
    }

    private isolated function handleInitializeRequest(JsonRpcRequest jsonRpcRequest) returns http:BadRequest|http:Ok {
        JsonRpcRequest {jsonrpc, id, ...request} = jsonRpcRequest;
        InitializeRequest|error initRequest = request.cloneWithType(InitializeRequest);
        if initRequest is error {
            JsonRpcError jsonRpcError = self.createErrorResponse(id, INVALID_REQUEST,
                string `Invalid request: ${initRequest.message()}`);
            return <http:BadRequest>{
                body: jsonRpcError
            };
        }

        lock {
            // If it's a server with session management and the session ID is already set we should reject the request
            // to avoid re-initialization.
            if self.isInitialized && self.sessionId != () {
                JsonRpcError jsonRpcError = self.createErrorResponse(id, INVALID_REQUEST,
                    "Invalid Request: Only one initialization request is allowed");
                return <http:BadRequest>{
                    body: jsonRpcError.cloneReadOnly()
                };
            }

            self.isInitialized = true;
            self.sessionId = uuid:createRandomUuid();

            string requestedVersion = initRequest.params.protocolVersion;
            string protocolVersion = self.selectProtocolVersion(requestedVersion);

            return <http:Ok>{
                headers: {
                    [SESSION_ID_HEADER]: self.sessionId ?: ""
                },
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: id,
                    result: <InitializeResult>{
                        protocolVersion: protocolVersion,
                        capabilities: (self.serverConfigs?.options?.capabilities ?: {}).cloneReadOnly(),
                        serverInfo: (self.serverConfigs?.serverInfo ?: {
                            name: "MCP Server",
                            version: "1.0.0"
                        }).cloneReadOnly()
                    }
                }
            };
        }
    }

    private isolated function handleListToolsRequest(JsonRpcRequest request) returns http:BadRequest|http:Ok {
        lock {
            // Check if initialized
            if !self.isInitialized {
                JsonRpcError jsonRpcError = self.createErrorResponse(request.id, INVALID_REQUEST,
                    "Client must be initialized before making requests");
                return <http:BadRequest>{
                    body: jsonRpcError.cloneReadOnly()
                };
            }

            ListToolsResult|error listToolsResult = self.executeOnListTools();
            if listToolsResult is error {
                JsonRpcError jsonRpcError = self.createErrorResponse(request.id, INTERNAL_ERROR,
                    string `Failed to list tools: ${listToolsResult.message()}`);
                return <http:BadRequest>{
                    body: jsonRpcError.cloneReadOnly()
                };
            }

            return <http:Ok>{
                headers: {
                    [SESSION_ID_HEADER]: self.sessionId ?: ""
                },
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: request.id,
                    result: listToolsResult.cloneReadOnly()
                }
            };
        }
    }

    private isolated function handleCallToolRequest(JsonRpcRequest request) returns http:BadRequest|http:Ok {
        lock {
            // Check if initialized
            if !self.isInitialized {
                JsonRpcError jsonRpcError = self.createErrorResponse(request.id, INVALID_REQUEST,
                    "Client must be initialized before making requests");
                return <http:BadRequest>{
                    body: jsonRpcError.cloneReadOnly()
                };
            }

            // Extract and validate parameters
            CallToolParams|error params = request.cloneReadOnly().params.ensureType(CallToolParams);
            if params is error {
                JsonRpcError jsonRpcError = self.createErrorResponse(request.id, INVALID_PARAMS,
                    string `Invalid parameters: ${params.message()}`);
                return <http:BadRequest>{
                    body: jsonRpcError.cloneReadOnly()
                };
            }

            CallToolResult|error callToolResult = self.executeOnCallTool(params);
            if callToolResult is error {
                JsonRpcError jsonRpcError = self.createErrorResponse(request.id, INTERNAL_ERROR,
                    string `Failed to call tool '${params.name}': ${callToolResult.message()}`);
                return <http:BadRequest>{
                    body: jsonRpcError.cloneReadOnly()
                };
            }

            return <http:Ok>{
                headers: {
                    [SESSION_ID_HEADER]: self.sessionId ?: ""
                },
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: request.id,
                    result: callToolResult.cloneReadOnly()
                }
            };
        }
    }

    private isolated function selectProtocolVersion(string requestedVersion) returns string {
        foreach string supportedVersion in SUPPORTED_PROTOCOL_VERSIONS {
            if supportedVersion == requestedVersion {
                return requestedVersion;
            }
        }
        return LATEST_PROTOCOL_VERSION;
    }

    private isolated function createErrorResponse(RequestId? id, int code, string message) returns JsonRpcError {
        return {
            jsonrpc: JSONRPC_VERSION,
            id: id,
            'error: {
                code: code,
                message: message
            }
        };
    }

    private isolated function executeOnListTools() returns ListToolsResult|error {
        lock {
            Service|AdvancedService? mcpService = self.mcpService;
            if mcpService is AdvancedService {
                return check invokeOnListTools(mcpService);
            } else if mcpService is Service {
                return check listToolsForRemoteFunctions(mcpService);
            }
            return error DispatcherError("MCP Service is not attached");
        }
    }

    private isolated function executeOnCallTool(CallToolParams params) returns CallToolResult|error {
        lock {
            Service|AdvancedService? mcpService = self.mcpService;
            if mcpService is AdvancedService {
                return check invokeOnCallTool(mcpService, params.cloneReadOnly());
            } else if mcpService is Service {
                return check callToolForRemoteFunctions(mcpService, params.cloneReadOnly());
            }
            return error DispatcherError("MCP Service is not attached");
        }
    }
};
