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

// Exercises the full identity assertion acquisition path of `ClientOAuthProvider`:
// discovery, the assertion provider callback, the jwt-bearer request, scope bookkeeping and
// step-up. Only the network edges are mocked: metadata retrieval (`fetchJson`) and the
// token endpoint (`postTokenRequest`).

import ballerina/test;

const FLOW_SERVER_URL = "https://mcp.example.com/mcp";
const FLOW_PRM_URL = "https://mcp.example.com/.well-known/oauth-protected-resource/mcp";
const FLOW_FIRST_ISSUER = "https://first.example.com";
const FLOW_CIMD_URL = "https://client.example.com/oauth/metadata.json";
const FLOW_IDP_ISSUER = "https://idp.example.com";
const FLOW_IDP_ISSUED_ID_JAG = "idp.issued.id-jag";

@test:Mock {functionName: "fetchJson"}
test:MockFunction fetchJsonMock = new;

@test:Mock {functionName: "postTokenRequest"}
test:MockFunction postTokenRequestMock = new;

// An unstubbed mock fails every call, so other tests use the real network functions unless a
// test stubs them.
@test:BeforeSuite
function useRealIdentityAssertionNetwork() {
    restoreIdentityAssertionNetwork();
}

// A token request observed by the mocked endpoint.
type RecordedTokenRequest record {|
    string tokenEndpoint;
    string clientId;
    string authMethod;
    map<string> form;
|};

isolated IdentityAssertionContext[] recordedAssertionContexts = [];
isolated RecordedTokenRequest[] recordedTokenRequests = [];

isolated function mockFetchJson(string targetUrl, readonly & AuthHttpConfig config,
        ClientObserver? observer = (), ClientEventTarget eventTarget = AUTHORIZATION_SERVER)
        returns json|Error {
    if targetUrl == FLOW_PRM_URL {
        return {"resource": FLOW_SERVER_URL, "authorization_servers": [FLOW_FIRST_ISSUER, ISSUER]};
    }
    // The Identity Provider publishes only OpenID Connect discovery, with minimal metadata.
    if targetUrl == FLOW_IDP_ISSUER + "/.well-known/openid-configuration" {
        return {
            "issuer": FLOW_IDP_ISSUER,
            "token_endpoint": FLOW_IDP_ISSUER + "/token",
            "grant_types_supported": [GRANT_TOKEN_EXCHANGE]
        };
    }
    foreach string issuer in [ISSUER, FLOW_FIRST_ISSUER] {
        if targetUrl == issuer + "/.well-known/oauth-authorization-server" {
            return {
                "issuer": issuer,
                "token_endpoint": issuer + "/token",
                "response_types_supported": ["code"],
                "grant_types_supported": [GRANT_JWT_BEARER],
                "token_endpoint_auth_methods_supported": [CLIENT_SECRET_BASIC, METHOD_NONE],
                "authorization_grant_profiles_supported": [PROFILE_ID_JAG],
                "client_id_metadata_document_supported": true
            };
        }
    }
    return error OAuthDiscoveryError(string `Unexpected metadata request to '${targetUrl}'.`);
}

isolated function mockPostTokenRequest(ClientAuth? clientAuth, string clientId,
        AuthorizationServerMetadata|IdentityProviderMetadata metadata, map<string> form,
        readonly & AuthHttpConfig config, ClientObserver? observer = ()) returns json|Error {
    string tokenEndpoint = selectTokenEndpoint(clientAuth, metadata);
    RecordedTokenRequest & readonly request = {
        tokenEndpoint,
        clientId,
        authMethod: clientAuthMethodName(clientAuth),
        form: form.cloneReadOnly()
    };
    int count;
    lock {
        recordedTokenRequests.push(request);
        count = recordedTokenRequests.length();
    }
    if tokenEndpoint == FLOW_IDP_ISSUER + "/token" {
        return {
            "access_token": FLOW_IDP_ISSUED_ID_JAG,
            "issued_token_type": TOKEN_TYPE_ID_JAG,
            "token_type": "N_A",
            "expires_in": 300
        };
    }
    // The response omits `scope` and includes a refresh token the grant must discard.
    return {
        "access_token": string `mcp-token-${count}`,
        "token_type": "Bearer",
        "expires_in": 3600,
        "refresh_token": "must-be-discarded"
    };
}

