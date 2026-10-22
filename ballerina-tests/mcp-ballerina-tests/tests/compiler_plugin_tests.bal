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
import ballerina/test;

@mcp:ServiceConfig {
    info: {name: "inline-listener-test-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:Service /mcp on new mcp:Listener(8765) {

    # Returns a greeting for the given name.
    # 
    # + name - The name to greet
    # + return - A greeting message
    isolated remote function getGreeting(string name) returns string {
        return "Hello, " + name + "!";
    }
}

final mcp:StreamableHttpClient mcpClient = check new ("http://localhost:8765/mcp");
final mcp:Implementation clientInfo = {name: "test-client", version: "1.0.0"};

@test:Config
function testInlineListenerToolDiscovery() returns error? {
    check mcpClient->initialize(clientInfo);
    mcp:ListToolsResult result = check mcpClient->listTools();

    test:assertEquals(result.tools.length(), 1,
        msg = "Expected 1 tool — compiler plugin must have processed the inline-listener service");
    test:assertEquals(result.tools[0].name, "getGreeting");
}

@test:Config {dependsOn: [testInlineListenerToolDiscovery]}
function testInlineListenerToolSchema() returns error? {
    mcp:ListToolsResult result = check mcpClient->listTools();

    var inputSchema = result.tools[0].inputSchema;
    test:assertEquals(inputSchema.'type, "object");
    map<record {}> properties = check inputSchema.properties.ensureType();
    test:assertTrue(properties.hasKey("name"),
        msg = "Schema must include the 'name' parameter — compiler plugin generates the schema");
}

@test:Config {dependsOn: [testInlineListenerToolDiscovery]}
function testInlineListenerCallTool() returns error? {
    mcp:CallToolResult result = check mcpClient->callTool({name: "getGreeting", arguments: {"name": "World"}});

    test:assertFalse(result.isError ?: false);
    mcp:TextContent textContent = check result.content[0].ensureType();
    test:assertEquals(textContent.text, "Hello, World!");
}

listener mcp:Listener ln = check new (8766);

@mcp:ServiceConfig {
    info: {name: "inline-listener-test-server-2", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:Service /mcp on ln {

    # Returns a greeting for the given name.
    # 
    # + name - The name to greet
    # + return - A greeting message
    isolated remote function getGreetingStr(string name) returns string {
        return "Hello, " + name + "!";
    }
}

final mcp:StreamableHttpClient mcpClient2 = check new ("http://localhost:8766/mcp");
final mcp:Implementation clientInfo2 = {name: "test-client-2", version: "1.0.0"};

@test:Config
function testListenerDeclToolDiscovery() returns error? {
    check mcpClient2->initialize(clientInfo2);
    mcp:ListToolsResult result = check mcpClient2->listTools();

    test:assertEquals(result.tools.length(), 1,
        msg = "Expected 1 tool — compiler plugin must have processed the declared-listener service");
    test:assertEquals(result.tools[0].name, "getGreetingStr");
}
