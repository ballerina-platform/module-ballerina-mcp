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

import ballerina/crypto;
import ballerina/lang.regexp;
import ballerina/uuid;

const string PKCE_CHALLENGE_METHOD = "S256";

type Pkce record {|
    string verifier;
    string codeChallenge;
|};

type PendingAuthorization record {|
    string codeVerifier;
    string state;
    string expectedIssuer;
    string clientId;
    string redirectUri;
    string resourceUri;
|};

# Builds an authorization request URL using PKCE with `S256`.
#
# + grant - Authorization code configuration
# + clientId - Resolved client identifier
# + metadata - Validated authorization server metadata
# + resourceUri - Canonical MCP resource identifier
# + scopes - Scopes to request
# + return - Authorization URL and state retained for the code exchange
isolated function buildAuthorizationRequest(AuthorizationCodeGrant grant, string clientId,
        AuthorizationServerMetadata metadata, string resourceUri, string[] scopes = [])
        returns [string, PendingAuthorization]|Error {
    string? authorizationEndpoint = metadata.authorization_endpoint;
    if authorizationEndpoint is () {
        return error OAuthConfigError(string `Authorization server '${metadata.issuer}' does not ` +
            string `publish an 'authorization_endpoint'.`);
    }
    check validateHttpsUrl(authorizationEndpoint, "authorization_endpoint", false, true);

    Pkce pkce = generatePkce();
    string state = generateRandomToken(1);
    map<string> params = {
        "response_type": "code",
        "client_id": clientId,
        "redirect_uri": grant.redirectUri,
        "state": state,
        "code_challenge": pkce.codeChallenge,
        "code_challenge_method": PKCE_CHALLENGE_METHOD,
        "resource": resourceUri
    };
    if scopes.length() > 0 {
        params["scope"] = string:'join(" ", ...scopes);
    }

    string query = check encodeForm(params);
    string separator = authorizationEndpoint.includes("?") ? "&" : "?";
    PendingAuthorization pending = {
        codeVerifier: pkce.verifier,
        state: state,
        expectedIssuer: metadata.issuer,
        clientId: clientId,
        redirectUri: grant.redirectUri,
        resourceUri: resourceUri
    };
    return [authorizationEndpoint + separator + query, pending];
}

# Validates an authorization response and exchanges its code for tokens.
#
# + clientAuth - Token endpoint authentication, or `()` for a public client
# + metadata - Validated authorization server metadata
# + pending - State retained from the authorization request
# + params - Parameters returned to the redirect URI
# + config - HTTP settings for the token request
# + observer - Optional observer for token endpoint events
# + return - Token response, or an OAuth error
isolated function completeAuthorization(ClientAuth? clientAuth,
        AuthorizationServerMetadata metadata, PendingAuthorization pending,
        AuthorizationCallbackParams params, readonly & AuthHttpConfig config = {},
        ClientObserver? observer = ())
        returns TokenResponse|Error {
    check validateAuthorizationResponse(metadata, pending, params);
    string? authorizationCode = params.code;
    if authorizationCode is () || authorizationCode.trim() == "" {
        return error OAuthAuthorizationError(
            "The authorization response did not contain an authorization code.");
    }
    map<string> form = {
        "grant_type": GRANT_AUTHORIZATION_CODE,
        "code": authorizationCode,
        "redirect_uri": pending.redirectUri,
        "code_verifier": pending.codeVerifier,
        "resource": pending.resourceUri
    };
    return requestToken(clientAuth, metadata, pending.clientId, form, config, observer);
}

# Exchanges a refresh token for a new access token.
#
# + clientAuth - Token endpoint authentication, or `()` for a public client
# + metadata - Validated authorization server metadata
# + clientId - Resolved client identifier
# + refreshToken - Previously issued refresh token
# + resourceUri - Canonical MCP resource identifier
# + scopes - Scopes to preserve on the refreshed token
# + config - HTTP settings for the token request
# + observer - Optional observer for token endpoint events
# + return - Token response, or an OAuth error
isolated function refreshAccessToken(ClientAuth? clientAuth,
        AuthorizationServerMetadata metadata, string clientId, string refreshToken,
        string resourceUri, string[] scopes = [], readonly & AuthHttpConfig config = {},
        ClientObserver? observer = ())
        returns TokenResponse|Error {
    map<string> form = {
        "grant_type": "refresh_token",
        "refresh_token": refreshToken,
        "resource": resourceUri
    };
    if scopes.length() > 0 {
        form["scope"] = string:'join(" ", ...scopes);
    }
    return requestToken(clientAuth, metadata, clientId, form, config, observer);
}

isolated function validateAuthorizationResponse(AuthorizationServerMetadata metadata,
        PendingAuthorization pending, AuthorizationCallbackParams params) returns Error? {
    string? returnedState = params.state;
    if returnedState is () {
        return error OAuthAuthorizationError(
            "The authorization response carried no 'state' parameter.");
    }
    if returnedState != pending.state {
        return error OAuthAuthorizationError(
            "The 'state' parameter in the authorization response does not match the value sent.");
    }

    boolean issAdvertised = metadata.authorization_response_iss_parameter_supported ?: false;
    string? returnedIssuer = params.iss;
    if returnedIssuer is () {
        if issAdvertised {
            return error OAuthAuthorizationError(string `Authorization server '${metadata.issuer}' ` +
                string `advertises the RFC 9207 issuer parameter, but the authorization response ` +
                string `carried no 'iss' parameter.`);
        }
    } else if returnedIssuer != pending.expectedIssuer {
        return error OAuthAuthorizationError(string `The authorization response issuer ` +
            string `'${returnedIssuer}' does not match '${pending.expectedIssuer}'.`);
    }

    string? authorizationError = params.'error;
    if authorizationError is string {
        string? description = params.errorDescription;
        string detail = description is string
            ? string `'${authorizationError}': ${description}`
            : string `'${authorizationError}'`;
        return error OAuthAuthorizationError(
            string `Authorization server '${metadata.issuer}' returned ${detail}.`);
    }
}

isolated function generatePkce() returns Pkce {
    string verifier = generateRandomToken(2);
    byte[] digest = crypto:hashSha256(verifier.toBytes());
    return {verifier: verifier, codeChallenge: base64UrlEncode(digest)};
}

isolated function generateRandomToken(int segments) returns string {
    string token = "";
    int index = 0;
    while index < segments {
        token += regexp:replaceAll(re `-`, uuid:createType4AsString(), "");
        index += 1;
    }
    return token;
}

isolated function base64UrlEncode(byte[] data) returns string {
    string encoded = data.toBase64();
    encoded = regexp:replaceAll(re `\+`, encoded, "-");
    encoded = regexp:replaceAll(re `/`, encoded, "_");
    return regexp:replaceAll(re `=`, encoded, "");
}
