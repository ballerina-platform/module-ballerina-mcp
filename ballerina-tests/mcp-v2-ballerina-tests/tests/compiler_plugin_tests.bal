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

import ballerina/mcp.v2 as mcpv2;
import ballerina/test;

@mcpv2:StreamableHttpServiceConfig {
    info: {name: "inline-listener-test-server", version: "1.0.0"},
    sessionMode: mcpv2:STATELESS
}
isolated service mcpv2:StreamableHttpService /mcp on new mcpv2:StreamableHttpListener(8765) {

    # Returns a greeting for the given name.
    # 
    # + name - The name to greet
    # + return - A greeting message
    isolated remote function getGreeting(string name) returns string {
        return "Hello, " + name + "!";
    }
}

final mcpv2:StreamableHttpClient mcpClient = check new ("http://localhost:8765/mcp");
final mcpv2:Implementation clientInfo = {name: "test-client", version: "1.0.0"};

@test:Config
function testInlineListenerToolDiscovery() returns error? {
    _ = check mcpClient->connect(clientInfo);
    mcpv2:ListToolsResult result = check mcpClient->listTools();

    test:assertEquals(result.tools.length(), 1,
        msg = "Expected 1 tool — compiler plugin must have processed the inline-listener service");
    test:assertEquals(result.tools[0].name, "getGreeting");
}

@test:Config {dependsOn: [testInlineListenerToolDiscovery]}
function testInlineListenerToolSchema() returns error? {
    mcpv2:ListToolsResult result = check mcpClient->listTools();

    var inputSchema = result.tools[0].inputSchema;
    test:assertEquals(inputSchema.'type, "object");
    map<anydata> properties = inputSchema.properties ?: {};
    test:assertTrue(properties.hasKey("name"),
        msg = "Schema must include the 'name' parameter — compiler plugin generates the schema");
}

@test:Config {dependsOn: [testInlineListenerToolDiscovery]}
function testInlineListenerCallTool() returns error? {
    mcpv2:CallToolResult result = check mcpClient->callTool({name: "getGreeting", arguments: {"name": "World"}});

    test:assertFalse(result.isError ?: false);
    mcpv2:TextContent textContent = check result.content[0].ensureType();
    test:assertEquals(textContent.text, "Hello, World!");
}

listener mcpv2:StreamableHttpListener ln = check new (8766);

@mcpv2:StreamableHttpServiceConfig {
    info: {name: "inline-listener-test-server-2", version: "1.0.0"},
    sessionMode: mcpv2:STATELESS
}
isolated service mcpv2:StreamableHttpService /mcp on ln {

    # Returns a greeting for the given name.
    # 
    # + name - The name to greet
    # + return - A greeting message
    isolated remote function getGreetingStr(string name) returns string {
        return "Hello, " + name + "!";
    }
}

final mcpv2:StreamableHttpClient mcpClient2 = check new ("http://localhost:8766/mcp");
final mcpv2:Implementation clientInfo2 = {name: "test-client-2", version: "1.0.0"};

@test:Config
function testListenerDeclToolDiscovery() returns error? {
    _ = check mcpClient2->connect(clientInfo2);
    mcpv2:ListToolsResult result = check mcpClient2->listTools();

    test:assertEquals(result.tools.length(), 1,
        msg = "Expected 1 tool — compiler plugin must have processed the declared-listener service");
    test:assertEquals(result.tools[0].name, "getGreetingStr");
}
