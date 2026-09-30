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

import ballerina/http;
import ballerina/jwt;
import ballerina/test;

const MTLS_RESOURCES = "tests/resources/mtls/";
const MTLS_CLIENT_ID = "https://client.example.com/oauth/mtls-client.json";
const MTLS_TOKEN_ENDPOINT = "https://localhost:3220/oauth/token";
const PLAIN_TOKEN_ENDPOINT = "https://localhost:3221/oauth/token";
const MTLS_RESOURCE_URI = "https://mcp.example.com/mcp";

// Requires a client certificate signed by, or equal to, `client.crt`.
listener http:Listener mtlsTokenListener = new (3220, {
    secureSocket: {
        key: {certFile: MTLS_RESOURCES + "server.crt", keyFile: MTLS_RESOURCES + "server.key"},
        mutualSsl: {verifyClient: http:REQUIRE, cert: MTLS_RESOURCES + "client.crt"}
    }
});

// Serves TLS without requesting a client certificate, standing in for the conventional
// token endpoint when `mtls_endpoint_aliases` is published.
listener http:Listener plainTokenListener = new (3221, {
    secureSocket: {
        key: {certFile: MTLS_RESOURCES + "server.crt", keyFile: MTLS_RESOURCES + "server.key"}
    }
});

service /oauth on mtlsTokenListener {
    resource function post token(http:Request request) returns http:Ok|http:Unauthorized|error {
        map<string> form = check request.getFormParams();
        http:MutualSslHandshake? handshake = request.mutualSslHandshake;
        boolean certificateVerified = handshake is http:MutualSslHandshake && handshake.status == http:PASSED;
        // RFC 8705 section 2: the client is identified by `client_id` and authenticated by
        // the handshake alone.
        if !certificateVerified || form["client_id"] != MTLS_CLIENT_ID ||
                form.hasKey("client_assertion") || form.hasKey("client_secret") ||
                request.hasHeader("Authorization") {
            return <http:Unauthorized>{body: {'error: "invalid_client"}};
        }
        return <http:Ok>{body: {access_token: "mtls-token", token_type: "Bearer", expires_in: 3600}};
    }
}

service /oauth on plainTokenListener {
    resource function post token() returns http:Ok {
        return {body: {access_token: "plain-token", token_type: "Bearer", expires_in: 3600}};
    }
}

// The test server certificate is self-signed, so the client trusts it explicitly. This also
// shows that the transport trust store is kept when the client certificate is added.
final readonly & AuthHttpConfig trustTestServer = {secureSocket: {cert: MTLS_RESOURCES + "server.crt"}};

function mutualTlsAuth(string keyName = "client",
        MutualTlsAuthMethod authMethod = SELF_SIGNED_TLS_CLIENT_AUTH) returns MutualTlsConfig => {
    key: {certFile: MTLS_RESOURCES + keyName + ".crt", keyFile: MTLS_RESOURCES + keyName + ".key"},
    authMethod
};

function mutualTlsMetadata(string tokenEndpoint, string? aliasTokenEndpoint = ())
        returns AuthorizationServerMetadata {
    AuthorizationServerMetadata metadata = {
        issuer: ISSUER,
        token_endpoint: tokenEndpoint,
        response_types_supported: ["code"],
        grant_types_supported: ["client_credentials", "refresh_token"],
        token_endpoint_auth_methods_supported: ["self_signed_tls_client_auth", "none"]
    };
    if aliasTokenEndpoint is string {
        metadata.mtls_endpoint_aliases = {token_endpoint: aliasTokenEndpoint};
    }
    return metadata;
}

@test:Config {}
function testMutualTlsClientCredentialsUsesEndpointAlias() returns error? {
    TokenResponse response = check requestClientCredentialsToken(MTLS_CLIENT_ID, mutualTlsAuth(),
            mutualTlsMetadata(PLAIN_TOKEN_ENDPOINT, MTLS_TOKEN_ENDPOINT), MTLS_RESOURCE_URI,
            clientConfig = trustTestServer);
    test:assertEquals(response.access_token, "mtls-token");
}

@test:Config {}
function testMutualTlsRefreshUsesTokenEndpoint() returns error? {
    TokenResponse response = check refreshAccessToken(mutualTlsAuth(),
            mutualTlsMetadata(MTLS_TOKEN_ENDPOINT), MTLS_CLIENT_ID, "refresh-token",
            MTLS_RESOURCE_URI, config = trustTestServer);
    test:assertEquals(response.access_token, "mtls-token");
}

@test:Config {}
function testMutualTlsRejectsUnregisteredCertificate() {
    TokenResponse|Error response = requestClientCredentialsToken(MTLS_CLIENT_ID,
            mutualTlsAuth("untrusted"), mutualTlsMetadata(MTLS_TOKEN_ENDPOINT), MTLS_RESOURCE_URI,
            clientConfig = trustTestServer);
    test:assertTrue(response is OAuthTokenError);
}

@test:Config {}
function testClientCertificateOnlySentForMutualTls() returns error? {
    // A public client ignores the alias and presents no certificate.
    TokenResponse response = check refreshAccessToken((),
            mutualTlsMetadata(PLAIN_TOKEN_ENDPOINT, MTLS_TOKEN_ENDPOINT), MTLS_CLIENT_ID,
            "refresh-token", MTLS_RESOURCE_URI, config = trustTestServer);
    test:assertEquals(response.access_token, "plain-token");

    TokenResponse|Error rejected = refreshAccessToken((), mutualTlsMetadata(MTLS_TOKEN_ENDPOINT),
            MTLS_CLIENT_ID, "refresh-token", MTLS_RESOURCE_URI, config = trustTestServer);
    test:assertTrue(rejected is OAuthTokenError);
}

@test:Config {}
function testSelectTokenEndpoint() {
    AuthorizationServerMetadata aliased = mutualTlsMetadata(PLAIN_TOKEN_ENDPOINT, MTLS_TOKEN_ENDPOINT);
    test:assertEquals(selectTokenEndpoint(mutualTlsAuth(), aliased), MTLS_TOKEN_ENDPOINT);
    test:assertEquals(selectTokenEndpoint(mutualTlsAuth(), mutualTlsMetadata(PLAIN_TOKEN_ENDPOINT)),
            PLAIN_TOKEN_ENDPOINT);
    test:assertEquals(selectTokenEndpoint({clientSecret: "secret"}, aliased), PLAIN_TOKEN_ENDPOINT);
    PrivateKeyJwtConfig privateKeyJwt = {signatureConfig: {config: {keyFile: "private-key.pem"}}};
    test:assertEquals(selectTokenEndpoint(privateKeyJwt, aliased), PLAIN_TOKEN_ENDPOINT);
}

@test:Config {}
function testWithClientCertificateKeepsTrustStore() {
    MutualTlsConfig clientAuth = mutualTlsAuth();
    AuthHttpConfig config = withClientCertificate(trustTestServer, clientAuth);
    test:assertEquals(config?.secureSocket?.cert, MTLS_RESOURCES + "server.crt");
    test:assertEquals(config?.secureSocket?.key, clientAuth.key);
    test:assertTrue(trustTestServer?.secureSocket?.key is ());

    AuthHttpConfig withoutSecureSocket = withClientCertificate({}, clientAuth);
    test:assertEquals(withoutSecureSocket?.secureSocket?.key, clientAuth.key);
}

@test:Config {}
function testApplyMutualTlsAuthentication() returns error? {
    map<string> form = {"grant_type": "client_credentials"};
    map<string|string[]> headers = {};
    check applyClientAuthentication(mutualTlsAuth(), MTLS_CLIENT_ID, MTLS_TOKEN_ENDPOINT, form, headers);
    test:assertEquals(form, {"grant_type": "client_credentials", "client_id": MTLS_CLIENT_ID});
    test:assertEquals(headers, {});
}

@test:Config {}
function testValidateMutualTlsConfig() {
    test:assertTrue(validateConfig(preRegisteredConfig(mutualTlsAuth(authMethod = TLS_CLIENT_AUTH))) is ());

    MutualTlsConfig missingKeyFile = {
        key: {certFile: MTLS_RESOURCES + "client.crt", keyFile: " "},
        authMethod: TLS_CLIENT_AUTH
    };
    test:assertTrue(validateConfig(preRegisteredConfig(missingKeyFile)) is Error);

    MutualTlsConfig missingKeyStore = {
        key: {path: "", password: "secret"},
        authMethod: SELF_SIGNED_TLS_CLIENT_AUTH
    };
    test:assertTrue(validateConfig(preRegisteredConfig(missingKeyStore)) is Error);

    OAuthConfig cimd = {
        grant: {
            clientConfig: {url: MTLS_CLIENT_ID, clientAuth: mutualTlsAuth()}
        }
    };
    test:assertTrue(validateConfig(cimd) is ());
}

@test:Config {}
function testValidateAdvertisedMutualTls() {
    AuthorizationServerMetadata selfSigned = serverMetadata(["self_signed_tls_client_auth"]);
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(mutualTlsAuth()),
                    selfSigned) is ());
    test:assertTrue(validateGrantAndClientAuthSupported(
                    clientCredentialsGrant(mutualTlsAuth(authMethod = TLS_CLIENT_AUTH)), selfSigned) is Error);
    // Advertised JWT client authentication does not affect a mutual TLS client.
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(mutualTlsAuth()),
                    serverMetadata(["self_signed_tls_client_auth", "private_key_jwt"], ["RS256"])) is ());
    PrivateKeyJwtConfig privateKeyJwt = {
        signatureConfig: {algorithm: jwt:RS256, config: {keyFile: "private-key.pem"}}
    };
    test:assertTrue(validateGrantAndClientAuthSupported(clientCredentialsGrant(privateKeyJwt),
                    selfSigned) is Error);
}

@test:Config {}
function testSelectIdentityProviderTokenEndpoint() {
    IdentityProviderMetadata idp = {
        issuer: "https://idp.example.com",
        token_endpoint: "https://idp.example.com/token",
        mtls_endpoint_aliases: {token_endpoint: "https://mtls.idp.example.com/token"}
    };
    // The ID-JAG token exchange follows the same RFC 8705 endpoint selection.
    test:assertEquals(selectTokenEndpoint(mutualTlsAuth(), idp), "https://mtls.idp.example.com/token");
    test:assertEquals(selectTokenEndpoint({clientSecret: "secret"}, idp), "https://idp.example.com/token");
    test:assertEquals(selectTokenEndpoint((), idp), "https://idp.example.com/token");
}
