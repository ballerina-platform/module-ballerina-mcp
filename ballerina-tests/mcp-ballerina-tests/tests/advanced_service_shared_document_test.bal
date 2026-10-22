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

// Regression coverage: the source modifier rewrites every service declaration in a document that
// contains tools, and used to re-emit only registered '@mcp:Tool' methods -- silently dropping an
// advanced service's 'onListTools'/'onCallTool' when it shared a document with a tool-bearing basic
// service. Because 'mcp:StreamableHttpAdvancedService' is an empty object type (its method shapes
// are validated by the compiler plugin in the analysis phase, before the modifier runs), the drop
// produced no diagnostic and only failed at runtime.
//
// These two services MUST stay in the same document for this test to be meaningful.

import ballerina/http;
import ballerina/mcp;
import ballerina/test;

// The tool-bearing basic service. Its presence is what makes the modifier rewrite this document.
@mcp:StreamableHttpServiceConfig {
    info: {name: "shared-doc-basic", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:StreamableHttpService /sharedBasic on new mcp:StreamableHttpListener(8774) {
    isolated remote function greet(string name) returns string => "hello " + name;
}

// The advanced service sharing the document above.
@mcp:StreamableHttpServiceConfig {
    info: {name: "shared-doc-advanced", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:StreamableHttpAdvancedService /sharedAdvanced on new mcp:StreamableHttpListener(8775) {
    isolated remote function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {
            tools: [{name: "sharedDocTool", description: "declared by onListTools", inputSchema: {'type: "object"}}]
        };
    }

    isolated remote function onCallTool(mcp:CallToolParams params, mcp:Session? session)
            returns mcp:CallToolResult|mcp:ServerError {
        return {content: [{'type: "text", text: "shared-doc-ok"}]};
    }
}

final http:Client sharedDocClient = check new ("http://localhost:8775");
final http:Client sharedDocBasicClient = check new ("http://localhost:8774");

@test:Config
function testAdvancedServiceOnListToolsSurvivesSharedDocument() returns error? {
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 1, method: "tools/list", params: {}});
    request.setHeader("Accept", "application/json, text/event-stream");
    http:Response response = check sharedDocClient->post("/sharedAdvanced", request);
    json result = check response.getJsonPayload();
    json[] tools = check (check result.result.tools).ensureType();
    test:assertEquals(tools.length(), 1);
    test:assertEquals(check tools[0].name, "sharedDocTool");
}

@test:Config
function testAdvancedServiceOnCallToolSurvivesSharedDocument() returns error? {
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 2, method: "tools/call",
        params: {name: "sharedDocTool", arguments: {}}});
    request.setHeader("Accept", "application/json, text/event-stream");
    http:Response response = check sharedDocClient->post("/sharedAdvanced", request);
    json result = check response.getJsonPayload();
    test:assertEquals(check getRawTextResult(result), "shared-doc-ok");
}

@test:Config
function testBasicServiceToolStillWorksInSharedDocument() returns error? {
    // The co-located basic service must keep working: the modifier still has to annotate its tools.
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 3, method: "tools/list", params: {}});
    request.setHeader("Accept", "application/json, text/event-stream");
    http:Response response = check sharedDocBasicClient->post("/sharedBasic", request);
    json result = check response.getJsonPayload();
    json[] tools = check (check result.result.tools).ensureType();
    test:assertEquals(tools.length(), 1);
    test:assertEquals(check tools[0].name, "greet");
}

@test:Config
function testBasicServiceToolInvocationStillWorksInSharedDocument() returns error? {
    // Listing the tool is not enough: the rewritten method must remain callable.
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 4, method: "tools/call",
        params: {name: "greet", arguments: {name: "shared"}}});
    request.setHeader("Accept", "application/json, text/event-stream");
    http:Response response = check sharedDocBasicClient->post("/sharedBasic", request);
    json result = check response.getJsonPayload();
    test:assertEquals(check getRawTextResult(result), "hello shared");
}
