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
};

DispatcherService dispatcherService = isolated service object {
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


    isolated resource function post .(@http:Payload JsonRpcMessage request, http:Headers headers)
            returns http:BadRequest|http:NotAcceptable|http:UnsupportedMediaType|http:Accepted|http:Ok|ServerError {
        http:NotAcceptable|http:UnsupportedMediaType? headerValidationError = self.validateHeaders(headers);
        if headerValidationError !is () {
            return headerValidationError;
        }

        if request is JsonRpcRequest {
            return self.processJsonRpcRequest(request);
        }
        if request is JsonRpcNotification {
            return self.processJsonRpcNotification(request);
        }

        JsonRpcError & readonly jsonRpcError = self.createJsonRpcError(INVALID_REQUEST, "Unsupported request type");
        return <http:BadRequest>{
            body: jsonRpcError
        };
    }

    private isolated function validateHeaders(http:Headers headers)
            returns http:NotAcceptable|http:UnsupportedMediaType? {
        // Validate Accept header
        string|http:HeaderNotFoundError acceptHeader = headers.getHeader(ACCEPT_HEADER);
        if acceptHeader is http:HeaderNotFoundError {
            JsonRpcError jsonRpcError = self.createJsonRpcError(NOT_ACCEPTABLE,
                "Not Acceptable: Client must accept both application/json and text/event-stream");
            return <http:NotAcceptable>{
                body: jsonRpcError
            };
        }

        if !acceptHeader.includes(CONTENT_TYPE_JSON) || !acceptHeader.includes(CONTENT_TYPE_SSE) {
            JsonRpcError jsonRpcError = self.createJsonRpcError(NOT_ACCEPTABLE,
                "Not Acceptable: Client must accept both application/json and text/event-stream");
            return <http:NotAcceptable>{
                body: jsonRpcError
            };
        }

        // Validate Content-Type header
        string|http:HeaderNotFoundError contentTypeHeader = headers.getHeader(CONTENT_TYPE_HEADER);
        if contentTypeHeader is http:HeaderNotFoundError {
            JsonRpcError jsonRpcError = self.createJsonRpcError(UNSUPPORTED_MEDIA_TYPE,
                "Unsupported Media Type: Content-Type must be application/json");
            return <http:UnsupportedMediaType>{
                body: jsonRpcError
            };
        }

        if !contentTypeHeader.includes(CONTENT_TYPE_JSON) {
            JsonRpcError jsonRpcError = self.createJsonRpcError(UNSUPPORTED_MEDIA_TYPE,
                "Unsupported Media Type: Content-Type must be application/json");
            return <http:UnsupportedMediaType>{
                body: jsonRpcError
            };
        }

        return;
    }

    private isolated function processJsonRpcRequest(JsonRpcRequest request) returns http:BadRequest|http:Ok {
        match request.method {
            REQUEST_INITIALIZE => {
                return self.handleInitializeRequest(request);
            }
            REQUEST_LIST_TOOLS => {
                return self.handleListToolsRequest(request);
            }
            REQUEST_CALL_TOOL => {
                return self.handleCallToolRequest(request);
            }
            _ => {
                JsonRpcError jsonRpcError = self.createJsonRpcError(METHOD_NOT_FOUND, "Method not found", request.id);
                return <http:BadRequest>{
                    body: jsonRpcError
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

    private isolated function handleInitializeRequest(JsonRpcRequest jsonRpcRequest) returns http:BadRequest|http:Ok {
        JsonRpcRequest {jsonrpc: _, id, ...request} = jsonRpcRequest;
        InitializeRequest|error initRequest = request.cloneWithType();
        if initRequest is error {
            JsonRpcError jsonRpcError = self.createJsonRpcError(INVALID_REQUEST,
                string `Invalid request: ${initRequest.message()}`, id);
            return <http:BadRequest>{
                body: jsonRpcError
            };
        }

        lock {
            // If it's a server with session management and the session ID is already set we should reject the request
            // to avoid re-initialization.
            if self.isInitialized && self.sessionId != () {
                JsonRpcError & readonly jsonRpcError = self.createJsonRpcError(INVALID_REQUEST,
                    "Invalid Request: Only one initialization request is allowed", id);
                return <http:BadRequest>{
                    body: jsonRpcError
                };
            }

            Service|AdvancedService? mcpService = self.mcpService;
            if mcpService is () {
                JsonRpcError & readonly jsonRpcError = self.createJsonRpcError(INTERNAL_ERROR,
                    "Internal Error: MCP Service is not attached", id);
                return <http:BadRequest>{
                    body: jsonRpcError
                };
            }

            ServiceConfiguration serviceConfig = getServiceConfiguration(mcpService);

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
                        capabilities: (serviceConfig.options?.capabilities ?: {}).cloneReadOnly(),
                        serverInfo: serviceConfig.info.cloneReadOnly()
                    }
                }
            };
        }
    }

    private isolated function handleListToolsRequest(JsonRpcRequest request) returns http:BadRequest|http:Ok {
        lock {
            // Check if initialized
            if !self.isInitialized {
                JsonRpcError & readonly jsonRpcError = self.createJsonRpcError(INVALID_REQUEST,
                    "Client must be initialized before making requests", request.id);
                return <http:BadRequest>{
                    body: jsonRpcError
                };
            }
        }

        ListToolsResult|error listToolsResult = self.executeOnListTools();
        if listToolsResult is error {
            JsonRpcError & readonly jsonRpcError = self.createJsonRpcError(INTERNAL_ERROR,
                    string `Failed to list tools: ${listToolsResult.message()}`, request.id);
            return <http:BadRequest>{
                body: jsonRpcError
            };
        }

        lock {
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
                JsonRpcError & readonly jsonRpcError = self.createJsonRpcError(INVALID_REQUEST,
                    "Client must be initialized before making requests", request.id);
                return <http:BadRequest>{
                    body: jsonRpcError
                };
            }
        }

        // Extract and validate parameters
        CallToolParams|error params = request.params.cloneWithType();
        if params is error {
            JsonRpcError jsonRpcError = self.createJsonRpcError(INVALID_PARAMS,
                string `Invalid parameters: ${params.message()}`, request.id);
            return <http:BadRequest>{
                body: jsonRpcError
            };
        }

        CallToolResult|error callToolResult = self.executeOnCallTool(params);
        if callToolResult is error {
            JsonRpcError jsonRpcError = self.createJsonRpcError(INTERNAL_ERROR,
                string `Failed to call tool '${params.name}': ${callToolResult.message()}`, request.id);
            return <http:BadRequest>{
                body: jsonRpcError
            };
        }

        lock {
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

    private isolated function createJsonRpcError(int code, string message, RequestId? id = ()) returns JsonRpcError & readonly {
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
                return invokeOnListTools(mcpService);
            }
            if mcpService is Service {
                return listToolsForRemoteFunctions(mcpService);
            }
            return error DispatcherError("MCP Service is not attached");
        }
    }

    private isolated function executeOnCallTool(CallToolParams params) returns CallToolResult|error {
        lock {
            Service|AdvancedService? mcpService = self.mcpService;
            if mcpService is AdvancedService {
                return invokeOnCallTool(mcpService, params.cloneReadOnly());
            }
            if mcpService is Service {
                return callToolForRemoteFunctions(mcpService, params.cloneReadOnly());
            }
            return error DispatcherError("MCP Service is not attached");
        }
    }
};
