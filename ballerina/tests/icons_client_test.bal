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
import ballerina/test;

const string ICONS_MOCK_SERVER_URL = "http://localhost:3203/mcp";
const string ICON_DATA_URI = "data:image/png;base64,iVBORw0KGgo=";

// Spec-compliant icons (MCP 2025-11-25), as sent by servers such as github-mcp-server.
final readonly & json[] mockIcons = [
    {src: ICON_DATA_URI, mimeType: "image/png", theme: "light"},
    {src: ICON_DATA_URI, mimeType: "image/png", theme: "dark"},
    {src: "https://example.com/icon.svg", sizes: ["any"]}
];

// A minimal MCP-like HTTP server whose initialize and tools/list results carry icons.
isolated service /mcp on new http:Listener(3203) {
    isolated resource function post .(@http:Payload json payload) returns http:Ok|http:Accepted|error {
        string method = check payload.method.ensureType();
        if method == REQUEST_INITIALIZE {
            return <http:Ok>{
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: check payload.id,
                    result: {
                        protocolVersion: "2025-03-26",
                        capabilities: {tools: {}},
                        serverInfo: {name: "icons-server", version: "1.0.0", icons: mockIcons}
                    }
                }
            };
        }
        if method == NOTIFICATION_INITIALIZED {
            return http:ACCEPTED;
        }
        return <http:Ok>{
            body: {
                jsonrpc: JSONRPC_VERSION,
                id: check payload.id,
                result: {
                    tools: [
                        {
                            name: "get_me",
                            description: "Get details of the authenticated GitHub user",
                            inputSchema: {'type: "object", properties: {}},
                            annotations: {title: "Get my user profile", readOnlyHint: true},
                            icons: mockIcons
                        }
                    ],
                    // Non-spec top-level fields sent by some servers.
                    ttlMs: 60000,
                    cacheScope: "session"
                }
            }
        };
    }
}

@test:Config {}
function testClientDecodesSpecCompliantIcons() returns error? {
    StreamableHttpClient 'client = check new (ICONS_MOCK_SERVER_URL);
    check 'client->initialize();

    ListToolsResult result = check 'client->listTools();
    test:assertEquals(result.tools.length(), 1);
    ToolDefinition tool = result.tools[0];
    test:assertEquals(tool.name, "get_me");
    Icon[] icons = tool.icons ?: [];
    test:assertEquals(icons.length(), 3);
    test:assertEquals(icons[0].src, ICON_DATA_URI);
    test:assertEquals(icons[0].mimeType, "image/png");
    test:assertEquals(icons[0].theme, "light");
    test:assertEquals(icons[1].theme, "dark");
    test:assertEquals(icons[2].sizes, ["any"]);
    test:assertEquals(result["ttlMs"], 60000);
    test:assertEquals(result["cacheScope"], "session");
}

@test:Config {}
function testServerInfoWithSpecCompliantIconsConverts() returns error? {
    json initResult = {
        protocolVersion: "2025-11-25",
        capabilities: {},
        serverInfo: {name: "icons-server", version: "1.0.0", icons: mockIcons}
    };
    InitializeResult result = check initResult.cloneWithType();
    Icon[] icons = result.serverInfo.icons ?: [];
    test:assertEquals(icons.length(), 3);
    test:assertEquals(icons[0].src, ICON_DATA_URI);
}
