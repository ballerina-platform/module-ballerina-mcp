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

import ballerina/jballerina.java;

isolated function invokeOnListTools(AdvancedService 'service) returns ListToolsResult|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function invokeOnCallTool(AdvancedService 'service, CallToolParams params, Session? session)
        returns CallToolResult|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function listToolsForRemoteFunctions(Service 'service, typedesc<ListToolsResult> t = <>)
        returns t|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function callToolForRemoteFunctions(Service 'service, CallToolParams params, Session? session,
        typedesc<CallToolResult> t = <>) returns t|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function addMcpServiceToDispatcher(DispatcherService dispatcherService, Service|AdvancedService mcpService)
        returns Error? = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function getMcpServiceFromDispatcher(DispatcherService dispatcherService)
        returns Service|AdvancedService|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;
