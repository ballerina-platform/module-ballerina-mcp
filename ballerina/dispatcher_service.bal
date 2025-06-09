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
import ballerina/io;
import ballerina/uuid;

// import ballerina/io;

type DispatcherService distinct service object {
    *http:Service;

    isolated function addServiceRef(McpService mcpService);
    isolated function removeServiceRef();
    isolated function setServerConfigs(ServerConfiguration serverConfigs);
};

DispatcherService dispatcherService = isolated service object {
    private ServerConfiguration? serverConfigs = ();
    private McpService? mcpService = ();
    private boolean isInitialized = false;
    private string? sessionId = ();

    isolated function addServiceRef(McpService mcpService) {
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

    isolated resource function get .() returns error? {
        
    }

    isolated resource function post .(@http:Payload JsonRpcMessage request, http:Headers headers) returns http:BadRequest|http:Accepted|http:Ok|error {
        lock {
            io:println("Received request: ", request.cloneReadOnly());
            string|http:HeaderNotFoundError acceptHeader = headers.getHeader(ACCEPT_HEADER);
            if acceptHeader is http:HeaderNotFoundError {
                return <http:BadRequest>{
                    body: {
                        jsonrpc: JSONRPC_VERSION,
                        id: 1,
                        'error: {
                            code: -32000,
                            message: "Not Acceptable: Client must accept both application/json and text/event-stream"
                        }
                    }
                };
            }
            if !acceptHeader.includes(CONTENT_TYPE_JSON) || !acceptHeader.includes(CONTENT_TYPE_SSE) {
                return <http:BadRequest>{
                    body: {
                        jsonrpc: JSONRPC_VERSION,
                        id: 1,
                        'error: {
                            code: -32000,
                            message: "Not Acceptable: Client must accept both application/json and text/event-stream"
                        }
                    }
                };
            }

            string|http:HeaderNotFoundError contentTypeHeader = headers.getHeader(CONTENT_TYPE_HEADER);
            if contentTypeHeader is http:HeaderNotFoundError {
                return <http:BadRequest>{
                    body: {
                        jsonrpc: JSONRPC_VERSION,
                        id: null,
                        'error: {
                            code: -32000,
                            message: "Unsupported Media Type: Content-Type must be application/json"
                        }
                    }
                };
            }
            if !contentTypeHeader.includes(CONTENT_TYPE_JSON) {
                return <http:BadRequest>{
                    body: {
                        jsonrpc: JSONRPC_VERSION,
                        id: null,
                        'error: {
                            code: -32000,
                            message: "Unsupported Media Type: Content-Type must be application/json"
                        }
                    }
                };
            }

            if request is JsonRpcRequest {
                if request.method == "initialize" {
                    if self.isInitialized && self.sessionId != () {
                        return <http:BadRequest>{
                            body: {
                                jsonrpc: JSONRPC_VERSION,
                                id: null,
                                'error: {
                                    code: -32600,
                                    message: "Invalid Request: Only one initialization request is allowed"
                                }
                            }
                        };
                    }
                    self.isInitialized = true;
                    self.sessionId = uuid:createRandomUuid();

                    final string requestedVersion = check (request.params["protocolVersion"]).cloneWithType();
                    final readonly & ServerCapabilities? capabilities = (self.serverConfigs?.options?.capabilities).cloneReadOnly();
                    final readonly & Implementation? serverInfo = (self.serverConfigs?.serverInfo).cloneReadOnly();

                    if serverInfo is () {
                        return <http:BadRequest>{
                            body: {
                                jsonrpc: JSONRPC_VERSION,
                                id: null,
                                'error: {
                                    code: -32000,
                                    message: "Server Info not provided in configuration"
                                }
                            }
                        };
                    }

                    string protocolVersion = SUPPORTED_PROTOCOL_VERSIONS.some(v => v == requestedVersion) ? requestedVersion
                        : LATEST_PROTOCOL_VERSION;

                    return <http:Ok>{
                        headers: {
                            [SESSION_ID_HEADER]: self.sessionId ?: ""
                        },
                        body: {
                            jsonrpc: JSONRPC_VERSION,
                            id: request.id,
                            result: <InitializeResult>{
                                protocolVersion: protocolVersion,
                                capabilities: capabilities ?: {},
                                serverInfo: serverInfo
                            }
                        }
                    };
                } else if request.method == "tools/list" {
                    ListToolsResult listToolsResult = check self.executeOnListTools();
                    io:println("ListToolsResult: ", listToolsResult.cloneReadOnly());
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
                } else if request.method == "tools/call" {
                    CallToolParams params = check request.cloneReadOnly().params.ensureType(CallToolParams);
                    CallToolResult callToolResult = check self.executeOnCallTool(params);
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
                } else {
                    return <http:BadRequest>{
                        body: {
                            jsonrpc: JSONRPC_VERSION,
                            id: request.id,
                            'error: {
                                code: -32601,
                                message: "Method not found"
                            }
                        }
                    };
                }
            }
            else if request is JsonRpcNotification {
                if request.method == "notifications/initialized" {
                    return http:ACCEPTED;
                }
            }
        }
        // if request is InitializeRequest {
        //     lock {
        //         if self.isInitialized && self.sessionId != () {
        //             return {
        //                 jsonrpc: JSONRPC_VERSION,
        //                 id: null,
        //                 'error: {
        //                     code: -32600,
        //                     message: "Invalid Request: Only one initialization request is allowed" 
        //                 }
        //             };
        //         }
        //         self.isInitialized = true;
        //         self.sessionId = uuid:createRandomUuid();
        //         io:println("Session initialized with ID: ", self.sessionId);
        //     }
        // } else if request is ListToolsRequest {
        //     io:println("Received ListToolsRequest");
        // } else if request is CallToolRequest {
        //     io:println("Received CallToolRequest");
        // }
        return error("Unsupported request type");
    }

    private isolated function executeOnListTools() returns ListToolsResult|error {
        lock {
            McpService? chatService = self.mcpService;
            if chatService is McpService {
                return check invokeOnListTools(chatService);
            }
            return error("MCP Service is not attached");
        }
    }

    private isolated function executeOnCallTool(CallToolParams params) returns CallToolResult|error {
        lock {
            McpService? chatService = self.mcpService;
            if chatService is McpService {
                return check invokeOnCallTool(chatService, params.cloneReadOnly());
            }
            return error("MCP Service is not attached");
        }
    }
};
