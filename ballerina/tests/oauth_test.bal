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

isolated function testIdentityAssertionProvider(IdentityAssertionContext context)
        returns string|error {
    _ = context;
    return "header.payload.signature";
}

function identityAssertionGrant(ClientAuth clientAuth = {clientSecret: "secret"})
        returns IdentityAssertionGrant => {
    clientConfig: {
        clientId: "reporting-agent",
        issuer: ISSUER,
        clientAuth
    },
    assertionProvider: testIdentityAssertionProvider
};

function identityAssertionMetadata(string[]? profiles = [PROFILE_ID_JAG])
        returns AuthorizationServerMetadata => {
    issuer: ISSUER,
    token_endpoint: ISSUER + "/token",
    response_types_supported: ["code"],
    grant_types_supported: [GRANT_JWT_BEARER],
    token_endpoint_auth_methods_supported: [CLIENT_SECRET_BASIC],
    authorization_grant_profiles_supported: profiles
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
    // Without advertised signing algorithms, the configured algorithm is used.
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(privateKeyJwt),
                    serverMetadata(["private_key_jwt"], ())) is ());
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(privateKeyJwt),
                    serverMetadata(["private_key_jwt"], ["RS512"])) is Error);

    AuthorizationServerMetadata unsupportedGrant = serverMetadata();
    unsupportedGrant.grant_types_supported = ["authorization_code"];
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(), unsupportedGrant) is Error);

    AuthorizationServerMetadata defaultGrants = serverMetadata();
    defaultGrants.grant_types_supported = ();
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(), defaultGrants) is Error);

    AuthorizationServerMetadata noJwtAlgorithms = serverMetadata(
        [CLIENT_SECRET_BASIC, "private_key_jwt"], ());
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(), noJwtAlgorithms) is ());
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
function testValidateIdentityAssertionConfiguration() {
    OAuthConfig config = {grant: identityAssertionGrant()};
    test:assertTrue(validateConfig(config) is ());

    OAuthConfig invalid = {
        grant: {
            clientConfig: {
                clientId: " ",
                issuer: ISSUER,
                clientAuth: {clientSecret: "secret"}
            },
            assertionProvider: testIdentityAssertionProvider
        }
    };
    test:assertTrue(validateConfig(invalid) is Error);
}

@test:Config {}
function testValidateCimdIdentityAssertionConfiguration() {
    OAuthConfig publicClient = {
        grant: {
            clientConfig: {url: "https://client.example.com/oauth/metadata.json"},
            assertionProvider: testIdentityAssertionProvider
        }
    };
    test:assertTrue(validateConfig(publicClient) is ());

    OAuthConfig confidentialClient = {
        grant: {
            clientConfig: {
                url: "https://client.example.com/oauth/metadata.json",
                clientAuth: {
                    signatureConfig: {algorithm: jwt:RS256, config: {keyFile: "private-key.pem"}}
                }
            },
            assertionProvider: testIdentityAssertionProvider
        }
    };
    test:assertTrue(validateConfig(confidentialClient) is ());

    OAuthConfig rootUrl = {
        grant: {
            clientConfig: {url: "https://client.example.com/"},
            assertionProvider: testIdentityAssertionProvider
        }
    };
    test:assertTrue(validateConfig(rootUrl) is Error);

    OAuthConfig symmetricKey = {
        grant: {
            clientConfig: {
                url: "https://client.example.com/oauth/metadata.json",
                clientAuth: {signatureConfig: {algorithm: jwt:HS256, config: "shared-secret"}}
            },
            assertionProvider: testIdentityAssertionProvider
        }
    };
    test:assertTrue(validateConfig(symmetricKey) is Error);
}

