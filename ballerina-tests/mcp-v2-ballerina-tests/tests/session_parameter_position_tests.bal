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
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/mcp.v2 as mcpv2;
import ballerina/test;

isolated function nextVisit(mcpv2:HttpSession session) returns int {
    mcpv2:HttpSessionEntry previous = session.hasKey("visits") ? session.get("visits") : 0;
    int visits = (previous is int ? previous : 0) + 1;
    session.set("visits", visits);
    return visits;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "session-position", version: "1.0.0"}}
service mcpv2:StreamableHttpService /sessionPosition on structuredListener {
    remote isolated function sessionInMiddle(string label, mcpv2:HttpSession session, int step) returns string =>
        string `${label}:${nextVisit(session)}:${step}`;

    remote isolated function sessionLast(string label, mcpv2:HttpSession? session) returns string =>
        string `${label}:${session is () ? "none" : nextVisit(session).toString()}`;
}

@test:Config {}
function testSessionParameterAtMiddleAndLastPositions() returns error? {
    mcpv2:StreamableHttpClient legacyClient = check new ("http://localhost:8789/sessionPosition",
            protocolMode = "legacy");
    _ = check legacyClient->connect();

    mcpv2:ListToolsResult listedTools = check legacyClient->listTools();
    map<string[]> expectedProperties = {"sessionInMiddle": ["label", "step"], "sessionLast": ["label"]};
    foreach mcpv2:ToolDefinition toolInfo in listedTools.tools {
        map<json> properties = check toolInfo.inputSchema.properties.ensureType();
        test:assertEquals(properties.keys().sort(), expectedProperties[toolInfo.name]);
    }

    test:assertEquals(check callSessionTool(legacyClient, "sessionInMiddle", {"label": "a", "step": 5}), "a:1:5");
    test:assertEquals(check callSessionTool(legacyClient, "sessionLast", {"label": "b"}), "b:2");
    test:assertEquals(check callSessionTool(legacyClient, "sessionInMiddle", {"label": "c", "step": 7}), "c:3:7");
    check legacyClient->close();
}

function callSessionTool(mcpv2:StreamableHttpClient sessionClient, string toolName, record {} arguments)
        returns string|error {
    mcpv2:CallToolResult result = check sessionClient->callTool({name: toolName, arguments});
    mcpv2:TextContent textContent = check result.content[0].ensureType();
    return textContent.text;
}
