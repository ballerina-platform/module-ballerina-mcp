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
import ballerina/test;

isolated function printAuthorizationUrl(string authorizationUrl) returns error? {
    _ = authorizationUrl;
}

isolated function receiveAuthorizationResponse() returns AuthorizationCallbackParams|error => {
    code: "authorization-code",
    state: "state"
};

isolated function provideIdentityAssertion(IdentityAssertionContext context) returns string|error {
    _ = context;
    return "header.payload.signature";
}

@test:Config {}
isolated function testCimdWithPrivateKeyJwt() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {
                    url: "https://wso2.com/mcp/client.json",
                    clientAuth: {
                        signatureConfig: {config: {keyFile: "./client-private.key"}},
                        keyId: "mcp-signing-1"
                    }
                }
            }
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testPreRegisteredWithClientSecret() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {
                    clientId: "reporting-agent",
                    issuer: "https://auth.example.com",
                    clientAuth: {clientSecret: "s3cr3t"}
                }
            },
            scopes: ["mcp:read"]
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testIdentityAssertionWithPreRegisteredClient() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {
                    clientId: "reporting-agent",
                    issuer: "https://auth.example.com",
                    clientAuth: {clientSecret: "s3cr3t"}
                },
                assertionProvider: provideIdentityAssertion
            },
            scopes: ["mcp:read"]
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testIdentityAssertionWithCimdClient() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {
                    url: "https://wso2.com/mcp/client.json",
                    clientAuth: {
                        signatureConfig: {config: {keyFile: "./client-private.key"}},
                        keyId: "mcp-signing-1"
                    }
                },
                assertionProvider: provideIdentityAssertion
            }
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testGrantClientConfigShapes() {
    readonly & map<anydata> publicPreRegistered = {clientId: "agent", issuer: "https://auth.example.com"};
    test:assertTrue(publicPreRegistered is OAuthClientConfig);
    test:assertFalse(publicPreRegistered is ClientCredentialsClientConfig);

    readonly & map<anydata> confidentialPreRegistered = {
        clientId: "agent",
        issuer: "https://auth.example.com",
        clientAuth: {clientSecret: "s3cr3t", authMethod: CLIENT_SECRET_BASIC}
    };
    test:assertTrue(confidentialPreRegistered is OAuthClientConfig);
    test:assertTrue(confidentialPreRegistered is ClientCredentialsClientConfig);

    readonly & map<anydata> publicCimd = {url: "https://wso2.com/mcp/client.json"};
    test:assertTrue(publicCimd is OAuthClientConfig);
    test:assertFalse(publicCimd is ClientCredentialsClientConfig);

    readonly & map<anydata> confidentialCimd = {
        url: "https://wso2.com/mcp/client.json",
        clientAuth: {signatureConfig: {algorithm: "RS256", config: {keyFile: "./client-private.key"}}}
    };
    test:assertTrue(confidentialCimd is OAuthClientConfig);
    test:assertTrue(confidentialCimd is ClientCredentialsClientConfig);

    // A CIMD client cannot hold a shared secret.
    readonly & map<anydata> cimdWithSecret = {
        url: "https://wso2.com/mcp/client.json",
        clientAuth: {clientSecret: "s3cr3t", authMethod: CLIENT_SECRET_BASIC}
    };
    test:assertFalse(cimdWithSecret is OAuthClientConfig);
}

