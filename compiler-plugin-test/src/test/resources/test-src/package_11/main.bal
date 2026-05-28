// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
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
import ballerina/mcp;

// MCP service — the MCP compiler plugin SHOULD emit an endpoint.yaml for this one.
listener mcp:Listener mcpListener = check new (9091);

@mcp:ServiceConfig {
    info: {
        name: "Demo MCP Server",
        version: "1.0.0"
    },
    sessionMode: mcp:STATELESS
}
service mcp:AdvancedService /mcp on mcpListener {

    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params, mcp:Session? session)
            returns mcp:CallToolResult|mcp:ServerError {
        return error mcp:ServerError("not implemented");
    }
}

// Plain HTTP service — the MCP compiler plugin must NOT emit an endpoint.yaml for this one.
listener http:Listener httpListener = new (8080);

service /api on httpListener {
    resource function get hello() returns string {
        return "hi";
    }
}
