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

enum TestApiVersion {
    TV1 = "v1",
    TV2 = "v2"
}

type TestCallerHeaders record {|
    string authorization;
    @http:Header {name: "X-Tenant-Id"}
    string tenantId?;
|};

@mcp:StreamableHttpServiceConfig {
    info: {name: "header-binding-test-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(8772) {

    @mcp:Tool {description: "Binds the authorization header by parameter name"}
    isolated remote function readAuth(@http:Header string authorization, string name) returns string {
        return name + ":" + authorization;
    }

    @mcp:Tool {description: "Binds a named nilable header"}
    isolated remote function readTenant(@http:Header {name: "X-Tenant-Id"} string? tenant) returns string {
        return tenant ?: "<none>";
    }

    @mcp:Tool {description: "Binds typed headers"}
    isolated remote function readTyped(@http:Header {name: "X-Retry-Count"} int retries,
            @http:Header {name: "X-Debug"} boolean debug) returns string {
        return retries.toString() + ":" + debug.toString();
    }

    @mcp:Tool {description: "Binds an enum header"}
    isolated remote function readVersion(@http:Header {name: "X-Ver"} TestApiVersion ver) returns string {
        return ver;
    }

    @mcp:Tool {description: "Binds a readonly header array"}
    isolated remote function readTags(@http:Header {name: "X-Tag"} readonly & string[] tags) returns string {
        return string:'join(",", ...tags);
    }

    @mcp:Tool {description: "Binds a record of headers"}
    isolated remote function readRecord(@http:Header TestCallerHeaders hdrs) returns string {
        return hdrs.authorization + ":" + (hdrs.tenantId ?: "<none>");
    }

    @mcp:Tool {description: "Reads the raw http:Headers object"}
    isolated remote function readRaw(http:Headers headers) returns string {
        string|http:HeaderNotFoundError auth = headers.getHeader("authorization");
        return auth is string ? auth : "<none>";
    }

    @mcp:Tool {description: "Reads a header via the raw http:Request object"}
    isolated remote function readViaRequest(http:Request request, string name) returns string {
        string|http:HeaderNotFoundError auth = request.getHeader("authorization");
        return name + ":" + (auth is string ? auth : "<none>");
    }
}

@mcp:StreamableHttpServiceConfig {
    info: {name: "strict-header-binding-test-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS,
    httpConfig: {treatNilableAsOptional: false}
}
isolated service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(8773) {

    @mcp:Tool {description: "Nilable header under treatNilableAsOptional: false"}
    isolated remote function readStrictTenant(@http:Header {name: "X-Tenant-Id"} string? tenant) returns string {
        return tenant ?: "<none>";
    }
}

final mcp:StreamableHttpClient headerClient = check new ("http://localhost:8772/mcp");
final mcp:StreamableHttpClient strictHeaderClient = check new ("http://localhost:8773/mcp");

// Raw JSON-RPC client: the mcp client discards the JSON-RPC error payload of
// non-2xx responses and cannot send string[] header values, so error-path and
// multi-value-header tests go through plain http.
final http:Client rawHeaderClient = check new ("http://localhost:8772");
final http:Client rawStrictHeaderClient = check new ("http://localhost:8773");

isolated function getTextResult(mcp:CallToolResult result) returns string|error {
    mcp:TextContent textContent = check result.content[0].ensureType();
    return textContent.text;
}

isolated function rawCallTool(http:Client rawClient, string toolName,
        map<string|string[]> headers) returns json|error {
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 1, method: "tools/call",
        params: {name: toolName, arguments: {}}});
    request.setHeader("Accept", "application/json, text/event-stream");
    foreach var [headerName, value] in headers.entries() {
        if value is string {
            request.setHeader(headerName, value);
        } else {
            foreach string headerValue in value {
                request.addHeader(headerName, headerValue);
            }
        }
    }
    http:Response response = check rawClient->post("/mcp", request);
    return response.getJsonPayload();
}

isolated function getRawErrorMessage(json payload) returns string|error {
    json message = check payload.'error.message;
    return message.toString();
}

isolated function getRawErrorCode(json payload) returns int|error {
    json code = check payload.'error.code;
    return code.ensureType();
}

isolated function getRawTextResult(json payload) returns string|error {
    json[] content = check (check payload.result.content).ensureType();
    json text = check content[0].text;
    return text.toString();
}

