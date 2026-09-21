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
import ballerina/lang.array;
import ballerina/lang.regexp;

# Exchanges an OpenID Connect ID token for a fresh Identity Assertion JWT
# Authorization Grant (ID-JAG) at the OpenID Provider. The application remains
# responsible for the OpenID Connect login and for supplying a current ID token.
#
# This function does not cache either token. It discovers and validates the OpenID
# Provider metadata, then performs the RFC 8693 token exchange required by
# Enterprise-Managed Authorization.
#
# + idToken - ID token issued to the application by the OpenID Provider
# + context - Resource Authorization Server, MCP resource, client, and scope values
# supplied to an `IdentityAssertionProvider`
# + config - OpenID Provider registration and HTTP configuration
# + return - A fresh ID-JAG, or an `Error`
public isolated function exchangeIdTokenForIdJag(string idToken,
        IdentityAssertionContext context, IdentityProviderConfig config)
        returns string|Error {
    if idToken.trim() == "" {
        return error OAuthConfigError("'idToken' must not be empty.");
    }
    IdentityProvider idp = check prepareIdentityProvider(config);
    check validateIdJagIssuanceSupported(idp.metadata);
    TokenExchangeResponse response = check requestTokenExchange(idp, {
        subjectToken: idToken,
        subjectTokenType: TOKEN_TYPE_ID_TOKEN,
        requestedTokenType: TOKEN_TYPE_ID_JAG,
        audience: context.audience,
        'resource: context.'resource,
        scopes: context.scopes
    });
    // RFC 8693 permits a refresh token in the response, but the ID-JAG profile recommends
    // against it. It is ignored along with the ID-JAG lifetime: callers receive only the
    // fresh assertion, and this module never caches it.
    return response.access_token;
}

// A validated and discovered Identity Provider ready for RFC 8693 token exchanges.
type IdentityProvider record {|
    string clientId;
    ClientAuth? clientAuth;
    IdentityProviderMetadata metadata;
    readonly & AuthHttpConfig httpConfig;
|};

// Prepares an Identity Provider and checks capabilities shared by every token exchange.
// Exchange-specific capabilities are checked by the caller.
isolated function prepareIdentityProvider(IdentityProviderConfig config) returns IdentityProvider|Error {
    if config.clientId.trim() == "" {
        return error OAuthConfigError("'clientId' must not be empty.");
    }
    check validateHttpsUrl(config.issuer, "issuer", false, false);
    ClientAuth? clientAuth = config?.clientAuth;
    if clientAuth is ClientAuth {
        check validateClientAuthentication(clientAuth);
    }

    AuthHttpConfig httpConfig = {
        timeout: config.timeout,
        httpVersion: config.httpVersion
    };
    http:ClientSecureSocket? secureSocket = config?.secureSocket;
    if secureSocket is http:ClientSecureSocket {
        httpConfig.secureSocket = secureSocket;
    }
    http:ProxyConfig? proxy = config?.proxy;
    if proxy is http:ProxyConfig {
        httpConfig.proxy = proxy;
    }
    readonly & AuthHttpConfig pinnedHttpConfig = httpConfig.cloneReadOnly();

    IdentityProviderMetadata metadata =
        check discoverIdentityProviderMetadata(config.issuer, pinnedHttpConfig);
    check validateTokenExchangeSupported(clientAuth, metadata);
    return {clientId: config.clientId, clientAuth, metadata, httpConfig: pinnedHttpConfig};
}

// Checks capabilities only when advertised; omission does not mean the exchange is unsupported.
isolated function validateTokenExchangeSupported(ClientAuth? clientAuth,
        IdentityProviderMetadata metadata) returns Error? {
    string[]? advertisedGrantTypes = metadata.grant_types_supported;
    if advertisedGrantTypes is string[] && advertisedGrantTypes.indexOf(GRANT_TOKEN_EXCHANGE) is () {
        return error OAuthConfigError(string `OpenID Provider '${metadata.issuer}' advertises ` +
            string `'grant_types_supported' but does not include the token exchange grant.`);
    }
    if metadata.token_endpoint_auth_methods_supported is () {
        return;
    }
    return validateClientAuthSupported(clientAuth, metadata);
}

// Checks ID-JAG support when the Identity Provider advertises identity-chaining token types.
isolated function validateIdJagIssuanceSupported(IdentityProviderMetadata metadata) returns Error? {
    string[]? advertisedTokenTypes = metadata.identity_chaining_requested_token_types_supported;
    if advertisedTokenTypes is string[] && advertisedTokenTypes.indexOf(TOKEN_TYPE_ID_JAG) is () {
        return error OAuthConfigError(string `OpenID Provider '${metadata.issuer}' advertises ` +
            string `'identity_chaining_requested_token_types_supported' but does not include ID-JAG.`);
    }
}

isolated function requestIdentityAssertionAccessToken(string idJag, string clientId,
        ClientAuth? clientAuth, AuthorizationServerMetadata metadata, string resourceUri,
        string[] scopes = [], readonly & AuthHttpConfig clientConfig = {}, ClientObserver? observer = ())
        returns TokenResponse|Error {
    map<string> form = buildIdentityAssertionAccessTokenForm(idJag, resourceUri, scopes);
    return requestToken(clientAuth, metadata, clientId, form, clientConfig, observer);
}