@test:Config {}
function testValidatePublicPreRegisteredIdentityAssertionConfiguration() {
    OAuthConfig publicClient = {
        grant: {
            clientConfig: {clientId: "reporting-agent", issuer: ISSUER},
            assertionProvider: testIdentityAssertionProvider
        }
    };
    test:assertTrue(validateConfig(publicClient) is ());

    OAuthConfig insecureIssuer = {
        grant: {
            clientConfig: {clientId: "reporting-agent", issuer: "http://auth.example.com"},
            assertionProvider: testIdentityAssertionProvider
        }
    };
    test:assertTrue(validateConfig(insecureIssuer) is Error);
}

@test:Config {}
function testCimdIdentityAssertionClientAuthentication() {
    IdentityAssertionGrant publicGrant = {
        clientConfig: {url: "https://client.example.com/oauth/metadata.json"},
        assertionProvider: testIdentityAssertionProvider
    };
    test:assertTrue(grantClientAuth(publicGrant) is ());

    AuthorizationServerMetadata publicMetadata = identityAssertionMetadata();
    publicMetadata.token_endpoint_auth_methods_supported = [METHOD_NONE];
    test:assertTrue(validateGrantAndClientAuthSupported(publicGrant, publicMetadata) is ());
    test:assertTrue(validateGrantAndClientAuthSupported(publicGrant, identityAssertionMetadata()) is Error);
}

@test:Config {}
function testValidateIdentityAssertionCapabilities() {
    IdentityAssertionGrant grant = identityAssertionGrant();
    test:assertTrue(validateGrantAndClientAuthSupported(
                    grant, identityAssertionMetadata()) is ());

    // The profile metadata is RECOMMENDED rather than required by the underlying draft.
    test:assertTrue(validateGrantAndClientAuthSupported(
                    grant, identityAssertionMetadata(())) is ());

    AuthorizationServerMetadata wrongProfile = identityAssertionMetadata(["example-profile"]);
    test:assertTrue(validateGrantAndClientAuthSupported(grant, wrongProfile) is Error);

    AuthorizationServerMetadata wrongGrant = identityAssertionMetadata();
    wrongGrant.grant_types_supported = [GRANT_AUTHORIZATION_CODE];
    test:assertTrue(validateGrantAndClientAuthSupported(grant, wrongGrant) is Error);
}

