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
import ballerina/jwt;
import ballerina/mcp;
import ballerina/test;

const AUTH_PLUGIN_SECRET = "auth-plugin-test-secret-0123456789abcdef";
const AUTH_PLUGIN_ISSUER = "https://idp.example.com";
const AUTH_PLUGIN_RESOURCE = "http://localhost:8792/mcp";

// The tools rely on the compiler plugin for their schemas, which must leave out the injected
// `mcp:AuthContext` parameter and keep the `scopes` declared on `@mcp:Tool`.
@mcp:StreamableHttpServiceConfig {
    info: {name: "auth-plugin-test-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS,
    httpConfig: {
        auth: {
            'resource: AUTH_PLUGIN_RESOURCE,
            authorizationServers: [
                {issuer: AUTH_PLUGIN_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: AUTH_PLUGIN_SECRET}}}}
            ]
        }
    }
}
isolated service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(8792) {

    @mcp:Tool {description: "Greets the caller"}
    isolated remote function greet(mcp:AuthContext auth, string greeting) returns string {
        return greeting + ", " + (auth.subject ?: "anonymous");
    }

    # Deletes a file.
    #
    # + path - Path of the file
    # + return - A confirmation
    @mcp:Tool {scopes: ["files:write"]}
    isolated remote function deleteFile(string path) returns string {
        return "deleted " + path;
    }
}

final http:Client authPluginClient = check new ("http://localhost:8792");

isolated function authPluginPost(string method, json params, string scope) returns http:Response|error {
    string token = check jwt:issue({
        issuer: AUTH_PLUGIN_ISSUER,
        username: "alice",
        audience: AUTH_PLUGIN_RESOURCE,
        customClaims: {scope},
        signatureConfig: {algorithm: jwt:HS256, config: AUTH_PLUGIN_SECRET}
    });
    return authPluginClient->post("/mcp", {jsonrpc: "2.0", id: 1, method, params}, headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "MCP-Protocol-Version": "2025-11-25",
        "Authorization": "Bearer " + token
    });
}

@test:Config {}
function testGeneratedSchemaOmitsAuthContext() returns error? {
    http:Response response = check authPluginPost("tools/list", {}, "");
    test:assertEquals(response.statusCode, 200);
    json payload = check response.getJsonPayload();
    json[] tools = check (check payload.result.tools).ensureType();
    foreach json tool in tools {
        map<json> toolDefinition = check tool.ensureType();
        test:assertFalse(toolDefinition.hasKey("scopes"), toolDefinition.toJsonString());
        if toolDefinition["name"] == "greet" {
            map<json> properties = check (check tool.inputSchema.properties).ensureType();
            test:assertEquals(properties.keys(), ["greeting"]);
        }
    }

    http:Response greeted = check authPluginPost("tools/call", {name: "greet", arguments: {greeting: "Hi"}}, "");
    test:assertEquals(greeted.statusCode, 200);
    json greetedPayload = check greeted.getJsonPayload();
    test:assertEquals(check greetedPayload.result.content, [{"type": "text", "text": "Hi, alice"}]);
}

@test:Config {}
function testToolScopesSurviveAnnotationGeneration() returns error? {
    http:Response denied = check authPluginPost("tools/call", {name: "deleteFile", arguments: {path: "a"}}, "");
    test:assertEquals(denied.statusCode, 403);
    string challenge = check denied.getHeader("WWW-Authenticate");
    test:assertTrue(challenge.includes("scope=\"files:write\""), challenge);

    http:Response allowed = check authPluginPost("tools/call", {name: "deleteFile", arguments: {path: "a"}},
            "files:write");
    test:assertEquals(allowed.statusCode, 200);
}