// Returns an ID-JAG whose `scope` claim narrows `files:write` away.
isolated function recordingAssertionProvider(IdentityAssertionContext context) returns string|error {
    lock {
        recordedAssertionContexts.push(context);
    }
    return unsignedJwt({"scope": "files:read files:admin"});
}

isolated function failingAssertionProvider(IdentityAssertionContext context) returns string|error {
    return error("The IdP refused the exchange.");
}

isolated function emptyAssertionProvider(IdentityAssertionContext context) returns string|error => " ";

function stubIdentityAssertionNetwork() {
    lock {
        recordedAssertionContexts = [];
    }
    lock {
        recordedTokenRequests = [];
    }
    test:when(fetchJsonMock).call("mockFetchJson");
    test:when(postTokenRequestMock).call("mockPostTokenRequest");
}

function restoreIdentityAssertionNetwork() {
    test:when(fetchJsonMock).callOriginal();
    test:when(postTokenRequestMock).callOriginal();
}

function assertionContexts() returns IdentityAssertionContext[] {
    lock {
        return recordedAssertionContexts.clone();
    }
}

function tokenRequests() returns RecordedTokenRequest[] {
    lock {
        return recordedTokenRequests.clone();
    }
}

@test:Config {
    before: stubIdentityAssertionNetwork,
    after: restoreIdentityAssertionNetwork
}
function testIdentityAssertionAcquisitionAndStepUp() returns error? {
    ClientOAuthProvider provider = check new (FLOW_SERVER_URL, {
        grant: {
            clientConfig: {clientId: "reporting-agent", issuer: ISSUER, clientAuth: {clientSecret: "secret"}},
            assertionProvider: recordingAssertionProvider
        },
        scopes: ["files:read", "files:write"]
    });

    string header = check provider.getAuthorizationHeader({resourceMetadata: FLOW_PRM_URL});
    test:assertEquals(header, "Bearer mcp-token-1");

    // The callback receives the discovered, pinned Resource AS and the PRM resource.
    IdentityAssertionContext[] contexts = assertionContexts();
    test:assertEquals(contexts.length(), 1);
    test:assertEquals(contexts[0], {
        audience: ISSUER,
        'resource: FLOW_SERVER_URL,
        clientId: "reporting-agent",
        scopes: ["files:read", "files:write"]
    });

    // The jwt-bearer request carries resource and scope, with confidential client authentication.
    RecordedTokenRequest[] requests = tokenRequests();
    test:assertEquals(requests.length(), 1);
    test:assertEquals(requests[0].tokenEndpoint, ISSUER + "/token");
    test:assertEquals(requests[0].clientId, "reporting-agent");
    test:assertEquals(requests[0].authMethod, CLIENT_SECRET_BASIC);
    test:assertEquals(requests[0].form, {
        "grant_type": GRANT_JWT_BEARER,
        "assertion": unsignedJwt({"scope": "files:read files:admin"}),
        "resource": FLOW_SERVER_URL,
        "scope": "files:read files:write"
    });

    // The cached token is reused without another exchange.
    test:assertEquals(check provider.getAuthorizationHeader(), "Bearer mcp-token-1");
    test:assertEquals(assertionContexts().length(), 1);

    // Step-up obtains a fresh ID-JAG. The union is built from the scopes the ID-JAG allowed,
    // so `files:write`, which the Identity Provider removed, is not requested again.
    string steppedUp = check provider.getAuthorizationHeader({
        resourceMetadata: FLOW_PRM_URL,
        errorCode: ERROR_INSUFFICIENT_SCOPE,
        scope: "files:admin"
    });
    test:assertEquals(steppedUp, "Bearer mcp-token-2");
    contexts = assertionContexts();
    test:assertEquals(contexts.length(), 2);
    test:assertEquals(contexts[1].scopes, ["files:read", "files:admin"]);
    test:assertEquals(tokenRequests()[1].form["scope"], "files:read files:admin");
}