@test:Config {}
isolated function testIdentityAssertionWithPublicCimdClient() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {url: "https://wso2.com/mcp/client.json"},
                assertionProvider: provideIdentityAssertion
            }
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testIdentityAssertionWithPublicPreRegisteredClient() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {clientId: "reporting-agent", issuer: "https://auth.example.com"},
                assertionProvider: provideIdentityAssertion
            }
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testClientSecretInPostBody() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {
                    clientId: "reporting-agent",
                    issuer: "https://auth.example.com",
                    clientAuth: {clientSecret: "s3cr3t", authMethod: CLIENT_SECRET_POST}
                }
            }
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testCimdPublicAuthorizationCodeClient() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {url: "https://wso2.com/mcp/client.json"},
                redirectUri: "http://127.0.0.1:3030/callback",
                redirectHandler: printAuthorizationUrl,
                callbackHandler: receiveAuthorizationResponse
            }
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testPreRegisteredAuthorizationCodeClientWithSecret() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {
                    clientId: "interactive-client",
                    issuer: "https://auth.example.com",
                    clientAuth: {clientSecret: "s3cr3t"}
                },
                redirectUri: "https://client.example.com/oauth/callback",
                redirectHandler: printAuthorizationUrl,
                callbackHandler: receiveAuthorizationResponse
            }
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testCimdAuthorizationCodeWithMutualTls() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {
                    url: "https://wso2.com/mcp/client.json",
                    clientAuth: {
                        key: {certFile: "./client.crt", keyFile: "./client.key"},
                        authMethod: SELF_SIGNED_TLS_CLIENT_AUTH
                    }
                },
                redirectUri: "http://127.0.0.1:3030/callback",
                redirectHandler: printAuthorizationUrl,
                callbackHandler: receiveAuthorizationResponse
            }
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testPreRegisteredClientCredentialsWithMutualTls() {
    StreamableHttpClientConfig config = {
        auth: {
            grant: {
                clientConfig: {
                    clientId: "reporting-agent",
                    issuer: "https://auth.example.com",
                    clientAuth: {
                        key: {path: "./client-keystore.p12", password: "changeit"},
                        authMethod: TLS_CLIENT_AUTH
                    }
                }
            }
        }
    };
    test:assertTrue(config.auth is OAuthConfig);
}

@test:Config {}
isolated function testStaticCredentialIsUnaffected() {
    StreamableHttpClientConfig config = {auth: {token: "sk-abc123"}};
    test:assertTrue(config.auth is http:ClientAuthConfig);
}

@test:Config {}
isolated function testNoAuthorizationConfigured() {
    StreamableHttpClientConfig config = {};
    test:assertTrue(config.auth is ());
}

@test:Config {}
isolated function testOAuthClientCredentialsCapability() {
    ClientCapabilities capabilities = withOAuthExtensionCapability({
        extensions: {"example.com/custom": {}}
    }, OAUTH_CLIENT_CREDENTIALS_EXTENSION);
    map<record {}>? extensions = capabilities.extensions;
    test:assertTrue(extensions is map<record {}>);
    if extensions is map<record {}> {
        test:assertTrue(extensions.hasKey(OAUTH_CLIENT_CREDENTIALS_EXTENSION));
        test:assertTrue(extensions.hasKey("example.com/custom"));
    }
}

@test:Config {}
isolated function testEnterpriseManagedAuthorizationCapability() {
    ClientCapabilities capabilities = withOAuthExtensionCapability({
        extensions: {"example.com/custom": {}}
    }, ENTERPRISE_MANAGED_AUTHORIZATION_EXTENSION);
    map<record {}>? extensions = capabilities.extensions;
    test:assertTrue(extensions is map<record {}>);
    if extensions is map<record {}> {
        test:assertTrue(extensions.hasKey(ENTERPRISE_MANAGED_AUTHORIZATION_EXTENSION));
        test:assertFalse(extensions.hasKey(OAUTH_CLIENT_CREDENTIALS_EXTENSION));
        test:assertTrue(extensions.hasKey("example.com/custom"));
    }
}

@test:Config {}
isolated function testNoOAuthExtensionCapability() {
    ClientCapabilities capabilities = withOAuthExtensionCapability({}, ());
    test:assertTrue(capabilities.extensions is ());
}

@test:Config {}
isolated function testTransportReportsOAuthExtension() returns error? {
    StreamableHttpClientTransport identityAssertion = check new ("https://mcp.example.com/mcp", auth = {
        grant: {
            clientConfig: {
                clientId: "reporting-agent",
                issuer: "https://auth.example.com",
                clientAuth: {clientSecret: "s3cr3t"}
            },
            assertionProvider: provideIdentityAssertion
        }
    });
    test:assertEquals(identityAssertion.oauthExtension(), ENTERPRISE_MANAGED_AUTHORIZATION_EXTENSION);

    StreamableHttpClientTransport unauthenticated = check new ("https://mcp.example.com/mcp");
    test:assertTrue(unauthenticated.oauthExtension() is ());
}
