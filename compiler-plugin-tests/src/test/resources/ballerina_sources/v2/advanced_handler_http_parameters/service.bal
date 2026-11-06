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

import ballerina/http;
import ballerina/mcp.v2 as mcp;

// onListTools binds HTTP request values and may declare a cursor.
@mcp:StreamableHttpServiceConfig {
    info: {name: "advanced-handler-http-parameters", version: "1.0.0"}
}
service mcp:StreamableHttpAdvancedService /mcp on new mcp:StreamableHttpListener(9341) {
    remote isolated function onListTools(mcp:Cursor? cursor, mcp:AuthContext? auth,
            @http:Header {name: "X-Tenant"} string? tenant, http:Headers headers, http:Request request)
            returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params)
            returns mcp:CallToolResult|mcp:InputRequiredResult|mcp:ServerError {
        return {resultType: "complete", content: []};
    }
}

@mcp:StreamableHttpServiceConfig {
    info: {name: "advanced-handler-cursor-only", version: "1.0.0"}
}
service mcp:StreamableHttpAdvancedService /cursor on new mcp:StreamableHttpListener(9342) {
    remote isolated function onListTools(mcp:Cursor? cursor) returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params)
            returns mcp:CallToolResult|mcp:InputRequiredResult|mcp:ServerError {
        return {resultType: "complete", content: []};
    }
}