@test:Config {
    before: stubIdentityAssertionNetwork,
    after: restoreIdentityAssertionNetwork
}
function testIdentityAssertionWithPublicCimdClientFlow() returns error? {
    ClientOAuthProvider provider = check new (FLOW_SERVER_URL, {
        grant: {
            clientConfig: {url: FLOW_CIMD_URL},
            assertionProvider: recordingAssertionProvider
        },
        scopes: ["files:read"]
    });

    test:assertEquals(check provider.getAuthorizationHeader({resourceMetadata: FLOW_PRM_URL}),
        "Bearer mcp-token-1");

    // A CIMD client takes the first authorization server listed in the resource metadata and
    // uses its document URL as the client identifier.
    IdentityAssertionContext context = assertionContexts()[0];
    test:assertEquals(context.audience, FLOW_FIRST_ISSUER);
    test:assertEquals(context.clientId, FLOW_CIMD_URL);

    RecordedTokenRequest request = tokenRequests()[0];
    test:assertEquals(request.tokenEndpoint, FLOW_FIRST_ISSUER + "/token");
    test:assertEquals(request.clientId, FLOW_CIMD_URL);
    // A public client authenticates with `none`, which sends only `client_id`.
    test:assertEquals(request.authMethod, METHOD_NONE);
}

@test:Config {
    before: stubIdentityAssertionNetwork,
    after: restoreIdentityAssertionNetwork
}
function testIdentityAssertionProviderFailures() returns error? {
    ClientOAuthProvider failing = check new (FLOW_SERVER_URL, {
        grant: {
            clientConfig: {clientId: "reporting-agent", issuer: ISSUER, clientAuth: {clientSecret: "secret"}},
            assertionProvider: failingAssertionProvider
        }
    });
    string|Error failed = failing.getAuthorizationHeader({resourceMetadata: FLOW_PRM_URL});
    test:assertTrue(failed is OAuthAuthorizationError);
    if failed is Error {
        test:assertEquals((<error>failed.cause()).message(), "The IdP refused the exchange.");
    }

    ClientOAuthProvider empty = check new (FLOW_SERVER_URL, {
        grant: {
            clientConfig: {clientId: "reporting-agent", issuer: ISSUER, clientAuth: {clientSecret: "secret"}},
            assertionProvider: emptyAssertionProvider
        }
    });
    test:assertTrue(empty.getAuthorizationHeader({resourceMetadata: FLOW_PRM_URL}) is OAuthAuthorizationError);

    // Neither failure reaches the Resource Authorization Server.
    test:assertEquals(tokenRequests().length(), 0);
}

@test:Config {
    before: stubIdentityAssertionNetwork,
    after: restoreIdentityAssertionNetwork
}
function testExchangeIdTokenForIdJag() returns error? {
    IdentityAssertionContext context = {
        audience: ISSUER,
        'resource: FLOW_SERVER_URL,
        clientId: "reporting-agent",
        scopes: ["files:read"]
    };
    IdentityProviderConfig idp = {
        issuer: FLOW_IDP_ISSUER,
        clientId: "idp-client",
        clientAuth: {clientSecret: "idp-secret", authMethod: CLIENT_SECRET_POST}
    };

    test:assertEquals(check exchangeIdTokenForIdJag("id-token", context, idp), FLOW_IDP_ISSUED_ID_JAG);

    // The helper discovers the Identity Provider's token endpoint and sends the token
    // exchange built from the context.
    RecordedTokenRequest[] requests = tokenRequests();
    test:assertEquals(requests.length(), 1);
    test:assertEquals(requests[0].tokenEndpoint, FLOW_IDP_ISSUER + "/token");
    test:assertEquals(requests[0].clientId, "idp-client");
    test:assertEquals(requests[0].authMethod, CLIENT_SECRET_POST);
    test:assertEquals(requests[0].form, {
        "grant_type": GRANT_TOKEN_EXCHANGE,
        "requested_token_type": TOKEN_TYPE_ID_JAG,
        "audience": ISSUER,
        "resource": FLOW_SERVER_URL,
        "scope": "files:read",
        "subject_token": "id-token",
        "subject_token_type": TOKEN_TYPE_ID_TOKEN
    });

    test:assertTrue(exchangeIdTokenForIdJag(" ", context, idp) is Error);
    test:assertEquals(tokenRequests().length(), 1);
}
