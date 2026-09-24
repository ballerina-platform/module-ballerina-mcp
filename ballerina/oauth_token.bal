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
import ballerina/lang.regexp;
import ballerina/url;
import ballerina/uuid;

# Client assertion type for `private_key_jwt` (RFC 7523).
const CLIENT_ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer";

# Lifetime of a client assertion, in seconds.
const decimal CLIENT_ASSERTION_EXPIRY = 300;

# Posts a form to the token endpoint and parses the response.
#
# + clientAuth - How the client authenticates
# + metadata - Validated authorization server metadata
# + clientId - Resolved client identifier
# + form - Grant specific form parameters. Client authentication parameters are added here
# + config - HTTP settings for the request
# + return - The token response, or an `OAuthTokenError` describing the failure
isolated function requestToken(ClientAuth? clientAuth, AuthorizationServerMetadata metadata,
        string clientId, map<string> form, readonly & AuthHttpConfig config)
        returns TokenResponse|Error {
    string tokenEndpoint = metadata.token_endpoint;
    map<string> params = form.clone();
    map<string|string[]> headers = {
        [CONTENT_TYPE_HEADER]: "application/x-www-form-urlencoded",
        [ACCEPT_HEADER]: CONTENT_TYPE_JSON
    };
    check applyClientAuthentication(clientAuth, clientId, tokenEndpoint,
            params, headers);

    string body = check encodeForm(params);
    [string, string] [origin, path] = check splitUrl(tokenEndpoint);
    http:Client tokenClient = check createAuthClient(origin, config);
    http:Response|error response = tokenClient->post(path, body, headers);
    if response is error {
        return error OAuthTokenError(string `Request to token endpoint '${tokenEndpoint}' failed.`, response);
    }
    json|error payload = response.getJsonPayload();
    if response.statusCode != http:STATUS_OK {
        return buildOAuthTokenError(tokenEndpoint, response.statusCode, payload);
    }
    if payload is error {
        return error OAuthTokenError(
            string `Response from token endpoint '${tokenEndpoint}' is not valid JSON.`, payload);
    }
    TokenResponse|error tokenResponse = payload.cloneWithType();
    if tokenResponse is error {
        return error OAuthTokenError(string `Response from token endpoint '${tokenEndpoint}' does not ` +
            string `contain a valid access token.`, tokenResponse);
    }
    if tokenResponse.access_token.trim() == "" {
        return error OAuthTokenError(
            string `Response from token endpoint '${tokenEndpoint}' contains an empty access token.`);
    }
    if tokenResponse.token_type.toLowerAscii() != "bearer" {
        return error OAuthTokenError(string `Response from token endpoint '${tokenEndpoint}' contains ` +
            string `unsupported token type '${tokenResponse.token_type}'.`);
    }
    int? lifetime = tokenResponse?.expires_in;
    if lifetime is int && lifetime <= 0 {
        return error OAuthTokenError(string `Response from token endpoint '${tokenEndpoint}' contains ` +
            string `a non-positive 'expires_in' value.`);
    }
    return tokenResponse;
}

# Maps a token endpoint error response to a typed error.
#
# + tokenEndpoint - Token endpoint that was called, for the message
# + statusCode - HTTP status code of the response
# + payload - Parsed response body, if it could be parsed
# + return - An `OAuthInvalidGrantError` for `invalid_grant`, otherwise an `OAuthTokenError`
isolated function buildOAuthTokenError(string tokenEndpoint, int statusCode, json|error payload)
        returns Error {
    string errorCode = "";
    string description = "";
    if payload is map<json> {
        json codeValue = payload["error"] ?: ();
        if codeValue is string {
            errorCode = codeValue;
        }
        json descriptionValue = payload["error_description"] ?: ();
        if descriptionValue is string {
            description = descriptionValue;
        }
    }
    string detail = errorCode == "" ? string `status ${statusCode}`
        : (description == "" ? string `'${errorCode}'` : string `'${errorCode}': ${description}`);
    string message = string `Token endpoint '${tokenEndpoint}' rejected the request with ${detail}.`;
    if errorCode == "invalid_grant" {
        return error OAuthInvalidGrantError(message);
    }
    return error OAuthTokenError(message);
}

