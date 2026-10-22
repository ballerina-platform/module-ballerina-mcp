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

import ballerina/test;

listener StreamableHttpListener advancedShapesListener = check new (3274);

const ADVANCED_SHAPES_URL = "http://localhost:3274";

// Returns the new result types, which 1.x types cannot hold.
service StreamableHttpAdvancedService /newShapes on advancedShapesListener {
    remote isolated function onListTools() returns ToolPage|ServerError => {
        tools: [
            {
                name: "numbers",
                inputSchema: {'type: "object"},
                outputSchema: {"type": "array", "items": {"type": "integer"}}
            }
        ]
    };

    remote isolated function onCallTool(CallToolParams params) returns ToolResult|ServerError => {
        content: [{'type: "text", text: "[1,2,3]"}],
        structuredContent: [1, 2, 3]
    };
}

// The 1.4.0 signatures, returning the 1.x types.
service StreamableHttpAdvancedService /oldShapes on advancedShapesListener {
    remote isolated function onListTools() returns ListToolsResult|ServerError => {
        tools: [{name: "echo", inputSchema: {'type: "object", properties: {}}}],
        "ttlMs": 5,
        _meta: {"vendor": "v"}
    };

    remote isolated function onCallTool(CallToolParams params, Session? session) returns CallToolResult|ServerError => {
        content: [{'type: "text", text: "echo"}],
        structuredContent: {"k": "v"},
        _meta: {"vendor": "v"},
        "resultType": "complete"
    };
}

@test:Config {}
function testModernClientReceivesNewAdvancedShapesIntact() returns error? {
    StreamableHttpClient2 modernClient = check new (ADVANCED_SHAPES_URL + "/newShapes", protocolMode = "modern");
    _ = check modernClient->connect();
    ToolPage page = check modernClient->listTools();
    test:assertEquals(page.tools[0]?.outputSchema, {"type": "array", "items": {"type": "integer"}});
    ToolResult result = check modernClient->callTool({name: "numbers"});
    test:assertEquals(result?.structuredContent, [1, 2, 3]);
    check modernClient->close();
}

@test:Config {}
function testModernClientReceivesOldAdvancedShapes() returns error? {
    StreamableHttpClient2 modernClient = check new (ADVANCED_SHAPES_URL + "/oldShapes", protocolMode = "modern");
    _ = check modernClient->connect();
    ToolPage page = check modernClient->listTools();
    test:assertEquals(page.tools.map(toolInfo => toolInfo.name), ["echo"]);
    ToolResult result = check modernClient->callTool({name: "echo"});
    test:assertEquals(result?.structuredContent, {"k": "v"});
    check modernClient->close();
}

@test:Config {}
function testLegacyClientReceivesOldAdvancedShapesVerbatim() returns error? {
    StreamableHttpClient legacyClient = check new (ADVANCED_SHAPES_URL + "/oldShapes");
    check legacyClient->initialize();
    ListToolsResult page = check legacyClient->listTools();
    test:assertEquals(page["ttlMs"], 5);
    test:assertEquals(page._meta, {"vendor": "v"});
    CallToolResult result = check legacyClient->callTool({name: "echo"});
    test:assertEquals(result._meta, {"vendor": "v"});
    test:assertEquals(result["resultType"], "complete");
    check legacyClient->close();
}
