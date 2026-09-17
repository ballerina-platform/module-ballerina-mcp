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
    ClientCapabilities capabilities = withOAuthClientCredentialsCapability({
        extensions: {"example.com/custom": {}}
    });
    map<record {}>? extensions = capabilities.extensions;
    test:assertTrue(extensions is map<record {}>);
    if extensions is map<record {}> {
        test:assertTrue(extensions.hasKey(OAUTH_CLIENT_CREDENTIALS_EXTENSION));
        test:assertTrue(extensions.hasKey("example.com/custom"));
    }
}
