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
import ballerina/jballerina.java;

// Every service type a listener accepts, including the deprecated transport-neutral ones.
type McpService Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService;

isolated function invokeOnListTools(AdvancedService 'service)
        returns ListToolsResult|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function invokeOnCallTool(AdvancedService 'service, CallToolParams params, Session? session)
        returns CallToolResult|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function invokeAdvancedOnListTools(StreamableHttpAdvancedService 'service, Cursor? cursor,
        http:Headers headers, http:Request request, map<string[]> headerValues, boolean treatNilableAsOptional,
        AuthContext? authContext)
        returns ListToolsResult|ToolPage|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function invokeAdvancedOnCallTool(StreamableHttpAdvancedService 'service, CallToolParams params,
        Session? session, http:Headers headers, http:Request request, map<string[]> headerValues,
        boolean treatNilableAsOptional, AuthContext? authContext)
        returns CallToolResult|ToolResult|InputRequiredResult|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function listToolsForRemoteFunctions(Service|StreamableHttpService 'service,
        typedesc<ToolPage> t = <>) returns t|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function listProtocolToolsForRemoteFunctions(StreamableHttpService 'service,
        typedesc<ToolPage> t = <>) returns t|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function callToolForRemoteFunctions(Service|StreamableHttpService 'service, CallToolParams params,
        Session? session, http:Headers headers, http:Request request, map<string[]> headerValues,
        boolean treatNilableAsOptional, AuthContext? authContext, Context toolContext,
        typedesc<ToolResult> t = ToolResult) returns ToolResult|InputRequiredResult|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function callProtocolToolForRemoteFunctions(StreamableHttpService 'service, CallToolParams params,
        Session? session, http:Headers headers, http:Request request, map<string[]> headerValues,
        boolean treatNilableAsOptional, AuthContext? authContext, Context toolContext,
        typedesc<ToolResult> t = ToolResult) returns ToolResult|InputRequiredResult|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function addMcpServiceToDispatcher(http:Service dispatcherService,
        McpService mcpService)
        returns Error? = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function getMcpServiceFromDispatcher(http:Service dispatcherService)
        returns McpService|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

// Runtime counterpart of the compiler diagnostic, including dynamically attached services.
isolated function requiresLegacySession(McpService mcpService)
        returns boolean = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

// Returns whether the service requires a non-nilable `mcp:AuthContext`.
// Used during attachment to ensure the service is configured with `mcp:OAuthProtectedResourceConfig`.
isolated function requiresAuthContext(McpService mcpService)
        returns boolean = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

// Returns the scopes declared with `@mcp:Tool`, keyed by tool name. Advanced services declare none.
isolated function getToolScopes(McpService mcpService)
        returns readonly & map<string[]> = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;