# Applies client authentication to a token request.
#
# + clientAuth - How the client authenticates
# + clientId - Resolved client identifier
# + tokenEndpoint - Authorization server token endpoint, used as the audience of a client assertion
# + form - Form parameters, modified in place
# + headers - Request headers, modified in place
# + return - An `OAuthConfigError` if the assertion could not be built, or `()`
isolated function applyClientAuthentication(ClientAuth? clientAuth, string clientId,
        string tokenEndpoint, map<string> form, map<string|string[]> headers) returns Error? {
    if clientAuth is ClientSecretConfig {
        if clientAuth.authMethod == CLIENT_SECRET_POST {
            form["client_id"] = clientId;
            form["client_secret"] = clientAuth.clientSecret;
            return;
        }
        string encodedId = check encodeValue(clientId);
        string encodedSecret = check encodeValue(clientAuth.clientSecret);
        string credentials = (encodedId + ":" + encodedSecret).toBytes().toBase64();
        headers["Authorization"] = "Basic " + credentials;
        return;
    }
    if clientAuth is PrivateKeyJwtConfig {
        form["client_assertion_type"] = CLIENT_ASSERTION_TYPE;
        form["client_assertion"] = check buildClientAssertion(clientAuth, clientId, tokenEndpoint);
        return;
    }
    form["client_id"] = clientId;
}

# Builds a `private_key_jwt` client assertion (RFC 7523). `iss` and `sub` are the client
# identifier and the audience is the authorization server token endpoint.
#
# + clientAuth - The signing configuration
# + clientId - Resolved client identifier
# + tokenEndpoint - Authorization server token endpoint, used as the audience
# + return - The signed assertion, or an `OAuthConfigError` if it could not be issued
isolated function buildClientAssertion(PrivateKeyJwtConfig clientAuth, string clientId,
        string tokenEndpoint) returns string|Error {
    jwt:IssuerConfig issuerConfig = {
        issuer: clientId,
        username: clientId,
        audience: tokenEndpoint,
        jwtId: uuid:createType4AsString(),
        expTime: CLIENT_ASSERTION_EXPIRY,
        signatureConfig: clientAuth.signatureConfig
    };
    string? keyId = clientAuth?.keyId;
    if keyId is string {
        issuerConfig.keyId = keyId;
    }
    string|jwt:Error assertion = jwt:issue(issuerConfig);
    if assertion is jwt:Error {
        return error OAuthConfigError("Failed to issue the client assertion.", assertion);
    }
    return assertion;
}

# Encodes a parameter map as `application/x-www-form-urlencoded`.
#
# + params - Parameters to encode
# + return - The encoded string, or an `OAuthTokenError` if a value could not be encoded
isolated function encodeForm(map<string> params) returns string|Error {
    string[] pairs = [];
    foreach [string, string] [key, value] in params.entries() {
        pairs.push(key + "=" + check encodeValue(value));
    }
    return string:'join("&", ...pairs);
}

# Encodes a single parameter value for `application/x-www-form-urlencoded`. `url:encode`
# emits `%20` for a space, whereas form encoding uses `+`; a literal `+` is already encoded
# as `%2B`, so the substitution is unambiguous.
#
# + value - The value to encode
# + return - The encoded value, or an `OAuthTokenError`
isolated function encodeValue(string value) returns string|Error {
    string|url:Error encoded = url:encode(value, "UTF-8");
    if encoded is url:Error {
        return error OAuthTokenError("Failed to URL encode a request parameter.", encoded);
    }
    return regexp:replaceAll(re `%20`, encoded, "+");
}
