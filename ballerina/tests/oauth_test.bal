// Copyright (c) 2026 WSO2 LLC (http://www.wso2.org) All Rights Reserved.
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

import ballerina/jwt;
import ballerina/test;

const ISSUER = "https://auth.example.com";

function preRegisteredConfig(ClientAuth clientAuth = {clientSecret: "secret"}) returns OAuthConfig => {
    grant: {
        clientConfig: {
            clientId: "reporting-agent",
            issuer: ISSUER,
            clientAuth
        }
    }
};

function clientCredentialsGrant(ClientAuth clientAuth = {clientSecret: "secret"})
        returns ClientCredentialsGrant => {
    clientConfig: {
        clientId: "reporting-agent",
        issuer: ISSUER,
        clientAuth
    }
};

function serverMetadata(string[]? methods = [CLIENT_SECRET_BASIC],
        string[]? algorithms = ()) returns AuthorizationServerMetadata => {
    issuer: ISSUER,
    token_endpoint: ISSUER + "/token",
    response_types_supported: ["code"],
    grant_types_supported: ["client_credentials"],
    token_endpoint_auth_methods_supported: methods,
    token_endpoint_auth_signing_alg_values_supported: algorithms
};

isolated function testRedirectHandler(string authorizationUrl) returns error? {
    _ = authorizationUrl;
}

isolated function testCallbackHandler() returns AuthorizationCallbackParams|error => {
    code: "authorization-code",
    state: "state"
};

function authorizationCodeGrant(string redirectUri = "http://127.0.0.1:3030/callback")
        returns AuthorizationCodeGrant => {
    clientConfig: {url: "https://client.example.com/oauth/metadata.json"},
    redirectUri,
    redirectHandler: testRedirectHandler,
    callbackHandler: testCallbackHandler
};

function authorizationCodeMetadata(string[]? pkceMethods = ["S256"])
        returns AuthorizationServerMetadata => {
    issuer: ISSUER,
    authorization_endpoint: ISSUER + "/authorize",
    token_endpoint: ISSUER + "/token",
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    token_endpoint_auth_methods_supported: ["none"],
    code_challenge_methods_supported: pkceMethods,
    client_id_metadata_document_supported: true
};

@test:Config {}
function testParseBearerChallenge() {
    BearerChallenge? parsed = parseBearerChallenge(
            "Bearer resource_metadata=\"https://mcp.example.com/metadata\", scope=\"files:read files:write\"");
    test:assertTrue(parsed is BearerChallenge);
    if parsed is BearerChallenge {
        test:assertEquals(parsed.resourceMetadata, "https://mcp.example.com/metadata");
        test:assertEquals(parsed.scope, "files:read files:write");
    }
    BearerChallenge? unquoted = parseBearerChallenge(
            "Bearer error=insufficient_scope, scope=\"files:write\"");
    test:assertTrue(unquoted is BearerChallenge);
    if unquoted is BearerChallenge {
        test:assertEquals(unquoted.errorCode, "insufficient_scope");
        test:assertEquals(unquoted.scope, "files:write");
    }
    BearerChallenge? escaped = parseBearerChallenge(
            "Bearer realm=\"a\\\"b\", error=insufficient_scope");
    test:assertTrue(escaped is BearerChallenge);
    if escaped is BearerChallenge {
        test:assertEquals(escaped.errorCode, "insufficient_scope");
    }
    test:assertTrue(parseBearerChallenge("Basic realm=\"mcp\"") is ());
}

@test:Config {}
function testBuildProtectedResourceMetadataUrls() returns error? {
    string[] urls = check buildProtectedResourceMetadataUrls("https://MCP.Example.com/Tenant/Mcp?view=full");
    test:assertEquals(urls, [
                "https://mcp.example.com/.well-known/oauth-protected-resource/Tenant/Mcp?view=full",
                "https://mcp.example.com/.well-known/oauth-protected-resource"
            ]);

    string[] trailingSlashUrls = check buildProtectedResourceMetadataUrls(
        "https://mcp.example.com/Tenant/Mcp/?view=full");
    test:assertEquals(trailingSlashUrls[0],
        "https://mcp.example.com/.well-known/oauth-protected-resource/Tenant/Mcp/?view=full");
}

