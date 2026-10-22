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

// onListTools does not accept mcp:CallToolParams or mcp:Session; the reported supported types
// must be specific to onListTools and must not list those two (MCP_102).
@mcp:StreamableHttpServiceConfig {
    info: {name: "sample-17", version: "1.0.0"}
}
service mcp:StreamableHttpAdvancedService /mcp on new mcp:StreamableHttpListener(9317) {

    remote function onListTools(mcp:CallToolParams params) returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote function onCallTool(mcp:CallToolParams params) returns mcp:CallToolResult|mcp:ServerError {
        return {content: []};
    }
}
