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

type CartItem record {|
    string name;
    int qty;
|};

@mcp:StreamableHttpServiceConfig {
    info: {name: "error-handling-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(8778) {

    @mcp:Tool {description: "Divides two numbers"}
    isolated remote function divide(int a, int b) returns int|error {
        if b == 0 {
            return error("division by zero: b must be non-zero");
        }
        return a / b;
    }

    @mcp:Tool {description: "Panics with an index out of range"}
    isolated remote function panicking() returns int {
        int[] empty = [];
        return empty[5];
    }

    @mcp:Tool {description: "Adds an item to the cart"}
    isolated remote function addItem(CartItem item, int count) returns string {
        return string `${item.name}:${item.qty}x${count}`;
    }
}

@mcp:StreamableHttpServiceConfig {
    info: {name: "advanced-error-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:StreamableHttpAdvancedService /mcp on new mcp:StreamableHttpListener(8779) {

    isolated remote function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: [{name: "ping", description: "Pings the server", inputSchema: {"type": "object"}}]};
    }

    isolated remote function onCallTool(mcp:CallToolParams params, mcp:Session? session)
            returns mcp:CallToolResult|mcp:ServerError {
        if params.name == "failing" {
            return error mcp:ServerError("upstream API returned 503");
        }
        return {content: [{'type: "text", text: "Invalid date: must be in the future"}], isError: true};
    }
}

@mcp:StreamableHttpServiceConfig {
    info: {name: "stateful-error-server", version: "1.0.0"},
    sessionMode: mcp:STATEFUL
}
isolated service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(8780) {

    @mcp:Tool {description: "Returns a greeting"}
    isolated remote function greet() returns string => "hello";
}

final http:Client errorHandlingClient = check new ("http://localhost:8778");
final http:Client advancedErrorClient = check new ("http://localhost:8779");
final http:Client statefulErrorClient = check new ("http://localhost:8780");

isolated function callTool(http:Client clientEndpoint, string name, map<json> arguments = {})
        returns http:Response|error {
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 1, method: "tools/call", params: {name, arguments}});
    request.setHeader("Accept", "application/json, text/event-stream");
    return clientEndpoint->post("/mcp", request);
}

isolated function getToolError(json payload) returns [boolean, string]|error {
    boolean isError = check (check payload.result.isError).ensureType();
    return [isError, check getRawTextResult(payload)];
}

@test:Config
function testToolReturningErrorIsReportedAsToolExecutionError() returns error? {
    http:Response response = check callTool(errorHandlingClient, "divide", {a: 10, b: 0});
    test:assertEquals(response.statusCode, http:STATUS_OK);
    [boolean, string] [isError, message] = check getToolError(check response.getJsonPayload());
    test:assertTrue(isError);
    test:assertEquals(message, "division by zero: b must be non-zero");
}

@test:Config
function testPanickingToolIsReportedAsToolExecutionError() returns error? {
    http:Response response = check callTool(errorHandlingClient, "panicking");
    test:assertEquals(response.statusCode, http:STATUS_OK);
    [boolean, string] [isError, message] = check getToolError(check response.getJsonPayload());
    test:assertTrue(isError);
    test:assertEquals(message, "array index out of range: index: 5, size: 0");
}

@test:Config {dependsOn: [testPanickingToolIsReportedAsToolExecutionError]}
function testServiceSurvivesPanickingTool() returns error? {
    http:Response response = check callTool(errorHandlingClient, "divide", {a: 10, b: 2});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "5");
}

@test:Config
function testUnknownToolIsReportedAsToolExecutionError() returns error? {
    http:Response response = check callTool(errorHandlingClient, "noSuchTool");
    test:assertEquals(response.statusCode, http:STATUS_OK);
    [boolean, string] [isError, message] = check getToolError(check response.getJsonPayload());
    test:assertTrue(isError);
    test:assertEquals(message, "Unknown tool: noSuchTool");
}

