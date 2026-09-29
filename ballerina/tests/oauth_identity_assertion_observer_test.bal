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

// Observes the ID token to ID-JAG exchange performed by `exchangeIdTokenForIdJag` against a
// local HTTPS Identity Provider.

import ballerina/http;
import ballerina/test;

const OBSERVED_IDP_ISSUER = "https://localhost:3222";
const OBSERVED_ID_TOKEN = "observed.id.token";
const OBSERVED_ID_JAG = "observed.id-jag.assertion";

// Publishes only OpenID Connect discovery, as many Identity Providers do.
listener http:Listener observedIdentityProviderListener = new (3222, {
    secureSocket: {
        key: {certFile: MTLS_RESOURCES + "server.crt", keyFile: MTLS_RESOURCES + "server.key"}
    }
});

service / on observedIdentityProviderListener {
    resource function get \.well\-known/openid\-configuration() returns json => {
        issuer: OBSERVED_IDP_ISSUER,
        token_endpoint: OBSERVED_IDP_ISSUER + "/token",
        grant_types_supported: [GRANT_TOKEN_EXCHANGE],
        token_endpoint_auth_methods_supported: [CLIENT_SECRET_POST]
    };

    resource function post token(http:Request request) returns http:Ok|http:BadRequest|error {
        map<string> form = check request.getFormParams();
        if form["grant_type"] != GRANT_TOKEN_EXCHANGE || form["subject_token"] != OBSERVED_ID_TOKEN {
            return <http:BadRequest>{body: {'error: "invalid_grant"}};
        }
        return <http:Ok>{
            body: {
                access_token: OBSERVED_ID_JAG,
                issued_token_type: TOKEN_TYPE_ID_JAG,
                token_type: "N_A",
                expires_in: 300
            }
        };
    }
}

final readonly & IdentityProviderConfig observedIdentityProvider = {
    issuer: OBSERVED_IDP_ISSUER,
    clientId: "observed-idp-client",
    clientAuth: {clientSecret: "observed-idp-secret", authMethod: CLIENT_SECRET_POST},
    // The test server certificate is self-signed, so the client trusts it explicitly.
    secureSocket: {cert: MTLS_RESOURCES + "server.crt"}
};

final readonly & IdentityAssertionContext observedAssertionContext = {
    audience: ISSUER,
    'resource: "https://mcp.example.com/mcp",
    clientId: "reporting-agent",
    scopes: ["files:read"]
};

@test:Config {}
function testIdJagExchangeEmitsIdentityProviderEvents() returns error? {
    RecordingObserver eventObserver = new;
    string idJag = check exchangeIdTokenForIdJag(OBSERVED_ID_TOKEN, observedAssertionContext,
        observedIdentityProvider, eventObserver);
    test:assertEquals(idJag, OBSERVED_ID_JAG);

    (readonly & ClientEvent)[] eventList = eventObserver.getEvents();
    // Every event of the exchange is reported against the Identity Provider.
    foreach readonly & ClientEvent clientEvent in eventList {
        test:assertEquals(clientEvent.eventTarget, IDENTITY_PROVIDER);
    }

    // Discovery tries the RFC 8414 location first; this Identity Provider answers it with 404
    // and serves its metadata from OpenID Connect discovery.
    readonly & ClientEvent? metadataBody = ();
    foreach readonly & ClientEvent clientEvent in eventList {
        if clientEvent.eventType == HTTP_BODY && clientEvent.statusCode == 200 {
            metadataBody = clientEvent;
        }
    }
    test:assertTrue(metadataBody is readonly & ClientEvent);
    if metadataBody is readonly & ClientEvent {
        test:assertEquals(metadataBody.eventUrl, OBSERVED_IDP_ISSUER + "/.well-known/openid-configuration");
    }

    readonly & ClientEvent? tokenRequest = ();
    foreach readonly & ClientEvent clientEvent in eventList {
        if clientEvent.eventType == HTTP_REQUEST && clientEvent.httpMethod == "POST" {
            tokenRequest = clientEvent;
        }
    }
    test:assertTrue(tokenRequest is readonly & ClientEvent);
    if tokenRequest is readonly & ClientEvent {
        test:assertEquals(tokenRequest.eventUrl, OBSERVED_IDP_ISSUER + "/token");
        string requestBody = tokenRequest.eventBody ?: "";
        test:assertTrue(requestBody.includes(TOKEN_TYPE_ID_JAG));
        test:assertTrue(requestBody.includes(REDACTED_VALUE));
    }

    readonly & ClientEvent? acquired = findEvent(eventList, TOKEN_ACQUIRED, IDENTITY_PROVIDER);
    test:assertTrue(acquired is readonly & ClientEvent);
    if acquired is readonly & ClientEvent {
        test:assertEquals(acquired.eventUrl, OBSERVED_IDP_ISSUER + "/token");
    }

    // Neither the ID token, the ID-JAG, nor the client secret reaches the observer.
    test:assertFalse(bodyContains(eventList, OBSERVED_ID_TOKEN));
    test:assertFalse(bodyContains(eventList, OBSERVED_ID_JAG));
    test:assertFalse(bodyContains(eventList, "observed-idp-secret"));
}

@test:Config {}
function testIdJagExchangeWithoutObserver() returns error? {
    // The observer is optional, so existing callers are unaffected.
    test:assertEquals(check exchangeIdTokenForIdJag(OBSERVED_ID_TOKEN, observedAssertionContext,
        observedIdentityProvider), OBSERVED_ID_JAG);
}

@test:Config {}
function testIdJagExchangeFailureIsObserved() {
    RecordingObserver eventObserver = new;
    string|Error rejected = exchangeIdTokenForIdJag("unknown.id.token", observedAssertionContext,
        observedIdentityProvider, eventObserver);
    test:assertTrue(rejected is OAuthInvalidGrantError);

    // The rejection is visible as the Identity Provider's response status, and no ID-JAG is
    // reported as acquired.
    (readonly & ClientEvent)[] eventList = eventObserver.getEvents();
    boolean rejectedResponse = false;
    foreach readonly & ClientEvent clientEvent in eventList {
        if clientEvent.eventType == HTTP_RESPONSE && clientEvent.httpMethod == "POST" &&
                clientEvent.statusCode == 400 && clientEvent.eventTarget == IDENTITY_PROVIDER {
            rejectedResponse = true;
        }
    }
    test:assertTrue(rejectedResponse);
    test:assertTrue(findEvent(eventList, TOKEN_ACQUIRED, IDENTITY_PROVIDER) is ());
}

@test:Config {}
function testIdentityAssertionTokensAreRedacted() {
    map<string> sanitized = sanitizedTokenParameters({
        "grant_type": GRANT_JWT_BEARER,
        "assertion": "id-jag",
        "subject_token": "id-token",
        "actor_token": "actor-token",
        "subject_token_type": TOKEN_TYPE_ID_TOKEN
    });
    test:assertEquals(sanitized, {
        "grant_type": GRANT_JWT_BEARER,
        "assertion": REDACTED_VALUE,
        "subject_token": REDACTED_VALUE,
        "actor_token": REDACTED_VALUE,
        "subject_token_type": TOKEN_TYPE_ID_TOKEN
    });
}