@test:Config {}
function testBuildAuthorizationServerMetadataUrls() returns error? {
    string[] urls = check buildAuthorizationServerMetadataUrls("https://auth.example.com/tenant1");
    test:assertEquals(urls, [
                "https://auth.example.com/.well-known/oauth-authorization-server/tenant1",
                "https://auth.example.com/.well-known/openid-configuration/tenant1",
                "https://auth.example.com/tenant1/.well-known/openid-configuration"
            ]);
}

@test:Config {}
function testAuthorizationServerMetadataRequiresResponseTypes() {
    json payload = {
        issuer: ISSUER,
        token_endpoint: ISSUER + "/token",
        grant_types_supported: ["client_credentials"]
    };
    AuthorizationServerMetadata|error metadata = payload.cloneWithType();
    test:assertTrue(metadata is error);
}

@test:Config {}
function testCanonicalResourceUri() returns error? {
    test:assertEquals(check canonicalResourceUri(" HTTPS://MCP.Example.com/Tenant/Mcp/?view=full "),
            "https://mcp.example.com/Tenant/Mcp/?view=full");
    test:assertEquals(check canonicalResourceUri("https://MCP.Example.com/"),
            "https://mcp.example.com");
    test:assertEquals(check resourceOrigin("https://mcp.example.com/Tenant/Mcp?view=full"),
            "https://mcp.example.com");
    test:assertTrue(canonicalResourceUri("https://mcp.example.com/mcp#fragment") is Error);
}

@test:Config {}
function testValidatePreRegisteredClient() {
    test:assertTrue(validateConfig(preRegisteredConfig()) is ());

    OAuthConfig missingClientId = {
        grant: {
            clientConfig: {
                clientId: " ",
                issuer: ISSUER,
                clientAuth: {clientSecret: "secret"}
            }
        }
    };
    test:assertTrue(validateConfig(missingClientId) is Error);

    OAuthConfig insecureIssuer = {
        grant: {
            clientConfig: {
                clientId: "reporting-agent",
                issuer: "http://auth.example.com",
                clientAuth: {clientSecret: "secret"}
            }
        }
    };
    test:assertTrue(validateConfig(insecureIssuer) is Error);

    OAuthConfig issuerWithQuery = {
        grant: {
            clientConfig: {
                clientId: "reporting-agent",
                issuer: ISSUER + "?tenant=one",
                clientAuth: {clientSecret: "secret"}
            }
        }
    };
    test:assertTrue(validateConfig(issuerWithQuery) is Error);
    test:assertTrue(validateConfig(preRegisteredConfig({clientSecret: ""})) is Error);
}

@test:Config {}
function testValidateCimdClient() {
    OAuthConfig config = {
        grant: {
            clientConfig: {
                url: "https://client.example.com/oauth/metadata.json",
                clientAuth: {
                    signatureConfig: {
                        algorithm: jwt:RS256,
                        config: {keyFile: "private-key.pem"}
                    }
                }
            }
        }
    };
    test:assertTrue(validateConfig(config) is ());

    OAuthConfig rootUrl = {
        grant: {
            clientConfig: {
                url: "https://client.example.com/",
                clientAuth: {
                    signatureConfig: {config: {keyFile: "private-key.pem"}}
                }
            }
        }
    };
    test:assertTrue(validateConfig(rootUrl) is Error);
}

@test:Config {}
function testRejectSymmetricPrivateKeyJwt() {
    PrivateKeyJwtConfig symmetric = {
        signatureConfig: {algorithm: jwt:HS256, config: "shared-secret"}
    };
    test:assertTrue(validateConfig(preRegisteredConfig(symmetric)) is Error);
}

