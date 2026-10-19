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
import ballerina/test;
import ballerina/uuid;

// Signing and client keys are generated per run, so that no key is kept in source.
final string SIGNING_KEY = uuid:createType4AsString() + uuid:createType4AsString();
const PROTECTED_ISSUER = "https://idp.example.com";
const PROTECTED_RESOURCE = "http://localhost:3235/mcp";
const PROTECTED_ADVANCED_RESOURCE = "http://localhost:3235/advanced";
const SESSION_REQUIRED_RESOURCE = "http://localhost:3235/sessionRequired";
const STATEFUL_RESOURCE = "http://localhost:3235/stateful";
const PROTECTED_METADATA_URL = "http://localhost:3235/.well-known/oauth-protected-resource/mcp";

listener StreamableHttpListener serverAuthListener = check new (3235);

@StreamableHttpConfig {
    info: {name: "protected", version: "1"},
    httpConfig: {
        auth: {
            'resource: PROTECTED_RESOURCE,
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ],
            requiredScopes: ["mcp:tools"],
            resourceName: "Protected test server"
        }
    }
}
service StreamableHttpService /mcp on serverAuthListener {
    @Tool {description: "Returns the caller", schema: {'type: "object"}}
    remote isolated function whoami(AuthContext auth) returns string => auth.subject ?: "";

    @Tool {
        description: "Deletes a file",
        schema: {'type: "object", properties: {path: {'type: "string"}}, required: ["path"]},
        scopes: ["files:write"]
    }
    remote isolated function deleteFile(string path) returns string => "deleted " + path;

    @Tool {description: "Decides at runtime that it needs the admin scope", schema: {'type: "object"}}
    remote isolated function adminReport(AuthContext auth) returns string|InsufficientScopeError {
        if auth.scopes.indexOf("admin") is () {
            return error InsufficientScopeError("The admin scope is required", scopes = ["admin"]);
        }
        return "report";
    }
}

@StreamableHttpConfig {
    info: {name: "protected-advanced", version: "1"},
    httpConfig: {
        auth: {
            'resource: PROTECTED_ADVANCED_RESOURCE,
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ]
        }
    }
}
service StreamableHttpAdvancedService /advanced on serverAuthListener {
    remote isolated function onListTools(AuthContext auth) returns ListToolsResult => {
        tools: [
            {name: "whoami", inputSchema: {'type: "object"}},
            {name: "admin", inputSchema: {'type: "object"}}
        ]
    };

    remote isolated function onCallTool(CallToolParams params, AuthContext auth)
            returns CallToolResult|InsufficientScopeError {
        if params.name == "admin" && auth.scopes.indexOf("admin") is () {
            return error InsufficientScopeError("The admin scope is required", scopes = ["admin"]);
        }
        return {content: [{'type: "text", text: auth.subject ?: ""}]};
    }
}

@StreamableHttpConfig {
    info: {name: "protected-listing", version: "1"},
    httpConfig: {
        auth: {
            'resource: "http://localhost:3235/listing",
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ],
            requiredScopes: ["mcp:tools"]
        }
    }
}
service StreamableHttpAdvancedService /listing on serverAuthListener {
    remote isolated function onListTools(AuthContext auth) returns ListToolsResult|InsufficientScopeError {
        if auth.scopes.indexOf("tools:list") is () {
            return error InsufficientScopeError("Listing tools requires the tools:list scope", scopes = ["tools:list"]);
        }
        return {tools: [{name: "echo", inputSchema: {'type: "object"}}]};
    }

    remote isolated function onCallTool(CallToolParams params) returns CallToolResult =>
        {content: [{'type: "text", text: params.name}]};
}

@StreamableHttpConfig {
    info: {name: "protected-session-required", version: "1"},
    httpConfig: {
        auth: {
            'resource: SESSION_REQUIRED_RESOURCE,
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ]
        }
    }
}
service StreamableHttpService /sessionRequired on serverAuthListener {
    @Tool {description: "Returns the required session ID", schema: {'type: "object"}}
    remote isolated function sessionId(HttpSession session) returns string => session.getSessionId();
}

@StreamableHttpConfig {
    info: {name: "protected-stateful", version: "1"},
    sessionMode: STATEFUL,
    httpConfig: {
        auth: {
            'resource: STATEFUL_RESOURCE,
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ]
        }
    }
}
service StreamableHttpService /stateful on serverAuthListener {
    @Tool {description: "Returns pong", schema: {'type: "object"}}
    remote isolated function ping() returns string => "pong";
}

final http:Client serverAuthClient = check new ("http://localhost:3235");

isolated function serverAuthToken(string scope = "mcp:tools", string subject = "alice",
        string audience = PROTECTED_RESOURCE, string secret = SIGNING_KEY) returns string|error =>
    jwt:issue({
        issuer: PROTECTED_ISSUER,
        username: subject,
        audience,
        customClaims: {scope},
        signatureConfig: {algorithm: jwt:HS256, config: secret}
    });

isolated function protectedModernPost(string servicePath, string methodName, RequestParams requestParams = {},
        string? token = ()) returns http:Response|error {
    requestParams._meta = {
        [PROTOCOL_META_KEY]: MODERN_PROTOCOL_VERSION,
        [CAPABILITIES_META_KEY]: {}
    };
    map<string|string[]> requestHeaders = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: MODERN_PROTOCOL_VERSION,
        [METHOD_HEADER]: methodName
    };
    anydata toolName = requestParams["name"];
    if toolName is string {
        requestHeaders[NAME_HEADER] = encodeProtocolHeader(toolName);
    }
    if token is string {
        requestHeaders[AUTHORIZATION_HEADER] = "Bearer " + token;
    }
    JsonRpcRequest requestMessage = {jsonrpc: JSONRPC_VERSION, id: 7, method: methodName, params: requestParams};
    return serverAuthClient->post(servicePath, requestMessage, headers = requestHeaders);
}

isolated function callProtectedTool(string toolName, string? token, string servicePath = "/mcp",
        map<json> arguments = {}) returns http:Response|error =>
    protectedModernPost(servicePath, REQUEST_CALL_TOOL, {"name": toolName, "arguments": arguments}, token);

isolated function challengeOf(http:Response response) returns string|error =>
    response.getHeader(WWW_AUTHENTICATE_HEADER);

isolated function textResult(http:Response response) returns string|error {
    json payload = check response.getJsonPayload();
    json[] content = check (check payload.result.content).ensureType();
    return (check content[0].text).ensureType();
}

@test:Config {}
function testRequestWithoutTokenIsChallenged() returns error? {
    http:Response response = check protectedModernPost("/mcp", REQUEST_LIST_TOOLS);
    test:assertEquals(response.statusCode, 401);
    string challenge = check challengeOf(response);
    test:assertTrue(challenge.startsWith("Bearer "), challenge);
    test:assertTrue(challenge.includes(string `resource_metadata="${PROTECTED_METADATA_URL}"`), challenge);
    test:assertTrue(challenge.includes("scope=\"mcp:tools\""), challenge);
    // RFC 6750 section 3.1: a request without credentials gets no error code.
    test:assertFalse(challenge.includes("error="), challenge);

    // Our own client parses the challenge it receives from our server.
    BearerChallenge? parsed = parseBearerChallenge(challenge);
    test:assertEquals(parsed?.resourceMetadata, PROTECTED_METADATA_URL);
    test:assertEquals(parsed?.scope, "mcp:tools");
}

@test:Config {}
function testProtectedResourceMetadataIsPublished() returns error? {
    json metadata = check serverAuthClient->get("/.well-known/oauth-protected-resource/mcp");
    test:assertEquals(metadata.'resource, PROTECTED_RESOURCE);
    test:assertEquals(metadata.authorization_servers, [PROTECTED_ISSUER]);
    test:assertEquals(metadata.bearer_methods_supported, ["header"]);
    test:assertEquals(metadata.resource_name, "Protected test server");
    // Defaults to the required scopes; tool scopes are requested through step-up challenges.
    test:assertEquals(metadata.scopes_supported, ["mcp:tools"]);

    json advancedMetadata = check serverAuthClient->get("/.well-known/oauth-protected-resource/advanced");
    test:assertEquals(advancedMetadata.'resource, PROTECTED_ADVANCED_RESOURCE);

    // A root document would have to describe the origin as a resource, so none is published.
    http:Response rootMetadata = check serverAuthClient->get("/.well-known/oauth-protected-resource");
    test:assertEquals(rootMetadata.statusCode, 404);
}

@test:Config {}
function testInvalidTokensAreRejected() returns error? {
    map<string> invalidTokens = {
        "wrong signature": check serverAuthToken(secret = uuid:createType4AsString()),
        "wrong audience": check serverAuthToken(audience = "http://localhost:3235/other"),
        "malformed": "not-a-jwt"
    };
    foreach [string, string] [label, token] in invalidTokens.entries() {
        http:Response response = check protectedModernPost("/mcp", REQUEST_LIST_TOOLS, token = token);
        test:assertEquals(response.statusCode, 401, label);
        test:assertTrue((check challengeOf(response)).includes("error=\"invalid_token\""), label);
    }

    // A malformed Authorization header is a bad request (RFC 6750 section 3.1).
    string token = check serverAuthToken();
    http:Response duplicated = check serverAuthClient->post("/mcp", {}, headers = {
        [AUTHORIZATION_HEADER]: ["Bearer " + token, "Bearer " + token]
    });
    test:assertEquals(duplicated.statusCode, 400);
    test:assertTrue((check challengeOf(duplicated)).includes("error=\"invalid_request\""));

    // Tokens are only accepted as a Bearer credential in the Authorization header.
    http:Response basic = check serverAuthClient->post("/mcp", {}, headers = {
        [AUTHORIZATION_HEADER]: "Basic YWxpY2U6c2VjcmV0"
    });
    test:assertEquals(basic.statusCode, 401);
}

@test:Config {}
function testBearerTokenAllowsExtraWhitespace() returns error? {
    string token = check serverAuthToken();
    // `protectedModernPost` adds the first separator, producing two spaces before the token here.
    http:Response response = check protectedModernPost("/mcp", REQUEST_LIST_TOOLS, token = " " + token);
    test:assertEquals(response.statusCode, 200);
}

@test:Config {}
function testTokenWithoutRequiredScopeIsForbidden() returns error? {
    http:Response response = check protectedModernPost("/mcp", REQUEST_LIST_TOOLS,
            token = check serverAuthToken(scope = "profile"));
    test:assertEquals(response.statusCode, 403);
    string challenge = check challengeOf(response);
    test:assertTrue(challenge.includes("error=\"insufficient_scope\""), challenge);
    test:assertTrue(challenge.includes("scope=\"mcp:tools\""), challenge);
    test:assertTrue(challenge.includes(string `resource_metadata="${PROTECTED_METADATA_URL}"`), challenge);
}

@test:Config {}
function testToolScopesStayOffTheWire() returns error? {
    http:Response response = check protectedModernPost("/mcp", REQUEST_LIST_TOOLS, token = check serverAuthToken());
    test:assertEquals(response.statusCode, 200);
    json payload = check response.getJsonPayload();
    json[] tools = check (check payload.result.tools).ensureType();
    test:assertEquals(tools.length(), 3);
    foreach json tool in tools {
        map<json> toolDefinition = check tool.ensureType();
        test:assertFalse(toolDefinition.hasKey("scopes"), toolDefinition.toJsonString());
    }
}

@test:Config {}
function testAuthContextIsBoundToTools() returns error? {
    http:Response response = check callProtectedTool("whoami", check serverAuthToken(subject = "bob"));
    test:assertEquals(response.statusCode, 200);
    test:assertEquals(check textResult(response), "bob");
}

@test:Config {}
function testToolScopeIsEnforced() returns error? {
    http:Response denied = check callProtectedTool("deleteFile", check serverAuthToken(), arguments = {path: "a"});
    test:assertEquals(denied.statusCode, 403);
    string challenge = check challengeOf(denied);
    test:assertTrue(challenge.includes("error=\"insufficient_scope\""), challenge);
    // The challenge asks for the scopes every request needs together with the tool's own.
    test:assertTrue(challenge.includes("scope=\"mcp:tools files:write\""), challenge);

    http:Response allowed = check callProtectedTool("deleteFile",
            check serverAuthToken(scope = "mcp:tools files:write"), arguments = {path: "a"});
    test:assertEquals(allowed.statusCode, 200);
    test:assertEquals(check textResult(allowed), "deleted a");
}

@test:Config {}
function testToolCanRequestStepUp() returns error? {
    http:Response denied = check callProtectedTool("adminReport", check serverAuthToken());
    test:assertEquals(denied.statusCode, 403);
    test:assertTrue((check challengeOf(denied)).includes("scope=\"mcp:tools admin\""));

    http:Response allowed = check callProtectedTool("adminReport", check serverAuthToken(scope = "mcp:tools admin"));
    test:assertEquals(allowed.statusCode, 200);
    test:assertEquals(check textResult(allowed), "report");
}

@test:Config {}
function testAdvancedServiceReceivesAuthContext() returns error? {
    string token = check serverAuthToken(audience = PROTECTED_ADVANCED_RESOURCE);
    http:Response response = check callProtectedTool("whoami", token, "/advanced");
    test:assertEquals(response.statusCode, 200);
    test:assertEquals(check textResult(response), "alice");

    http:Response denied = check callProtectedTool("admin", token, "/advanced");
    test:assertEquals(denied.statusCode, 403);
    string challenge = check challengeOf(denied);
    test:assertTrue(challenge.includes("scope=\"admin\""), challenge);
    test:assertTrue(challenge.includes(
        "resource_metadata=\"http://localhost:3235/.well-known/oauth-protected-resource/advanced\""), challenge);

    // A token issued for the basic service is not accepted by the advanced one.
    http:Response otherAudience = check callProtectedTool("whoami", check serverAuthToken(), "/advanced");
    test:assertEquals(otherAudience.statusCode, 401);
}

isolated function assertListingChallenge(http:Response response) returns error? {
    test:assertEquals(response.statusCode, 403);
    string challenge = check challengeOf(response);
    test:assertTrue(challenge.startsWith("Bearer "), challenge);
    test:assertTrue(challenge.includes("error=\"insufficient_scope\""), challenge);
    // The challenge names every scope the operation needs, not only the one that was missing.
    test:assertTrue(challenge.includes("scope=\"mcp:tools tools:list\""), challenge);
    test:assertTrue(challenge.includes(
        "resource_metadata=\"http://localhost:3235/.well-known/oauth-protected-resource/listing\""), challenge);
}

@test:Config {}
function testModernListToolsInsufficientScopeIsChallenged() returns error? {
    string audience = "http://localhost:3235/listing";
    string token = check serverAuthToken(audience = audience);
    check assertListingChallenge(check protectedModernPost("/listing", REQUEST_LIST_TOOLS, token = token));
    // A tool call is resolved against the listing, so it is challenged the same way.
    check assertListingChallenge(check callProtectedTool("echo", token, "/listing"));

    string stepUp = check serverAuthToken(scope = "mcp:tools tools:list", audience = audience);
    http:Response listed = check protectedModernPost("/listing", REQUEST_LIST_TOOLS, token = stepUp);
    test:assertEquals(listed.statusCode, 200);
    http:Response called = check callProtectedTool("echo", stepUp, "/listing");
    test:assertEquals(check textResult(called), "echo");
}

@test:Config {}
function testLegacyListToolsInsufficientScopeIsChallenged() returns error? {
    map<string|string[]> requestHeaders = {
        [AUTHORIZATION_HEADER]: "Bearer " + check serverAuthToken(audience = "http://localhost:3235/listing")
    };
    http:Response initialized = check serverAuthClient->post("/listing", legacyRequest(REQUEST_INITIALIZE, {
        protocolVersion: LATEST_LEGACY_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: {name: "test", version: "1"}
    }), headers = legacyHeaders(requestHeaders));
    test:assertEquals(initialized.statusCode, 200);
    requestHeaders[SESSION_ID_HEADER] = check initialized.getHeader(SESSION_ID_HEADER);
    http:Response listed = check serverAuthClient->post("/listing", legacyRequest(REQUEST_LIST_TOOLS),
            headers = legacyHeaders(requestHeaders));
    check assertListingChallenge(listed);
}

@test:Config {}
function testLegacySessionIsBoundToItsCreator() returns error? {
    map<string|string[]> aliceHeaders = {[AUTHORIZATION_HEADER]: "Bearer " + check serverAuthToken()};
    http:Response initialized = check serverAuthClient->post("/mcp", legacyRequest(REQUEST_INITIALIZE, {
        protocolVersion: LATEST_LEGACY_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: {name: "test", version: "1"}
    }), headers = legacyHeaders(aliceHeaders));
    test:assertEquals(initialized.statusCode, 200);
    string sessionId = check initialized.getHeader(SESSION_ID_HEADER);

    map<string|string[]> bobHeaders = {
        [AUTHORIZATION_HEADER]: "Bearer " + check serverAuthToken(subject = "bob"),
        [SESSION_ID_HEADER]: sessionId
    };
    http:Response hijacked = check serverAuthClient->post("/mcp", legacyRequest(REQUEST_LIST_TOOLS),
            headers = legacyHeaders(bobHeaders));
    test:assertEquals(hijacked.statusCode, 404);

    aliceHeaders[SESSION_ID_HEADER] = sessionId;
    http:Response owned = check serverAuthClient->post("/mcp", legacyRequest(REQUEST_LIST_TOOLS),
            headers = legacyHeaders(aliceHeaders));
    test:assertEquals(owned.statusCode, 200);

    http:Response deleted = check serverAuthClient->delete("/mcp", headers = legacyHeaders(bobHeaders));
    test:assertEquals(deleted.statusCode, 404);
}

@test:Config {}
function testServerAuthConfigurationIsValidated() returns error? {
    StreamableHttpListener validationListener = check new (3236);
    JwtTokenValidator jwtValidator = {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}};

    map<OAuthProtectedResourceConfig> invalidConfigs = {
        "not canonical": {
            'resource: "HTTP://LOCALHOST:3236/x",
            authorizationServers: [{issuer: PROTECTED_ISSUER, validator: jwtValidator}]
        },
        "configured more than once": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: jwtValidator},
                {issuer: PROTECTED_ISSUER, validator: jwtValidator}
            ]
        },
        "not in 'jwtValidatorConfig'": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [{
                issuer: PROTECTED_ISSUER,
                validator: {jwtValidatorConfig: {audience: "x", signatureConfig: {secret: SIGNING_KEY}}}
            }]
        },
        "does not match the authorization server issuer": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [{
                issuer: PROTECTED_ISSUER,
                validator: {jwtValidatorConfig: {issuer: "https://other.example.com",
                    signatureConfig: {secret: SIGNING_KEY}}}
            }]
        },
        "At least one authorization server": {'resource: "http://localhost:3236/x", authorizationServers: []},
        "remove it from requiredScopes": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [{issuer: PROTECTED_ISSUER, validator: jwtValidator}],
            requiredScopes: ["files:read", "offline_access"]
        },
        "remove it from scopesSupported": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [{issuer: PROTECTED_ISSUER, validator: jwtValidator}],
            scopesSupported: ["files:read", "offline_access"]
        },
        "remove it from scopeHierarchy": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [{issuer: PROTECTED_ISSUER, validator: jwtValidator}],
            scopeHierarchy: {"files:admin": ["files:read", "offline_access"]}
        },
        "entry for 'files:admin' lists no scopes": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [{issuer: PROTECTED_ISSUER, validator: jwtValidator}],
            scopeHierarchy: {"files:admin": []}
        },
        "'has space' in requiredScopes is not a valid OAuth scope": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [{issuer: PROTECTED_ISSUER, validator: jwtValidator}],
            requiredScopes: ["has space"]
        },
        "Invalid 'resourceDocumentation': 'docs/files' is not an absolute URL.": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [{issuer: PROTECTED_ISSUER, validator: jwtValidator}],
            resourceDocumentation: "docs/files"
        },
        "Only one authorization server can use 'oauth2IntrospectionConfig'": {
            'resource: "http://localhost:3236/x",
            authorizationServers: [
                {issuer: "https://a.example.com", validator: {oauth2IntrospectionConfig: {url: "https://a.example.com/i"}}},
                {issuer: "https://b.example.com", validator: {oauth2IntrospectionConfig: {url: "https://b.example.com/i"}}}
            ]
        }
    };
    foreach [string, OAuthProtectedResourceConfig] [expectedMessage, authConfig] in invalidConfigs.entries() {
        ServerAuthenticator|Error result = new (authConfig.cloneReadOnly(), {});
        test:assertTrue(result is Error && result.message().includes(expectedMessage),
                string `expected '${expectedMessage}', found: ${result is Error ? result.message() : "success"}`);
    }

    // Tool scopes end up in 403 challenges, so they are checked too.
    OAuthProtectedResourceConfig validConfig = {
        'resource: "http://localhost:3236/x",
        authorizationServers: [{issuer: PROTECTED_ISSUER, validator: jwtValidator}]
    };
    ServerAuthenticator|Error toolScopeResult = new (validConfig.cloneReadOnly(), {"refresh": ["offline_access"]});
    test:assertTrue(toolScopeResult is Error &&
            toolScopeResult.message().includes("from the '@mcp:Tool' scopes of 'refresh'"));

    StreamableHttpAdvancedService requiresAuth = @StreamableHttpConfig {
        info: {name: "requires-auth", version: "1"}
    } isolated service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams params, AuthContext auth) returns CallToolResult =>
            {content: []};
    };
    Error? requiresAuthResult = validationListener.attach(requiresAuth, "/requires-auth");
    test:assertTrue(requiresAuthResult is Error && requiresAuthResult.message().includes("mcp:AuthContext"));

}

isolated function newFilesVirtualHostService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {
        info: {name: "files", version: "1"},
        httpConfig: {
            host: "files.example.com",
            auth: {
                'resource: "http://public-a.example.com/shared",
                authorizationServers: [
                    {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
                ]
            }
        }
    } service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams params) returns CallToolResult => {content: []};
    };

isolated function newUppercaseFilesVirtualHostService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {
        info: {name: "uppercase-files", version: "1"},
        httpConfig: {
            host: "Files.Example.com",
            auth: {
                'resource: "http://public-uppercase.example.com/shared",
                authorizationServers: [
                    {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
                ]
            }
        }
    } service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams params) returns CallToolResult => {content: []};
    };

isolated function newMediaVirtualHostService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {
        info: {name: "media", version: "1"},
        httpConfig: {
            host: "media.example.com",
            auth: {
                'resource: "http://public-b.example.com/shared",
                authorizationServers: [
                    {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
                ]
            }
        }
    } service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams params) returns CallToolResult => {content: []};
    };

isolated function newOtherFilesVirtualHostService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {
        info: {name: "other-files", version: "1"},
        httpConfig: {
            host: "files.example.com",
            auth: {
                'resource: "http://public-a.example.com/other",
                authorizationServers: [
                    {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
                ]
            }
        }
    } service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams params) returns CallToolResult => {content: []};
    };

