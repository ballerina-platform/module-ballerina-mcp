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

listener mcp:Listener metaListener = check new (8767);

@mcp:ServiceConfig {
    info: {name: "meta-test-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:Service /mcp on metaListener {

    # Greets the caller, echoing the request's trace id when client metadata is supplied.
    #
    # + name - The name to greet
    # + meta - Optional request metadata injected by the framework
    # + greeting - Greeting to prepend to the name
    # + return - A greeting message that reflects whether metadata was received
    isolated remote function greetWithMeta(string name, mcp:Meta? meta, string greeting) returns string {
        if meta is mcp:Meta {
            anydata traceId = meta["traceId"];
            return string `${greeting}, ${name}! trace=${traceId.toString()}`;
        }
        return string `${greeting}, ${name}! no-meta`;
    }
}

final mcp:StreamableHttpClient metaClient = check new ("http://localhost:8767/mcp");
final mcp:Implementation metaClientInfo = {name: "meta-test-client", version: "1.0.0"};

@test:Config
function testMetaToolSchemaExcludesMetaParam() returns error? {
    check metaClient->initialize(metaClientInfo);
    mcp:ListToolsResult result = check metaClient->listTools();

    test:assertEquals(result.tools.length(), 1);
    test:assertEquals(result.tools[0].name, "greetWithMeta");

    var inputSchema = result.tools[0].inputSchema;
    map<record {}> properties = check inputSchema.properties.ensureType();
    test:assertTrue(properties.hasKey("name"),
        msg = "Schema must include the 'name' data parameter");
    test:assertTrue(properties.hasKey("greeting"),
        msg = "Schema must include data parameters declared after mcp:Meta");
    test:assertFalse(properties.hasKey("meta"),
        msg = "The injected mcp:Meta parameter must not appear in the tool input schema");
}

@test:Config {dependsOn: [testMetaToolSchemaExcludesMetaParam]}
function testMetaReceivedOnServer() returns error? {
    mcp:CallToolResult result = check metaClient->callTool({
        name: "greetWithMeta",
        arguments: {"name": "World", "greeting": "Hello"},
        _meta: {"traceId": "trace-xyz"}
    });

    // The server-side tool reads the injected client _meta via the mcp:Meta parameter
    // and reflects it in the result text.
    mcp:TextContent textContent = check result.content[0].ensureType();
    test:assertEquals(textContent.text, "Hello, World! trace=trace-xyz",
        msg = "Server must access the client-supplied _meta via the mcp:Meta parameter");

    // The request _meta must not be auto-echoed onto the result (not mandated by the MCP spec).
    test:assertTrue(result._meta is (),
        msg = "Request _meta must not be echoed back onto the response");
}

@test:Config {dependsOn: [testMetaToolSchemaExcludesMetaParam]}
function testMetaIsNilWhenClientOmitsIt() returns error? {
    mcp:CallToolResult result = check metaClient->callTool({
        name: "greetWithMeta",
        arguments: {"name": "World", "greeting": "Hello"}
    });

    mcp:TextContent textContent = check result.content[0].ensureType();
    test:assertEquals(textContent.text, "Hello, World! no-meta",
        msg = "Tool must observe a nil mcp:Meta when the client sends no _meta");
}
