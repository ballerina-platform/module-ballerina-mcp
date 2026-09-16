// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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

import ballerina/mcp;

configurable int interopPort = ?;
listener mcp:StreamableHttpListener interopListener = new (interopPort);

@mcp:StreamableHttpConfig {info: {name: "ballerina-interop", version: "2.0.0"}}
service mcp:StreamableHttpService /mcp on interopListener {
    remote isolated function add(int firstValue, int secondValue) returns int => firstValue + secondValue;

    remote isolated function echo(
            @mcp:Argument {headerName: "Region"} string region) returns string => region;
}

@mcp:StreamableHttpConfig {info: {name: "ballerina-stateful-interop", version: "2.0.0"}}
service mcp:StreamableHttpService /stateful on interopListener {
    remote isolated function sessionIdentity(mcp:HttpSession sessionValue) returns string => sessionValue.getSessionId();
}

@mcp:StreamableHttpConfig {info: {name: "ballerina-modern-interop", version: "2.0.0"}, protocolMode: "modern"}
service mcp:StreamableHttpAdvancedService /modern on interopListener {
    remote isolated function onListTools() returns mcp:ListToolsResult => {
        tools: [{name: "scalar", inputSchema: {'type: "object"}, outputSchema: {"type": "integer"}}]
    };

    remote isolated function onCallTool(mcp:CallToolParams callParams) returns mcp:CallToolResult => {
        content: [{'type: "text", text: "42"}],
        structuredContent: 42
    };
}
