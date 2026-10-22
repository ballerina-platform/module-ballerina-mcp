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

isolated function invokeOnListTools(AdvancedService 'service)
        returns ListToolsResult|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function invokeOnCallTool(AdvancedService 'service, CallToolParams params, Session? session)
        returns CallToolResult|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function invokeAdvancedOnListTools(StreamableHttpAdvancedService 'service, http:Headers headers,
        http:Request request, map<string[]> headerValues, boolean treatNilableAsOptional)
        returns ListToolsResult|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function invokeAdvancedOnCallTool(StreamableHttpAdvancedService 'service, CallToolParams params,
        Session? session, http:Headers headers, http:Request request, map<string[]> headerValues,
        boolean treatNilableAsOptional) returns CallToolResult|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function listToolsForRemoteFunctions(Service|StreamableHttpService 'service,
        typedesc<ListToolsResult> t = <>) returns t|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function callToolForRemoteFunctions(Service|StreamableHttpService 'service, CallToolParams params,
        Session? session, http:Headers headers, http:Request request, map<string[]> headerValues,
        boolean treatNilableAsOptional, typedesc<CallToolResult> t = <>) returns t|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function addMcpServiceToDispatcher(http:Service dispatcherService,
        Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService mcpService)
        returns Error? = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function getMcpServiceFromDispatcher(http:Service dispatcherService)
        returns Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;