isolated function newDefaultHostService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {
        info: {name: "default-host", version: "1"},
        httpConfig: {
            auth: {
                'resource: "http://public-default.example.com/shared",
                authorizationServers: [
                    {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
                ]
            }
        }
    } service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams params) returns CallToolResult => {content: []};
    };

@test:Config {}
function testProtectedResourceMetadataIsIsolatedByVirtualHost() returns error? {
    StreamableHttpListener virtualHostListener = check new (3240);
    StreamableHttpAdvancedService files = newFilesVirtualHostService();
    StreamableHttpAdvancedService uppercaseFiles = newUppercaseFilesVirtualHostService();
    StreamableHttpAdvancedService media = newMediaVirtualHostService();
    StreamableHttpAdvancedService otherFiles = newOtherFilesVirtualHostService();
    StreamableHttpAdvancedService defaultHost = newDefaultHostService();

    // The same metadata path is valid on different virtual hosts, and one host can serve multiple paths.
    check virtualHostListener.attach(files, "/files");
    // The HTTP module treats differently cased host configuration values as distinct routing keys.
    check virtualHostListener.attach(uppercaseFiles, "/uppercaseFiles");
    check virtualHostListener.attach(media, "/media");
    check virtualHostListener.attach(otherFiles, "/otherFiles");
    check virtualHostListener.attach(defaultHost, "/defaultHost");

    StreamableHttpAdvancedService duplicate = newFilesVirtualHostService();
    Error? duplicateResult = virtualHostListener.attach(duplicate, "/duplicate");
    test:assertTrue(duplicateResult is Error && duplicateResult.message().includes("already published"));

    check virtualHostListener.'start();
    error? assertionResult = trap assertVirtualHostMetadata(virtualHostListener, files);
    check virtualHostListener.gracefulStop();
    return assertionResult;
}