@test:Config
function testHeaderBindingClientInit() returns error? {
    check headerClient->initialize({name: "header-test-client", version: "1.0.0"});
    check strictHeaderClient->initialize({name: "strict-header-test-client", version: "1.0.0"});
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testHeaderParamsExcludedFromSchema() returns error? {
    mcp:ListToolsResult result = check headerClient->listTools();

    foreach mcp:ToolDefinition tool in result.tools {
        if tool.name != "readAuth" {
            continue;
        }
        map<record {}> properties = check tool.inputSchema.properties.ensureType();
        test:assertTrue(properties.hasKey("name"), msg = "tool argument must stay in the schema");
        test:assertFalse(properties.hasKey("authorization"),
            msg = "@http:Header parameter must be excluded from the tool input schema");
        return;
    }
    test:assertFail("readAuth tool not found in tools/list");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testSingleHeaderBinding() returns error? {
    mcp:CallToolResult result = check headerClient->callTool(
        {name: "readAuth", arguments: {"name": "World"}},
        {"authorization": "Bearer test-token"});
    test:assertEquals(check getTextResult(result), "World:Bearer test-token");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testMissingRequiredHeader() returns error? {
    json payload = check rawCallTool(rawHeaderClient, "readAuth", {});
    string message = check getRawErrorMessage(payload);
    test:assertTrue(message.includes("no header value found for 'authorization'"),
        msg = "unexpected error: " + message);
    test:assertEquals(check getRawErrorCode(payload), -32602,
        msg = "binding failures must be reported as invalid params");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testNilableHeaderPresentAndMissing() returns error? {
    mcp:CallToolResult withHeader = check headerClient->callTool(
        {name: "readTenant", arguments: {}}, {"X-Tenant-Id": "tenant-42"});
    test:assertEquals(check getTextResult(withHeader), "tenant-42");

    mcp:CallToolResult withoutHeader = check headerClient->callTool({name: "readTenant", arguments: {}});
    test:assertEquals(check getTextResult(withoutHeader), "<none>");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testTypedHeaderBinding() returns error? {
    mcp:CallToolResult result = check headerClient->callTool(
        {name: "readTyped", arguments: {}},
        {"X-Retry-Count": "3", "X-Debug": "true"});
    test:assertEquals(check getTextResult(result), "3:true");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testTypedHeaderCastFailure() returns error? {
    json payload = check rawCallTool(rawHeaderClient, "readTyped",
        {"X-Retry-Count": "not-a-number", "X-Debug": "true"});
    string message = check getRawErrorMessage(payload);
    test:assertTrue(message.includes("header binding failed for parameter 'X-Retry-Count'"),
        msg = "unexpected error: " + message);
    test:assertEquals(check getRawErrorCode(payload), -32602,
        msg = "binding failures must be reported as invalid params");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testEnumHeaderBinding() returns error? {
    mcp:CallToolResult valid = check headerClient->callTool(
        {name: "readVersion", arguments: {}}, {"X-Ver": "v2"});
    test:assertEquals(check getTextResult(valid), "v2");

    json invalid = check rawCallTool(rawHeaderClient, "readVersion", {"X-Ver": "v9"});
    string message = check getRawErrorMessage(invalid);
    test:assertTrue(message.includes("header binding failed for parameter 'X-Ver'"),
        msg = "unexpected error: " + message);
    test:assertEquals(check getRawErrorCode(invalid), -32602,
        msg = "binding failures must be reported as invalid params");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testReadonlyArrayHeaderBinding() returns error? {
    json payload = check rawCallTool(rawHeaderClient, "readTags", {"X-Tag": ["alpha", "beta"]});
    test:assertEquals(check getRawTextResult(payload), "alpha,beta");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testHeaderRecordBinding() returns error? {
    mcp:CallToolResult full = check headerClient->callTool(
        {name: "readRecord", arguments: {}},
        {"authorization": "Bearer rec-token", "X-Tenant-Id": "tenant-7"});
    test:assertEquals(check getTextResult(full), "Bearer rec-token:tenant-7");

    mcp:CallToolResult partial = check headerClient->callTool(
        {name: "readRecord", arguments: {}}, {"authorization": "Bearer rec-token"});
    test:assertEquals(check getTextResult(partial), "Bearer rec-token:<none>");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testRawHeadersParamBinding() returns error? {
    mcp:CallToolResult result = check headerClient->callTool(
        {name: "readRaw", arguments: {}}, {"authorization": "Bearer raw-token"});
    test:assertEquals(check getTextResult(result), "Bearer raw-token");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testRequestParamBinding() returns error? {
    mcp:CallToolResult result = check headerClient->callTool(
        {name: "readViaRequest", arguments: {"name": "World"}}, {"authorization": "Bearer req-token"});
    test:assertEquals(check getTextResult(result), "World:Bearer req-token");
}

@test:Config {dependsOn: [testHeaderBindingClientInit]}
function testStrictNilableHeaderMissing() returns error? {
    json payload = check rawCallTool(rawStrictHeaderClient, "readStrictTenant", {});
    string message = check getRawErrorMessage(payload);
    test:assertTrue(message.includes("no header value found for 'X-Tenant-Id'"),
        msg = "unexpected error: " + message);
    test:assertEquals(check getRawErrorCode(payload), -32602,
        msg = "binding failures must be reported as invalid params");
}