@test:Config {}
function testValidateAdvertisedClientAuthentication() {
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(), serverMetadata()) is ());
    // RFC 8414 defaults an omitted token_endpoint_auth_methods_supported value to
    // client_secret_basic.
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(), serverMetadata(())) is ());
    test:assertTrue(validateGrantAndClientAuthSupported(
                    clientCredentialsGrant({clientSecret: "secret", authMethod: CLIENT_SECRET_POST}),
                    serverMetadata()) is Error);

    PrivateKeyJwtConfig privateKeyJwt = {
        signatureConfig: {algorithm: jwt:RS256, config: {keyFile: "private-key.pem"}}
    };
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(privateKeyJwt),
                    serverMetadata(["private_key_jwt"], ["RS256"])) is ());
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(privateKeyJwt),
                    serverMetadata(["private_key_jwt"], ())) is Error);
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(privateKeyJwt),
                    serverMetadata(["private_key_jwt"], ["RS512"])) is Error);

    AuthorizationServerMetadata unsupportedGrant = serverMetadata();
    unsupportedGrant.grant_types_supported = ["authorization_code"];
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(), unsupportedGrant) is Error);

    AuthorizationServerMetadata defaultGrants = serverMetadata();
    defaultGrants.grant_types_supported = ();
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(), defaultGrants) is Error);

    AuthorizationServerMetadata malformedJwtMetadata = serverMetadata(
        [CLIENT_SECRET_BASIC, "private_key_jwt"], ());
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(), malformedJwtMetadata) is Error);
}

@test:Config {}
function testValidateAuthorizationCodeConfiguration() {
    OAuthConfig config = {grant: authorizationCodeGrant()};
    test:assertTrue(validateConfig(config) is ());

    OAuthConfig insecureRedirect = {
        grant: authorizationCodeGrant("http://client.example.com/callback")
    };
    test:assertTrue(validateConfig(insecureRedirect) is Error);
}

@test:Config {}
function testOAuthCapabilityMatchesConfiguredGrant() returns error? {
    ClientOAuthProvider clientCredentials = check new ("https://mcp.example.com/mcp", preRegisteredConfig());
    test:assertTrue(clientCredentials.usesClientCredentialsGrant());

    ClientOAuthProvider authorizationCode = check new ("https://mcp.example.com/mcp",
        {grant: authorizationCodeGrant()});
    test:assertFalse(authorizationCode.usesClientCredentialsGrant());
}

@test:Config {}
function testValidateAuthorizationCodeCapabilities() {
    AuthorizationCodeGrant grant = authorizationCodeGrant();
    test:assertTrue(validateGrantAndClientAuthSupported(
                    grant, authorizationCodeMetadata()) is ());
    test:assertTrue(validateGrantAndClientAuthSupported(
                    grant, authorizationCodeMetadata(())) is Error);
    test:assertTrue(validateGrantAndClientAuthSupported(
                    grant, authorizationCodeMetadata(["plain"])) is Error);
}

@test:Config {}
function testBuildAuthorizationCodeRequest() returns error? {
    AuthorizationCodeGrant grant = authorizationCodeGrant();
    [string, PendingAuthorization] [authorizationUrl, pending] = check buildAuthorizationRequest(
            grant, "https://client.example.com/oauth/metadata.json", authorizationCodeMetadata(),
            "https://mcp.example.com/mcp", ["files:read"]);
    test:assertTrue(authorizationUrl.startsWith(ISSUER + "/authorize?"));
    test:assertTrue(authorizationUrl.includes("response_type=code"));
    test:assertTrue(authorizationUrl.includes("code_challenge_method=S256"));
    test:assertTrue(authorizationUrl.includes("resource=https%3A%2F%2Fmcp.example.com%2Fmcp"));
    test:assertTrue(authorizationUrl.includes("scope=files%3Aread"));
    test:assertTrue(pending.codeVerifier.length() >= 43);
    test:assertTrue(validateAuthorizationResponse(authorizationCodeMetadata(), pending,
                    {code: "authorization-code", state: pending.state}) is ());
    test:assertTrue(validateAuthorizationResponse(authorizationCodeMetadata(), pending,
                    {code: "authorization-code", state: "incorrect"}) is Error);
}

