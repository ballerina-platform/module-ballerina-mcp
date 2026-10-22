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
import ballerina/mcp;
import ballerina/test;

// An advanced Streamable HTTP service whose onListTools/onCallTool bind transport-specific request
// information the same way StreamableHttpService tools do: @http:Header, http:Headers, http:Request.
@mcp:StreamableHttpServiceConfig {
    info: {name: "advanced-http-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:StreamableHttpAdvancedService /mcp on new mcp:StreamableHttpListener(8771) {

    isolated remote function onListTools(@http:Header {name: "X-Tools-Filter"} string? filter)
            returns mcp:ListToolsResult|mcp:ServerError {
        string toolName = filter ?: "whoAmI";
        return {
            tools: [
                {name: toolName, description: "Returns the Authorization header", inputSchema: {'type: "object"}}
            ]
        };
    }

    isolated remote function onCallTool(mcp:CallToolParams params, mcp:Session? session,
            @http:Header {name: "Authorization"} string? auth, http:Headers headers)
            returns mcp:CallToolResult|mcp:ServerError {
        string viaAnnotation = auth ?: "<none>";
        string|http:HeaderNotFoundError traceHeader = headers.getHeader("X-Trace");
        string trace = traceHeader is string ? traceHeader : "<none>";
        return {content: [{'type: "text", text: viaAnnotation + "|" + trace}]};
    }
}

final http:Client rawAdvancedClient = check new ("http://localhost:8771");

@test:Config
function testStreamableHttpAdvancedServiceListTools() returns error? {
    // onListTools binds an @http:Header parameter to choose the listed tool name.
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 1, method: "tools/list", params: {}});
    request.setHeader("Accept", "application/json, text/event-stream");
    request.setHeader("X-Tools-Filter", "filteredTool");
    http:Response response = check rawAdvancedClient->post("/mcp", request);
    json result = check response.getJsonPayload();
    json[] tools = check (check result.result.tools).ensureType();
    test:assertEquals(tools.length(), 1);
    test:assertEquals(check tools[0].name, "filteredTool");
}

@test:Config
function testStreamableHttpAdvancedServiceHeaderAccess() returns error? {
    // onCallTool binds an @http:Header parameter and the raw http:Headers object simultaneously.
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 2, method: "tools/call",
        params: {name: "whoAmI", arguments: {}}});
    request.setHeader("Accept", "application/json, text/event-stream");
    request.setHeader("Authorization", "Bearer adv-token");
    request.setHeader("X-Trace", "trace-123");
    http:Response response = check rawAdvancedClient->post("/mcp", request);
    json result = check response.getJsonPayload();
    test:assertEquals(check getRawTextResult(result), "Bearer adv-token|trace-123");
}