@test:Config {}
function testOAuthCapabilityMatchesConfiguredGrant() returns error? {
    ClientOAuthProvider clientCredentials = check new ("https://mcp.example.com/mcp", preRegisteredConfig());
    test:assertEquals(clientCredentials.oauthExtension(), OAUTH_CLIENT_CREDENTIALS_EXTENSION);

    ClientOAuthProvider authorizationCode = check new ("https://mcp.example.com/mcp",
        {grant: authorizationCodeGrant()});
    test:assertTrue(authorizationCode.oauthExtension() is ());

    ClientOAuthProvider identityAssertion = check new ("https://mcp.example.com/mcp",
        {grant: identityAssertionGrant()});
    test:assertEquals(identityAssertion.oauthExtension(), ENTERPRISE_MANAGED_AUTHORIZATION_EXTENSION);
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
function testBuildIdentityAssertionRequests() {
    map<string> accessTokenForm = buildIdentityAssertionAccessTokenForm("id-jag",
        "https://mcp.example.com/mcp", ["files:read", "files:write"]);
    test:assertEquals(accessTokenForm, {
        "grant_type": GRANT_JWT_BEARER,
        "assertion": "id-jag",
        "resource": "https://mcp.example.com/mcp",
        "scope": "files:read files:write"
    });

    map<string> unscopedForm = buildIdentityAssertionAccessTokenForm("id-jag",
        "https://mcp.example.com/mcp");
    test:assertEquals(unscopedForm, {
        "grant_type": GRANT_JWT_BEARER,
        "assertion": "id-jag",
        "resource": "https://mcp.example.com/mcp"
    });

    map<string> exchangeForm = buildTokenExchangeForm({
        subjectToken: "id-token",
        subjectTokenType: TOKEN_TYPE_ID_TOKEN,
        requestedTokenType: TOKEN_TYPE_ID_JAG,
        audience: ISSUER,
        'resource: "https://mcp.example.com/mcp",
        scopes: ["files:read", "files:write"]
    });
    test:assertEquals(exchangeForm, {
        "grant_type": GRANT_TOKEN_EXCHANGE,
        "requested_token_type": TOKEN_TYPE_ID_JAG,
        "audience": ISSUER,
        "resource": "https://mcp.example.com/mcp",
        "scope": "files:read files:write",
        "subject_token": "id-token",
        "subject_token_type": TOKEN_TYPE_ID_TOKEN
    });

    // An exchange without a target, such as a SAML assertion for a refresh token
    // (ID-JAG section 4.5), omits audience and resource.
    map<string> untargetedForm = buildTokenExchangeForm({
        subjectToken: "saml-assertion",
        subjectTokenType: TOKEN_TYPE_SAML2,
        requestedTokenType: TOKEN_TYPE_REFRESH_TOKEN,
        scopes: ["openid", "offline_access"]
    });
    test:assertEquals(untargetedForm, {
        "grant_type": GRANT_TOKEN_EXCHANGE,
        "requested_token_type": TOKEN_TYPE_REFRESH_TOKEN,
        "scope": "openid offline_access",
        "subject_token": "saml-assertion",
        "subject_token_type": TOKEN_TYPE_SAML2
    });
}

@test:Config {}
function testParseTokenExchangeResponse() returns error? {
    TokenExchangeResponse idJag = check parseTokenExchangeResponse({
        "access_token": "header.payload.signature",
        "issued_token_type": TOKEN_TYPE_ID_JAG,
        "token_type": "N_A",
        "expires_in": 300,
        "refresh_token": "must-be-ignored"
    }, TOKEN_TYPE_ID_JAG, ISSUER + "/token");
    test:assertEquals(idJag.access_token, "header.payload.signature");

    // The issued token type must be the requested one.
    test:assertTrue(parseTokenExchangeResponse({
        "access_token": "header.payload.signature",
        "issued_token_type": "urn:example:wrong",
        "token_type": "N_A"
    }, TOKEN_TYPE_ID_JAG, ISSUER + "/token") is Error);
    test:assertTrue(parseTokenExchangeResponse({
        "access_token": "idp-refresh-token",
        "issued_token_type": TOKEN_TYPE_REFRESH_TOKEN,
        "token_type": "N_A"
    }, TOKEN_TYPE_ID_JAG, ISSUER + "/token") is Error);
    TokenExchangeResponse refreshToken = check parseTokenExchangeResponse({
        "access_token": "idp-refresh-token",
        "issued_token_type": TOKEN_TYPE_REFRESH_TOKEN,
        "token_type": "N_A"
    }, TOKEN_TYPE_REFRESH_TOKEN, ISSUER + "/token");
    test:assertEquals(refreshToken.access_token, "idp-refresh-token");

    // Token type values are case-insensitive.
    TokenExchangeResponse lowerCase = check parseTokenExchangeResponse({
        "access_token": "header.payload.signature",
        "issued_token_type": TOKEN_TYPE_ID_JAG,
        "token_type": "n_a"
    }, TOKEN_TYPE_ID_JAG, ISSUER + "/token");
    test:assertEquals(lowerCase.access_token, "header.payload.signature");
    test:assertTrue(parseTokenExchangeResponse({
        "access_token": "header.payload.signature",
        "issued_token_type": TOKEN_TYPE_ID_JAG,
        "token_type": "Bearer"
    }, TOKEN_TYPE_ID_JAG, ISSUER + "/token") is Error);
}

@test:Config {}
function testValidateIdentityProviderCapabilities() {
    ClientSecretConfig postSecret = {clientSecret: "secret", authMethod: CLIENT_SECRET_POST};
    IdentityProviderMetadata metadata = {
        issuer: "https://idp.example.com",
        token_endpoint: "https://idp.example.com/token",
        grant_types_supported: [GRANT_TOKEN_EXCHANGE],
        token_endpoint_auth_methods_supported: [CLIENT_SECRET_POST],
        identity_chaining_requested_token_types_supported: [TOKEN_TYPE_ID_JAG]
    };
    test:assertTrue(validateTokenExchangeSupported(postSecret, metadata) is ());
    test:assertTrue(validateIdJagIssuanceSupported(metadata) is ());

    metadata.identity_chaining_requested_token_types_supported = ["urn:example:wrong"];
    test:assertTrue(validateIdJagIssuanceSupported(metadata) is Error);
    // The ID-JAG check is separate, so other exchanges are unaffected by it.
    test:assertTrue(validateTokenExchangeSupported(postSecret, metadata) is ());

    IdentityProviderMetadata withoutTokenExchange = {
        issuer: "https://idp.example.com",
        token_endpoint: "https://idp.example.com/token",
        grant_types_supported: [GRANT_AUTHORIZATION_CODE]
    };
    test:assertTrue(validateTokenExchangeSupported(postSecret, withoutTokenExchange) is Error);

    IdentityProviderMetadata unsupportedAuthMethod = {
        issuer: "https://idp.example.com",
        token_endpoint: "https://idp.example.com/token",
        token_endpoint_auth_methods_supported: [CLIENT_SECRET_BASIC]
    };
    test:assertTrue(validateTokenExchangeSupported(postSecret, unsupportedAuthMethod) is Error);

    // Capabilities are checked only when advertised, and a public client is allowed.
    IdentityProviderMetadata minimal = {
        issuer: "https://idp.example.com",
        token_endpoint: "https://idp.example.com/token"
    };
    test:assertTrue(validateTokenExchangeSupported(postSecret, minimal) is ());
    test:assertTrue(validateTokenExchangeSupported((), minimal) is ());
    test:assertTrue(validateIdJagIssuanceSupported(minimal) is ());
}

@test:Config {}
function testIdentityProviderMetadataRequiresOnlyIssuerAndTokenEndpoint() {
    json minimal = {issuer: "https://idp.example.com", token_endpoint: "https://idp.example.com/token"};
    test:assertTrue(minimal.cloneWithType(IdentityProviderMetadata) is IdentityProviderMetadata);
    // Authorization server metadata still requires response_types_supported.
    test:assertTrue(minimal.cloneWithType(AuthorizationServerMetadata) is error);

    json missingTokenEndpoint = {issuer: "https://idp.example.com"};
    test:assertTrue(missingTokenEndpoint.cloneWithType(IdentityProviderMetadata) is error);
}

@test:Config {}
function testTokenErrorKeepsErrorResponseFields() {
    Error reauthenticate = buildOAuthTokenError(ISSUER + "/token", 400, {
        "error": "insufficient_user_authentication",
        "error_description": "Authentication is too old",
        "error_uri": "https://idp.example.com/errors/reauth",
        "max_age": 5
    });
    test:assertTrue(reauthenticate is OAuthTokenError);
    test:assertFalse(reauthenticate is OAuthInvalidGrantError);
    if reauthenticate is OAuthTokenError {
        OAuthTokenErrorDetail detail = reauthenticate.detail();
        test:assertEquals(detail?.code, "insufficient_user_authentication");
        test:assertEquals(detail?.description, "Authentication is too old");
        test:assertEquals(detail?.errorUri, "https://idp.example.com/errors/reauth");
        test:assertEquals(detail?.statusCode, 400);
        test:assertEquals(detail?.maxAge, 5);
    }

    Error invalidGrant = buildOAuthTokenError(ISSUER + "/token", 400, {"error": "invalid_grant"});
    test:assertTrue(invalidGrant is OAuthInvalidGrantError);
    if invalidGrant is OAuthTokenError {
        test:assertEquals(invalidGrant.detail()?.code, "invalid_grant");
        test:assertEquals(invalidGrant.detail()?.statusCode, 400);
    }

    Error unparsable = buildOAuthTokenError(ISSUER + "/token", 503, error("not JSON"));
    test:assertTrue(unparsable is OAuthTokenError);
    if unparsable is OAuthTokenError {
        test:assertEquals(unparsable.detail()?.code, ());
        test:assertEquals(unparsable.detail()?.statusCode, 503);
    }
}

@test:Config {}
function testLimitToAssertionScopes() {
    string idJag = unsignedJwt({"scope": "files:read files:admin"});
    test:assertEquals(limitToAssertionScopes(["files:read", "files:write"], idJag), ["files:read"]);
    // A claim that grants none of the requested scopes leaves nothing to request.
    test:assertEquals(limitToAssertionScopes(["files:write"], idJag), []);
    // Without a readable scope claim, the ID-JAG does not say what it grants.
    test:assertEquals(limitToAssertionScopes(["files:read"], unsignedJwt({"sub": "user"})), ());
    test:assertEquals(limitToAssertionScopes(["files:read"], "not-a-jwt"), ());
}

// Builds an unsigned JWT for tests that only inspect claims.
isolated function unsignedJwt(map<json> claims) returns string =>
    string `${base64Url({"alg": "none", "typ": "oauth-id-jag+jwt"})}.${base64Url(claims)}.signature`;

isolated function base64Url(json value) returns string {
    string encoded = value.toJsonString().toBytes().toBase64();
    encoded = re `\+`.replaceAll(encoded, "-");
    encoded = re `/`.replaceAll(encoded, "_");
    return re `=+$`.replaceAll(encoded, "");
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

    // A public client uses the same selection rules as a confidential one.
    PreRegisteredClientConfig publicPreRegistered = {clientId: "reporting-agent", issuer: ISSUER};
    test:assertEquals(check selectAuthorizationServer(publicPreRegistered, resourceMetadata,
                    resourceMetadata.'resource), ISSUER);

    CimdClientConfig publicCimd = {url: "https://client.example.com/oauth/metadata.json"};
    test:assertEquals(check selectAuthorizationServer(publicCimd, resourceMetadata,
                    resourceMetadata.'resource), "https://first.example.com");
}

@test:Config {}
function testResolveCimdIdentityAssertionClientId() returns error? {
    CimdClientConfig clientConfig = {url: "https://client.example.com/oauth/metadata.json"};
    test:assertTrue(resolveClientId(clientConfig, identityAssertionMetadata()) is Error);

    AuthorizationServerMetadata metadata = identityAssertionMetadata();
    metadata.client_id_metadata_document_supported = true;
    test:assertEquals(check resolveClientId(clientConfig, metadata), clientConfig.url);
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

    tokenStore.update({
        access_token: "identity-token",
        token_type: "Bearer",
        refresh_token: "must-not-be-stored"
    }, ["files:read"], DISCARD_REFRESH_TOKEN);
    test:assertTrue(tokenStore.getRefreshToken() is ());
    tokenStore.clear();
    test:assertTrue(tokenStore.getValidAccessToken() is ());
}

@test:Config {}
function testTokenStoreRefreshTokenHandling() {
    TokenStore tokenStore = new;
    tokenStore.update({access_token: "a", token_type: "Bearer", refresh_token: "first"}, []);
    test:assertEquals(tokenStore.getRefreshToken(), "first");

    // A refresh response without a refresh token keeps the held one only when preserving.
    tokenStore.update({access_token: "b", token_type: "Bearer"}, [], PRESERVE_REFRESH_TOKEN);
    test:assertEquals(tokenStore.getRefreshToken(), "first");
    tokenStore.update({access_token: "c", token_type: "Bearer", refresh_token: "rotated"}, [],
        PRESERVE_REFRESH_TOKEN);
    test:assertEquals(tokenStore.getRefreshToken(), "rotated");

    tokenStore.update({access_token: "d", token_type: "Bearer"}, []);
    test:assertTrue(tokenStore.getRefreshToken() is ());
}