@test:Config {}
function testApplyClientSecretAuthentication() returns error? {
    map<string> basicForm = {"grant_type": "client_credentials"};
    map<string|string[]> basicHeaders = {};
    check applyClientAuthentication({clientSecret: "s e+c"}, "id:one", ISSUER,
                                    basicForm, basicHeaders);
    test:assertEquals(basicForm, {"grant_type": "client_credentials"});
    test:assertEquals(basicHeaders["Authorization"], "Basic aWQlM0FvbmU6cytlJTJCYw==");

    map<string> postForm = {"grant_type": "client_credentials"};
    map<string|string[]> postHeaders = {};
    check applyClientAuthentication({clientSecret: "secret", authMethod: CLIENT_SECRET_POST},
                                    "reporting-agent", ISSUER, postForm, postHeaders);
    test:assertEquals(postForm, {
                                    "grant_type": "client_credentials",
                                    "client_id": "reporting-agent",
                                    "client_secret": "secret"
                                });
    test:assertEquals(postHeaders, {});

    map<string> publicClientForm = {"grant_type": "authorization_code"};
    map<string|string[]> publicClientHeaders = {};
    check applyClientAuthentication((), "public-client", ISSUER + "/token",
        publicClientForm, publicClientHeaders);
    test:assertEquals(publicClientForm["client_id"], "public-client");
    test:assertEquals(publicClientHeaders, {});
}

@test:Config {}
function testResolveCimdClientId() returns error? {
    CimdClientCredentialsConfig clientConfig = {
        url: "https://client.example.com/oauth/metadata.json",
        clientAuth: {signatureConfig: {config: {keyFile: "private-key.pem"}}}
    };
    test:assertTrue(resolveClientId(clientConfig, serverMetadata(["private_key_jwt"], ["RS256"])) is Error);

    AuthorizationServerMetadata metadata = serverMetadata(["private_key_jwt"], ["RS256"]);
    metadata.client_id_metadata_document_supported = true;
    test:assertEquals(check resolveClientId(clientConfig, metadata), clientConfig.url);
}

@test:Config {}
function testAuthorizationServerSelection() returns error? {
    ProtectedResourceMetadata resourceMetadata = {
        'resource: "https://mcp.example.com",
        authorization_servers: ["https://first.example.com", ISSUER]
    };
    PreRegisteredClientCredentialsConfig preRegistered = {
        clientId: "reporting-agent",
        issuer: ISSUER,
        clientAuth: {clientSecret: "secret"}
    };
    test:assertEquals(check selectAuthorizationServer(preRegistered, resourceMetadata,
                    resourceMetadata.'resource), ISSUER);

    preRegistered.issuer = "https://missing.example.com";
    test:assertTrue(selectAuthorizationServer(preRegistered, resourceMetadata,
                    resourceMetadata.'resource) is Error);

    CimdClientCredentialsConfig cimd = {
        url: "https://client.example.com/oauth/metadata.json",
        clientAuth: {signatureConfig: {config: {keyFile: "private-key.pem"}}}
    };
    test:assertEquals(check selectAuthorizationServer(cimd, resourceMetadata,
                    resourceMetadata.'resource), "https://first.example.com");
}

@test:Config {}
function testTokenStoreTracksGrantedScopes() {
    TokenStore tokenStore = new;
    test:assertTrue(tokenStore.getValidAccessToken() is ());
    tokenStore.update({access_token: "token", token_type: "Bearer", scope: "files:read"},
        ["files:read", "files:write"]);
    test:assertEquals(tokenStore.getValidAccessToken(), "token");
    test:assertEquals(tokenStore.getGrantedScopes(), ["files:read"]);

    tokenStore.update({access_token: "new-token", token_type: "Bearer"},
        ["files:read", "files:write"]);
    test:assertEquals(tokenStore.getValidAccessToken(), "new-token");
    test:assertEquals(tokenStore.getGrantedScopes(), ["files:read", "files:write"]);
    tokenStore.clear();
    test:assertTrue(tokenStore.getValidAccessToken() is ());
}