isolated function assertVirtualHostMetadata(StreamableHttpListener virtualHostListener,
        StreamableHttpAdvancedService files) returns error? {
    http:Client virtualHostClient = check new ("http://localhost:3240");
    string sharedMetadataPath = "/.well-known/oauth-protected-resource/shared";

    json filesMetadata = check virtualHostClient->get(sharedMetadataPath, headers = {"Host": "files.example.com"});
    json uppercaseFilesMetadata = check virtualHostClient->get(sharedMetadataPath,
            headers = {"Host": "Files.Example.com"});
    json mediaMetadata = check virtualHostClient->get(sharedMetadataPath, headers = {"Host": "media.example.com"});
    json defaultMetadata = check virtualHostClient->get(sharedMetadataPath);
    json otherFilesMetadata = check virtualHostClient->get("/.well-known/oauth-protected-resource/other",
            headers = {"Host": "files.example.com"});
    // The advertised public resource is independent of the internal virtual host.
    test:assertEquals(filesMetadata.'resource, "http://public-a.example.com/shared");
    test:assertEquals(uppercaseFilesMetadata.'resource, "http://public-uppercase.example.com/shared");
    test:assertEquals(mediaMetadata.'resource, "http://public-b.example.com/shared");
    test:assertEquals(defaultMetadata.'resource, "http://public-default.example.com/shared");
    test:assertEquals(otherFilesMetadata.'resource, "http://public-a.example.com/other");

    check virtualHostListener.detach(files);
    http:Response detached = check virtualHostClient->get(sharedMetadataPath, headers = {"Host": "files.example.com"});
    test:assertEquals(detached.statusCode, 404);
    // Detaching one host's service does not remove the same path from another host's registry.
    json stillPublished = check virtualHostClient->get(sharedMetadataPath, headers = {"Host": "media.example.com"});
    test:assertEquals(stillPublished.'resource, "http://public-b.example.com/shared");
    json uppercaseStillPublished = check virtualHostClient->get(sharedMetadataPath,
            headers = {"Host": "Files.Example.com"});
    test:assertEquals(uppercaseStillPublished.'resource, "http://public-uppercase.example.com/shared");
}

isolated function bearerQuoting() returns string => bearerChallenge("https://a/b", ["x"], "invalid_token",
        "has \"quotes\" and \\ backslash");

@test:Config {}
function testBearerChallengeQuotesValues() {
    test:assertEquals(bearerQuoting(), "Bearer error=\"invalid_token\", " +
        "error_description=\"has \\\"quotes\\\" and \\\\ backslash\", scope=\"x\", resource_metadata=\"https://a/b\"");
}

@test:Config {}
function testGrantedScopesReadsScopeAndScpClaims() {
    test:assertEquals(grantedScopes({scope: " a  b "}, "scope"), ["a", "b"]);
    test:assertEquals(grantedScopes({scp: ["a", "b"]}, "scope"), ["a", "b"]);
    test:assertEquals(grantedScopes({}, "scope"), []);
    test:assertTrue(audienceMatches(["x", PROTECTED_RESOURCE], [PROTECTED_RESOURCE]));
    test:assertTrue(audienceMatches("api://files", ["api://files", PROTECTED_RESOURCE]));
    test:assertFalse(audienceMatches((), [PROTECTED_RESOURCE]));
}

// Two authorization servers: one issues JWTs, the other opaque tokens that are introspected and
// carry the server's own identifier for the API as their audience.

const PARTNER_ISSUER = "https://partner.example.com";
const PARTNER_AUDIENCE = "api://files-test";

isolated int introspectionCalls = 0;

isolated function introspectionCallCount() returns int {
    lock {
        return introspectionCalls;
    }
}

service /oauth2 on new http:Listener(3237) {
    resource function post introspect(http:Request request) returns json|error {
        lock {
            introspectionCalls += 1;
        }
        map<string> form = check request.getFormParams();
        match form["token"] {
            "opaque-carol" => {
                return {active: true, sub: "carol", client_id: "partner-app", scope: "mcp:tools", aud: PARTNER_AUDIENCE};
            }
            "opaque-username-only" => {
                return {active: true, username: "dave", client_id: "partner-app", scope: "mcp:tools",
                    aud: PARTNER_AUDIENCE};
            }
            "opaque-wrong-issuer" => {
                return {active: true, sub: "carol", iss: "https://other-idp.example.com", scope: "mcp:tools",
                    aud: PARTNER_AUDIENCE};
            }
            "opaque-other-audience" => {
                return {active: true, sub: "carol", scope: "mcp:tools", aud: "api://another-api"};
            }
        }
        return {active: false};
    }
}

@StreamableHttpConfig {
    info: {name: "protected-multi", version: "1"},
    httpConfig: {
        auth: {
            'resource: "http://localhost:3235/multi",
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}},
                {
                    issuer: PARTNER_ISSUER,
                    audience: PARTNER_AUDIENCE,
                    validator: {oauth2IntrospectionConfig: {url: "http://localhost:3237/oauth2/introspect"}}
                }
            ],
            requiredScopes: ["mcp:tools"]
        }
    }
}
service StreamableHttpService /multi on serverAuthListener {
    @Tool {description: "Returns the caller and its issuer", schema: {'type: "object"}}
    remote isolated function whoami(AuthContext auth) returns string =>
        (auth.subject ?: "") + "@" + (auth.issuer ?: "");

    @Tool {description: "Returns the caller's client", schema: {'type: "object"}}
    remote isolated function clientOf(AuthContext auth) returns string => auth.clientId ?: "";

    @Tool {description: "Asks for a scope that cannot appear in a challenge", schema: {'type: "object"}}
    remote isolated function badScope() returns string|InsufficientScopeError =>
        error InsufficientScopeError("Needs a malformed scope", scopes = ["not a scope"]);
}

// The introspection endpoint of this service is not listening.
@StreamableHttpConfig {
    info: {name: "protected-unavailable", version: "1"},
    httpConfig: {
        auth: {
            'resource: "http://localhost:3235/unavailable",
            authorizationServers: [
                {
                    issuer: PARTNER_ISSUER,
                    audience: PARTNER_AUDIENCE,
                    validator: {oauth2IntrospectionConfig: {url: "http://localhost:3239/oauth2/introspect"}}
                }
            ]
        }
    }
}
service StreamableHttpService /unavailable on serverAuthListener {
    @Tool {description: "Returns the caller", schema: {'type: "object"}}
    remote isolated function whoami(AuthContext auth) returns string => auth.subject ?: "";
}

@test:Config {}
function testIntrospectionResponsesAreReadFaithfully() returns error? {
    // `client_id` is read from the introspection response.
    http:Response clientResponse = check callProtectedTool("clientOf", "opaque-carol", "/multi");
    test:assertEquals(check textResult(clientResponse), "partner-app");

    // The configured issuer is authoritative: a response naming another issuer is rejected.
    http:Response otherIssuer = check callProtectedTool("whoami", "opaque-wrong-issuer", "/multi");
    test:assertEquals(otherIssuer.statusCode, 401);
}

@test:Config {}
function testIntrospectionOutageIsNotReportedAsInvalidToken() returns error? {
    http:Response unavailable = check callProtectedTool("whoami", "opaque-carol", "/unavailable");
    test:assertEquals(unavailable.statusCode, 503);
    // No challenge: the token was never judged, so the client should keep it and retry.
    test:assertFalse(unavailable.hasHeader(WWW_AUTHENTICATE_HEADER));
}

@test:Config {}
function testInvalidRuntimeScopeIsAServerError() returns error? {
    http:Response response = check callProtectedTool("badScope",
            check serverAuthToken(audience = "http://localhost:3235/multi"), "/multi");
    test:assertEquals(response.statusCode, 500);
}

@test:Config {}
function testTokenWithoutPrincipalGetsNoSession() returns error? {
    // A token naming neither a subject nor a client cannot own a session.
    string anonymousToken = check jwt:issue({
        issuer: PROTECTED_ISSUER,
        audience: PROTECTED_RESOURCE,
        customClaims: {scope: "mcp:tools"},
        signatureConfig: {algorithm: jwt:HS256, config: SIGNING_KEY}
    });
    http:Response initialized = check serverAuthClient->post("/mcp", legacyRequest(REQUEST_INITIALIZE, {
        protocolVersion: LATEST_LEGACY_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: {name: "test", version: "1"}
    }), headers = legacyHeaders({[AUTHORIZATION_HEADER]: "Bearer " + anonymousToken}));
    test:assertEquals(initialized.statusCode, 200);
    test:assertFalse(initialized.hasHeader(SESSION_ID_HEADER));
}

@test:Config {}
function testTokenWithoutPrincipalIsRejectedWhenAutoServiceRequiresSession() returns error? {
    string anonymousToken = check jwt:issue({
        issuer: PROTECTED_ISSUER,
        audience: SESSION_REQUIRED_RESOURCE,
        signatureConfig: {algorithm: jwt:HS256, config: SIGNING_KEY}
    });
    http:Response initialized = check serverAuthClient->post("/sessionRequired", legacyRequest(REQUEST_INITIALIZE, {
        protocolVersion: LATEST_LEGACY_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: {name: "test", version: "1"}
    }), headers = legacyHeaders({[AUTHORIZATION_HEADER]: "Bearer " + anonymousToken}));
    test:assertEquals(initialized.statusCode, 200);
    test:assertFalse(initialized.hasHeader(SESSION_ID_HEADER));
    json payload = check initialized.getJsonPayload();
    json errorPayload = check payload.'error;
    string errorMessage = check (check errorPayload.message).ensureType();
    test:assertTrue(errorMessage.includes("neither a subject nor a client"));
}

@test:Config {}
function testTokenWithoutPrincipalRemainsRejectedInStatefulMode() returns error? {
    string anonymousToken = check jwt:issue({
        issuer: PROTECTED_ISSUER,
        audience: STATEFUL_RESOURCE,
        signatureConfig: {algorithm: jwt:HS256, config: SIGNING_KEY}
    });
    http:Response initialized = check serverAuthClient->post("/stateful", legacyRequest(REQUEST_INITIALIZE, {
        protocolVersion: LATEST_LEGACY_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: {name: "test", version: "1"}
    }), headers = legacyHeaders({[AUTHORIZATION_HEADER]: "Bearer " + anonymousToken}));
    test:assertEquals(initialized.statusCode, 200);
    test:assertFalse(initialized.hasHeader(SESSION_ID_HEADER));
    json payload = check initialized.getJsonPayload();
    json errorPayload = check payload.'error;
    string errorMessage = check (check errorPayload.message).ensureType();
    test:assertTrue(errorMessage.includes("neither a subject nor a client"));
}

@test:Config {}
function testPrincipalsDoNotCollide() {
    string empty = "";
    AuthContext user = {subject: "x", clientId: (), issuer: PROTECTED_ISSUER, scopes: [], claims: {}, token: empty};
    AuthContext clientCaller = {subject: (), clientId: "x", issuer: PROTECTED_ISSUER, scopes: [], claims: {}, token: empty};
    test:assertNotEquals(principalOf(user), principalOf(clientCaller));
}

@test:Config {}
function testUsernameIsNotTakenAsTheSubject() returns error? {
    // `username` is a display name that may be reassigned, so it does not identify the caller.
    http:Response subject = check callProtectedTool("whoami", "opaque-username-only", "/multi");
    test:assertEquals(check textResult(subject), "@" + PARTNER_ISSUER);
    http:Response clientId = check callProtectedTool("clientOf", "opaque-username-only", "/multi");
    test:assertEquals(check textResult(clientId), "partner-app");
}

@test:Config {}
function testSessionIsBoundToItsClient() returns error? {
    // The same user signed in through two clients: the second client cannot use the first one's session.
    string desktopToken = check jwt:issue({
        issuer: PROTECTED_ISSUER,
        username: "alice",
        audience: PROTECTED_RESOURCE,
        customClaims: {scope: "mcp:tools", client_id: "desktop-app"},
        signatureConfig: {algorithm: jwt:HS256, config: SIGNING_KEY}
    });
    string otherToken = check jwt:issue({
        issuer: PROTECTED_ISSUER,
        username: "alice",
        audience: PROTECTED_RESOURCE,
        customClaims: {scope: "mcp:tools", client_id: "other-app"},
        signatureConfig: {algorithm: jwt:HS256, config: SIGNING_KEY}
    });
    http:Response initialized = check serverAuthClient->post("/mcp", legacyRequest(REQUEST_INITIALIZE, {
        protocolVersion: LATEST_LEGACY_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: {name: "test", version: "1"}
    }), headers = legacyHeaders({[AUTHORIZATION_HEADER]: "Bearer " + desktopToken}));
    test:assertEquals(initialized.statusCode, 200);
    string sessionId = check initialized.getHeader(SESSION_ID_HEADER);

    http:Response otherClient = check serverAuthClient->post("/mcp", legacyRequest(REQUEST_LIST_TOOLS),
            headers = legacyHeaders({[AUTHORIZATION_HEADER]: "Bearer " + otherToken, [SESSION_ID_HEADER]: sessionId}));
    test:assertEquals(otherClient.statusCode, 404);

    http:Response sameClient = check serverAuthClient->post("/mcp", legacyRequest(REQUEST_LIST_TOOLS),
            headers = legacyHeaders({[AUTHORIZATION_HEADER]: "Bearer " + desktopToken, [SESSION_ID_HEADER]: sessionId}));
    test:assertEquals(sameClient.statusCode, 200);
}

@test:Config {}
function testTokensFromEveryAuthorizationServerAreAccepted() returns error? {
    json metadata = check serverAuthClient->get("/.well-known/oauth-protected-resource/multi");
    test:assertEquals(metadata.authorization_servers, [PROTECTED_ISSUER, PARTNER_ISSUER]);

    http:Response jwtCaller = check callProtectedTool("whoami",
            check serverAuthToken(audience = "http://localhost:3235/multi"), "/multi");
    test:assertEquals(check textResult(jwtCaller), "alice@" + PROTECTED_ISSUER);

    // Introspected tokens are checked against the partner's own audience, and are attributed to it.
    http:Response introspectedCaller = check callProtectedTool("whoami", "opaque-carol", "/multi");
    test:assertEquals(check textResult(introspectedCaller), "carol@" + PARTNER_ISSUER);

    http:Response otherAudience = check callProtectedTool("whoami", "opaque-other-audience", "/multi");
    test:assertEquals(otherAudience.statusCode, 401);
    http:Response inactive = check callProtectedTool("whoami", "opaque-unknown", "/multi");
    test:assertEquals(inactive.statusCode, 401);
}

@test:Config {}
function testTokensAreOnlySentToTheirIssuer() returns error? {
    int callsBefore = introspectionCallCount();

    // A JWT is validated only by the server named in its `iss`. A JWT from an unrelated issuer, or
    // naming no issuer, is rejected without being disclosed to the introspection server.
    string unrelatedIssuerToken = check jwt:issue({
        issuer: "https://unrelated.example.com",
        username: "mallory",
        audience: "http://localhost:3235/multi",
        customClaims: {scope: "mcp:tools"},
        signatureConfig: {algorithm: jwt:HS256, config: SIGNING_KEY}
    });
    http:Response unrelated = check callProtectedTool("whoami", unrelatedIssuerToken, "/multi");
    test:assertEquals(unrelated.statusCode, 401);

    string noIssuerToken = check jwt:issue({
        username: "mallory",
        audience: "http://localhost:3235/multi",
        customClaims: {scope: "mcp:tools"},
        signatureConfig: {algorithm: jwt:HS256, config: SIGNING_KEY}
    });
    http:Response noIssuer = check callProtectedTool("whoami", noIssuerToken, "/multi");
    test:assertEquals(noIssuer.statusCode, 401);

    // A JWT from the JWT-validated server never reaches introspection either.
    http:Response jwtCaller = check callProtectedTool("whoami",
            check serverAuthToken(audience = "http://localhost:3235/multi"), "/multi");
    test:assertEquals(jwtCaller.statusCode, 200);
    test:assertEquals(introspectionCallCount(), callsBefore);

    // An opaque token goes to the single introspection server, exactly once.
    http:Response opaque = check callProtectedTool("whoami", "opaque-carol", "/multi");
    test:assertEquals(opaque.statusCode, 200);
    test:assertEquals(introspectionCallCount(), callsBefore + 1);
}

// Plain HTTP listener authentication: tokens are checked by the HTTP module, without discovery.
@StreamableHttpConfig {
    info: {name: "plain-http-auth", version: "1"},
    httpConfig: {
        auth: [
            {
                jwtValidatorConfig: {issuer: PROTECTED_ISSUER, audience: "plain", signatureConfig: {secret: SIGNING_KEY}},
                scopes: ["mcp:tools"]
            }
        ]
    }
}
service StreamableHttpService /plain on serverAuthListener {
    @Tool {description: "Returns the caller", schema: {'type: "object"}}
    remote isolated function whoami(AuthContext? auth) returns string => auth is () ? "no-context" : "context";
}

@test:Config {}
function testPlainHttpAuthBehavesAsBefore() returns error? {
    http:Response unauthenticated = check protectedModernPost("/plain", REQUEST_LIST_TOOLS);
    test:assertEquals(unauthenticated.statusCode, 401);
    test:assertFalse(unauthenticated.hasHeader(WWW_AUTHENTICATE_HEADER));

    http:Response allowed = check callProtectedTool("whoami", check serverAuthToken(audience = "plain"), "/plain");
    test:assertEquals(allowed.statusCode, 200);
    // `mcp:AuthContext` is only provided by MCP authorization.
    test:assertEquals(check textResult(allowed), "no-context");

    http:Response noMetadata = check serverAuthClient->get("/.well-known/oauth-protected-resource/plain");
    test:assertEquals(noMetadata.statusCode, 404);
}

// Scope hierarchies: a broader scope satisfies the narrower scopes it implies.
@StreamableHttpConfig {
    info: {name: "protected-hierarchy", version: "1"},
    httpConfig: {
        auth: {
            'resource: "http://localhost:3235/hierarchy",
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ],
            requiredScopes: ["files:read"],
            scopeHierarchy: {
                "files:admin": ["files:write", "files:delete"],
                "files:write": ["files:read"]
            }
        }
    }
}
service StreamableHttpService /hierarchy on serverAuthListener {
    @Tool {description: "Returns the caller's scopes", schema: {'type: "object"}}
    remote isolated function scopes(AuthContext auth) returns string => string:'join(" ", ...auth.scopes);

    @Tool {description: "Deletes a file", schema: {'type: "object"}, scopes: ["files:delete"]}
    remote isolated function deleteFile() returns string => "deleted";

    @Tool {description: "Archives a file", schema: {'type: "object"}, scopes: ["files:archive"]}
    remote isolated function archiveFile() returns string => "archived";

    @Tool {description: "Administers files", schema: {'type: "object"}, scopes: ["files:admin"]}
    remote isolated function administer() returns string => "administered";
}

@test:Config {}
function testBroaderScopesSatisfyNarrowerOnes() returns error? {
    string adminToken = check serverAuthToken(scope = "files:admin", audience = "http://localhost:3235/hierarchy");

    // `files:admin` implies `files:read` (through `files:write`), so it passes the required scopes,
    // and handlers see the expanded scopes.
    http:Response scopes = check callProtectedTool("scopes", adminToken, "/hierarchy");
    test:assertEquals(scopes.statusCode, 200);
    test:assertEquals(check textResult(scopes), "files:admin files:write files:delete files:read");

    http:Response deleted = check callProtectedTool("deleteFile", adminToken, "/hierarchy");
    test:assertEquals(deleted.statusCode, 200);

    // A scope outside the hierarchy is still required, and the challenge names exactly that scope.
    http:Response archived = check callProtectedTool("archiveFile", adminToken, "/hierarchy");
    test:assertEquals(archived.statusCode, 403);
    test:assertTrue((check challengeOf(archived)).includes("scope=\"files:read files:archive\""));

    // A narrower scope never satisfies a broader one.
    string writeToken = check serverAuthToken(scope = "files:write", audience = "http://localhost:3235/hierarchy");
    http:Response administered = check callProtectedTool("administer", writeToken, "/hierarchy");
    test:assertEquals(administered.statusCode, 403);
    test:assertTrue((check challengeOf(administered)).includes("scope=\"files:read files:admin\""));
}

@test:Config {}
function testExpandScopes() {
    readonly & map<string[]> hierarchy = {"a": ["b"], "b": ["c", "a"], "x": ["y"]};
    test:assertEquals(expandScopes(["a"], hierarchy), ["a", "b", "c"]);
    test:assertEquals(expandScopes(["c"], hierarchy), ["c"]);
    test:assertEquals(expandScopes(["x", "a"], hierarchy), ["x", "a", "y", "b", "c"]);
    test:assertEquals(expandScopes([], hierarchy), []);
}

// End to end: our own MCP client discovers the authorization server from the server's challenge,
// obtains a token, and steps up when a tool needs more scopes.

const E2E_ISSUER = "https://localhost:3233";
const E2E_RESOURCE = "https://localhost:3234/mcp";
const E2E_CLIENT_ID = "e2e-agent";
final string E2E_CLIENT_KEY = uuid:createType4AsString();

listener http:Listener e2eAuthServerListener = new (3233, {
    secureSocket: {key: {certFile: MTLS_RESOURCES + "server.crt", keyFile: MTLS_RESOURCES + "server.key"}}
});

isolated string[] e2eRequestedScopes = [];

service / on e2eAuthServerListener {
    resource function get [string... path]() returns json|http:NotFound {
        if path != [".well-known", "oauth-authorization-server"] {
            return http:NOT_FOUND;
        }
        return {
            issuer: E2E_ISSUER,
            token_endpoint: E2E_ISSUER + "/token",
            response_types_supported: ["code"],
            grant_types_supported: ["client_credentials"],
            token_endpoint_auth_methods_supported: ["client_secret_basic"]
        };
    }

    resource function post token(http:Request request) returns http:Ok|http:BadRequest|http:Unauthorized|error {
        string|http:HeaderNotFoundError authorization = request.getHeader(AUTHORIZATION_HEADER);
        string expected = "Basic " + (E2E_CLIENT_ID + ":" + E2E_CLIENT_KEY).toBytes().toBase64();
        if authorization != expected {
            return <http:Unauthorized>{body: {'error: "invalid_client"}};
        }
        map<string> form = check request.getFormParams();
        string? audience = form["resource"];
        if form["grant_type"] != "client_credentials" || audience is () {
            return <http:BadRequest>{body: {'error: "invalid_request"}};
        }
        string scope = form["scope"] ?: "";
        lock {
            e2eRequestedScopes.push(scope);
        }
        string accessToken = check jwt:issue({
            issuer: E2E_ISSUER,
            username: E2E_CLIENT_ID,
            audience,
            customClaims: {scope},
            signatureConfig: {algorithm: jwt:HS256, config: SIGNING_KEY}
        });
        string scheme = "Bearer";
        return <http:Ok>{body: {access_token: accessToken, token_type: scheme, expires_in: 300, scope}};
    }
}

listener StreamableHttpListener e2eMcpListener = check new (3234, secureSocket = {
    key: {certFile: MTLS_RESOURCES + "server.crt", keyFile: MTLS_RESOURCES + "server.key"}
});

@StreamableHttpConfig {
    info: {name: "e2e-protected", version: "1"},
    httpConfig: {
        auth: {
            'resource: E2E_RESOURCE,
            authorizationServers: [
                {issuer: E2E_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ],
            requiredScopes: ["mcp:tools"]
        }
    }
}
service StreamableHttpService /mcp on e2eMcpListener {
    @Tool {description: "Returns the caller", schema: {'type: "object"}, outputSchema: {"type": "string"}}
    remote isolated function whoami(AuthContext auth) returns string => auth.subject ?: "";

    @Tool {
        description: "Deletes a file",
        schema: {'type: "object", properties: {path: {'type: "string"}}, required: ["path"]},
        outputSchema: {"type": "string"},
        scopes: ["files:write"]
    }
    remote isolated function deleteFile(string path) returns string => "deleted " + path;
}

@test:Config {}
function testClientAuthorizesAgainstProtectedServer() returns error? {
    StreamableHttpClient mcpClient = check new (E2E_RESOURCE,
        auth = {
            grant: {
                clientConfig: {
                    clientId: E2E_CLIENT_ID,
                    issuer: E2E_ISSUER,
                    clientAuth: {clientSecret: E2E_CLIENT_KEY}
                }
            }
        },
        secureSocket = {cert: MTLS_RESOURCES + "server.crt"}
    );
    _ = check mcpClient->connect();

    CallToolResult whoami = check mcpClient->callTool({name: "whoami"});
    test:assertEquals(whoami["structuredContent"], E2E_CLIENT_ID);

    // The tool's scope is missing from the first token, so the client steps up and retries.
    CallToolResult deleted = check mcpClient->callTool({name: "deleteFile", arguments: {"path": "a"}});
    test:assertEquals(deleted["structuredContent"], "deleted a");
    check mcpClient->close();

    string[] requestedScopes;
    lock {
        requestedScopes = e2eRequestedScopes.clone();
    }
    test:assertEquals(requestedScopes, ["mcp:tools", "mcp:tools files:write"]);
}