// Builds the RFC 7523 jwt-bearer request, including MCP's required `resource`. The requested
// `scope` confers no authority, and must not exceed what the ID-JAG grants (RFC 7521
// section 4.1).
isolated function buildIdentityAssertionAccessTokenForm(string idJag, string resourceUri,
        string[] scopes = []) returns map<string> {
    map<string> form = {
        "grant_type": GRANT_JWT_BEARER,
        "assertion": idJag,
        "resource": resourceUri
    };
    if scopes.length() > 0 {
        form["scope"] = string:'join(" ", ...scopes);
    }
    return form;
}

// Returns the requested scopes that the ID-JAG's `scope` claim grants, or `()` when the ID-JAG
// carries no readable `scope` claim. The IdP reflects any narrowing in that claim, so it caps
// what the Resource AS request may ask for. The unverified claim is never used to authorize
// anything.
isolated function limitToAssertionScopes(string[] scopes, string idJag) returns string[]? {
    string[] parts = re `\.`.split(idJag);
    if parts.length() != 3 {
        return ();
    }
    string payloadSegment = regexp:replaceAll(re `_`, regexp:replaceAll(re `-`, parts[1], "+"), "/");
    while payloadSegment.length() % 4 != 0 {
        payloadSegment += "=";
    }
    byte[]|error payloadBytes = array:fromBase64(payloadSegment);
    if payloadBytes is error {
        return ();
    }
    string|error payloadText = string:fromBytes(payloadBytes);
    json|error claims = payloadText is string ? payloadText.fromJsonString() : payloadText;
    if claims !is map<json> {
        return ();
    }
    json assertionScope = claims["scope"];
    if assertionScope !is string {
        return ();
    }
    string[] authorized = splitScopes(assertionScope);
    string[] limited = [];
    foreach string scope in scopes {
        if authorized.indexOf(scope) is int {
            limited.push(scope);
        }
    }
    return limited;
}

// An RFC 8693 exchange request. Optional targets also accommodate the untargeted SAML
// assertion-to-refresh-token exchange described by ID-JAG section 4.5.
type TokenExchangeRequest record {|
    string subjectToken;
    string subjectTokenType;
    string requestedTokenType;
    string audience?;
    string 'resource?;
    string[] scopes = [];
|};

// Performs an RFC 8693 exchange and validates the returned token type.
isolated function requestTokenExchange(IdentityProvider idp, TokenExchangeRequest request)
        returns TokenExchangeResponse|Error {
    string tokenEndpoint = selectTokenEndpoint(idp.clientAuth, idp.metadata);
    json payload = check postTokenRequest(idp.clientAuth, idp.clientId, tokenEndpoint,
            buildTokenExchangeForm(request), idp.httpConfig);
    return parseTokenExchangeResponse(payload, request.requestedTokenType, tokenEndpoint);
}

isolated function buildTokenExchangeForm(TokenExchangeRequest request) returns map<string> {
    map<string> form = {
        "grant_type": GRANT_TOKEN_EXCHANGE,
        "requested_token_type": request.requestedTokenType,
        "subject_token": request.subjectToken,
        "subject_token_type": request.subjectTokenType
    };
    string? audience = request?.audience;
    if audience is string {
        form["audience"] = audience;
    }
    string? targetResource = request?.'resource;
    if targetResource is string {
        form["resource"] = targetResource;
    }
    if request.scopes.length() > 0 {
        form["scope"] = string:'join(" ", ...request.scopes);
    }
    return form;
}

// These exchanges issue non-access tokens, so `token_type` must be `N_A`.
isolated function parseTokenExchangeResponse(json payload, string requestedTokenType,
        string tokenEndpoint) returns TokenExchangeResponse|Error {
    TokenExchangeResponse|error response = payload.cloneWithType();
    if response is error {
        return error OAuthTokenError(string `Response from OpenID Provider token endpoint ` +
            string `'${tokenEndpoint}' is not a valid token exchange response.`, response);
    }
    if response.access_token.trim() == "" {
        return error OAuthTokenError(string `Response from OpenID Provider token endpoint ` +
            string `'${tokenEndpoint}' contains an empty token.`);
    }
    if response.issued_token_type != requestedTokenType {
        return error OAuthTokenError(string `Response from OpenID Provider token endpoint ` +
            string `'${tokenEndpoint}' contains issued token type '${response.issued_token_type}', ` +
            string `but '${requestedTokenType}' was requested.`);
    }
    if !response.token_type.equalsIgnoreCaseAscii("N_A") {
        return error OAuthTokenError(string `Response from OpenID Provider token endpoint ` +
            string `'${tokenEndpoint}' contains unexpected token type '${response.token_type}'.`);
    }
    int? lifetime = response?.expires_in;
    if lifetime is int && lifetime <= 0 {
        return error OAuthTokenError(string `Response from OpenID Provider token endpoint ` +
            string `'${tokenEndpoint}' contains a non-positive 'expires_in' value.`);
    }
    return response;
}
