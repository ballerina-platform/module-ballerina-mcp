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

// Regression coverage: the source modifier used to rewrite EVERY service declaration in a document
// that contains mcp tools -- including services that have nothing to do with mcp. A plain
// 'http:Service' sharing a document with an mcp tool had its non-resource methods dropped, so this
// document failed to compile with "undefined method 'helper'". Resource methods survived only
// incidentally, because their syntax kind is not OBJECT_METHOD_DEFINITION.
//
// The modifier now skips any service that is not an mcp basic service. The plain http:Service below
// MUST stay in the same document as the mcp service for this test to be meaningful.

import ballerina/http;
import ballerina/mcp;
import ballerina/test;

// A plain http:Service -- not an mcp service at all.
service /plain on new http:Listener(8776) {
    resource function get ping() returns string => self.buildPong();

    resource function post echo(@http:Payload string body) returns string => self.decorate(body);

    // Non-resource object methods: these are what used to be dropped.
    function buildPong() returns string => "pong";

    function decorate(string body) returns string => "echo:" + body;
}

// The mcp tool-bearing service that causes this document to be rewritten.
@mcp:StreamableHttpServiceConfig {
    info: {name: "mixed-doc", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:StreamableHttpService /mixedMcp on new mcp:StreamableHttpListener(8777) {
    isolated remote function greet(string name) returns string => "hello " + name;
}

final http:Client plainClient = check new ("http://localhost:8776");
final http:Client mixedMcpClient = check new ("http://localhost:8777");

@test:Config
function testPlainHttpServiceMethodsSurviveSharedDocument() returns error? {
    // Both resource methods delegate to non-resource helpers. If the helpers were dropped this
    // document would not compile at all; if they were mangled these calls would fail.
    string ping = check plainClient->get("/plain/ping");
    test:assertEquals(ping, "pong");

    string echo = check plainClient->post("/plain/echo", "hi");
    test:assertEquals(echo, "echo:hi");
}

@test:Config
function testMcpToolStillWorksAlongsidePlainHttpService() returns error? {
    // The mcp service in the same document must still be rewritten correctly.
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 1, method: "tools/call",
        params: {name: "greet", arguments: {name: "mixed"}}});
    request.setHeader("Accept", "application/json, text/event-stream");
    http:Response response = check mixedMcpClient->post("/mixedMcp", request);
    json result = check response.getJsonPayload();
    test:assertEquals(check getRawTextResult(result), "hello mixed");
}

@test:Config
function testMcpToolIsListedAlongsidePlainHttpService() returns error? {
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 2, method: "tools/list", params: {}});
    request.setHeader("Accept", "application/json, text/event-stream");
    http:Response response = check mixedMcpClient->post("/mixedMcp", request);
    json result = check response.getJsonPayload();
    json[] tools = check (check result.result.tools).ensureType();
    test:assertEquals(tools.length(), 1);
    test:assertEquals(check tools[0].name, "greet");
}