@test:Config
function testMissingRequiredArgument() returns error? {
    http:Response response = check callTool(errorHandlingClient, "divide", {a: 10});
    test:assertEquals(response.statusCode, http:STATUS_OK);
    [boolean, string] [isError, message] = check getToolError(check response.getJsonPayload());
    test:assertTrue(isError);
    test:assertEquals(message, "missing required argument 'b'");
}

@test:Config
function testWrongTypedArgument() returns error? {
    http:Response response = check callTool(errorHandlingClient, "divide", {a: "ten", b: 2});
    test:assertEquals(response.statusCode, http:STATUS_OK);
    [boolean, string] [isError, message] = check getToolError(check response.getJsonPayload());
    test:assertTrue(isError);
    test:assertTrue(message.startsWith("invalid value for argument 'a'"), message);
}

@test:Config
function testNestedRecordArgumentMissingField() returns error? {
    http:Response response = check callTool(errorHandlingClient, "addItem", {item: {name: "pen"}, count: 3});
    test:assertEquals(response.statusCode, http:STATUS_OK);
    [boolean, string] [isError, message] = check getToolError(check response.getJsonPayload());
    test:assertTrue(isError);
    test:assertTrue(message.startsWith("invalid value for argument 'item'"), message);
}

@test:Config
function testValidNestedRecordArgument() returns error? {
    http:Response response = check callTool(errorHandlingClient, "addItem",
            {item: {name: "pen", qty: 2}, count: 3});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "pen:2x3");
}

@test:Config
function testAdvancedServiceServerErrorStaysProtocolError() returns error? {
    http:Response response = check callTool(advancedErrorClient, "failing");
    test:assertEquals(response.statusCode, http:STATUS_OK);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, mcp:INTERNAL_ERROR);
    test:assertEquals(check payload.'error.message,
            "Failed to call tool 'failing': upstream API returned 503");
}

@test:Config
function testAdvancedServiceIsErrorResultIsPreserved() returns error? {
    http:Response response = check callTool(advancedErrorClient, "ping");
    [boolean, string] [isError, message] = check getToolError(check response.getJsonPayload());
    test:assertTrue(isError);
    test:assertEquals(message, "Invalid date: must be in the future");
}

@test:Config
function testUnknownMethodReturnsMethodNotFoundWithOkStatus() returns error? {
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 1, method: "resources/list", params: {}});
    request.setHeader("Accept", "application/json, text/event-stream");
    http:Response response = check errorHandlingClient->post("/mcp", request);
    test:assertEquals(response.statusCode, http:STATUS_OK);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, mcp:METHOD_NOT_FOUND);
}

@test:Config
function testMalformedJsonBodyReturnsParseError() returns error? {
    http:Request request = new;
    request.setTextPayload("{\"jsonrpc\":\"2.0\",\"id\":1,");
    request.setHeader("Content-Type", "application/json");
    request.setHeader("Accept", "application/json, text/event-stream");
    http:Response response = check errorHandlingClient->post("/mcp", request);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, mcp:PARSE_ERROR);
}

@test:Config
function testNonJsonRpcBodyReturnsInvalidRequest() returns error? {
    http:Request request = new;
    request.setJsonPayload({foo: "bar"});
    request.setHeader("Accept", "application/json, text/event-stream");
    http:Response response = check errorHandlingClient->post("/mcp", request);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, mcp:INVALID_REQUEST);
    test:assertEquals(check payload.'error.message, "Invalid Request: not a valid JSON-RPC message");
}

@test:Config
function testUnknownSessionReturnsNotFound() returns error? {
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 1, method: "tools/list", params: {}});
    request.setHeader("Accept", "application/json, text/event-stream");
    request.setHeader("mcp-session-id", "00000000-0000-0000-0000-000000000000");
    http:Response response = check statefulErrorClient->post("/mcp", request);
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
    json payload = check response.getJsonPayload();
    test:assertEquals(check payload.'error.code, mcp:INVALID_REQUEST);
}

@test:Config
function testDeleteWithUnknownSessionReturnsNotFound() returns error? {
    http:Request request = new;
    request.setHeader("mcp-session-id", "00000000-0000-0000-0000-000000000000");
    http:Response response = check statefulErrorClient->delete("/mcp", request);
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
}
