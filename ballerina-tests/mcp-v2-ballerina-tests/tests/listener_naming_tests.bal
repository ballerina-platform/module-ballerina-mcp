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
import ballerina/mcp.v2 as mcpv2;
import ballerina/test;

// Streamable HTTP service configured through the transport-specific
// @mcpv2:StreamableHttpServiceConfig annotation; header binding is allowed here.
@mcpv2:StreamableHttpServiceConfig {
    info: {name: "transport-named-listener-server", version: "1.0.0"},
    sessionMode: mcpv2:STATELESS,
    httpConfig: {treatNilableAsOptional: false}
}
isolated service mcpv2:StreamableHttpService /mcp on new mcpv2:StreamableHttpListener(8769) {

    @mcpv2:Tool {description: "Header binding on the Streamable HTTP service"}
    isolated remote function greet(@http:Header string authorization, string name) returns string {
        return name + ":" + authorization;
    }

    @mcpv2:Tool {description: "Nilable header under strict mode set via @mcpv2:StreamableHttpServiceConfig"}
    isolated remote function tenant(@http:Header {name: "X-Tenant-Id"} string? tenant) returns string {
        return tenant ?: "<none>";
    }
}

@mcpv2:StreamableHttpServiceConfig {
    info: {name: "transport-config-precedence-server", version: "1.0.0"},
    sessionMode: mcpv2:STATELESS
}
isolated service mcpv2:StreamableHttpService /mcp on new mcpv2:StreamableHttpListener(8791) {

    @mcpv2:Tool {description: "Returns a fixed value"}
    isolated remote function echo() returns string {
        return "ok";
    }
}

final http:Client rawTransportClient = check new ("http://localhost:8769");
final http:Client rawPrecedenceClient = check new ("http://localhost:8791");

@test:Config
function testHeaderBindingOnStreamableHttpListener() returns error? {
    http:Request request = new;
    request.setJsonPayload({jsonrpc: "2.0", id: 1, method: "tools/call",
        params: {name: "greet", arguments: {"name": "World"}}});
    request.setHeader("Accept", "application/json, text/event-stream");
    request.setHeader("authorization", "Bearer shl-token");
    http:Response response = check rawTransportClient->post("/mcp", request);
    json result = check response.getJsonPayload();
    test:assertEquals(check getRawTextResult(result), "World:Bearer shl-token");
}

@test:Config
function testStrictModeViaTransportConfigAnnotation() returns error? {
    // treatNilableAsOptional=false comes from @mcpv2:StreamableHttpServiceConfig.httpConfig:
    // a missing nilable header must be rejected as invalid params
    json payload = check rawCallTool(rawTransportClient, "tenant", {});
    string message = check getRawErrorMessage(payload);
    test:assertTrue(message.includes("no header value found for 'X-Tenant-Id'"),
        msg = "unexpected error: " + message);
    test:assertEquals(check getRawErrorCode(payload), -32602);

    json withHeader = check rawCallTool(rawTransportClient, "tenant", {"X-Tenant-Id": "t-1"});
    test:assertEquals(check getRawTextResult(withHeader), "t-1");
}

@test:Config
function testTransportConfigSessionMode() returns error? {
    // No initialize handshake and no mcp-session-id header: only works if the effective
    // session mode is STATELESS as configured by @mcpv2:StreamableHttpServiceConfig.
    json payload = check rawCallTool(rawPrecedenceClient, "echo", {});
    json|error errorField = payload.'error;
    if errorField is json {
        test:assertFail("expected STATELESS behavior from @mcpv2:StreamableHttpServiceConfig, got: "
            + errorField.toString());
    }
    test:assertEquals(check getRawTextResult(payload), "ok");
}
