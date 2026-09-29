// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;

# Identifies the system involved in a client event.
public enum ClientEventTarget {
    # The configured MCP server.
    MCP_SERVER = "mcp_server",
    # The discovered OAuth authorization server.
    AUTHORIZATION_SERVER = "authorization_server",
    # The user agent participating in an authorization-code flow.
    USER_AGENT = "user_agent",
    # The enterprise Identity Provider that exchanges an ID token for an ID-JAG.
    IDENTITY_PROVIDER = "identity_provider"
}

# Identifies the kind of activity reported by an MCP client.
public enum ClientEventType {
    # An HTTP request is about to be sent.
    HTTP_REQUEST = "http.request",
    # An HTTP response was received.
    HTTP_RESPONSE = "http.response",
    # An HTTP response body was read outside the MCP JSON-RPC decoder.
    HTTP_BODY = "http.body",
    # A JSON-RPC message was received over JSON or SSE.
    MCP_MESSAGE = "mcp.message",
    # An MCP server returned an OAuth bearer challenge.
    AUTHORIZATION_CHALLENGE = "oauth.challenge",
    # The user must be directed to an OAuth authorization endpoint.
    AUTHORIZATION_REDIRECT = "oauth.authorization_redirect",
    # The authorization callback handler returned a response.
    AUTHORIZATION_CALLBACK = "oauth.authorization_callback",
    # A usable token was acquired or refreshed. Token values are never included.
    TOKEN_ACQUIRED = "oauth.token_acquired",
    # A client operation failed.
    CLIENT_ERROR = "client.error"
}

# A structured event emitted while an MCP client communicates with an MCP server, an
# authorization server, or an Identity Provider. Authorization headers, cookies, client
# credentials, authorization codes, refresh tokens, access tokens, ID tokens, client assertions,
# PKCE verifiers, token exchange subject and actor tokens, and ID-JAG assertions are redacted
# before an event is emitted.
#
# + eventType - Kind of client activity
# + eventTarget - System involved in the activity
# + eventUrl - URL involved in the activity
# + httpMethod - HTTP method, when applicable
# + statusCode - HTTP response status, when applicable
# + eventHeaders - Sanitized HTTP headers
# + eventBody - Sanitized request or response body
# + eventMessage - Additional human-readable context
public type ClientEvent record {|
    ClientEventType eventType;
    ClientEventTarget eventTarget;
    string eventUrl;
    string? httpMethod = ();
    int? statusCode = ();
    map<string|string[]> eventHeaders = {};
    string? eventBody = ();
    string? eventMessage = ();
|};

# Receives structured events from an MCP client. Observer failures are ignored and do not affect
# the MCP operation being observed.
public type ClientObserver isolated object {
    # Handles a client event.
    #
    # + clientEvent - Event emitted by the client
    public isolated function onEvent(readonly & ClientEvent clientEvent);
};

const string REDACTED_VALUE = "[REDACTED]";

isolated function notifyClientObserver(ClientObserver? clientObserver, ClientEvent clientEvent) {
    if clientObserver is ClientObserver {
        readonly & ClientEvent readonlyEvent = clientEvent.cloneReadOnly();
        error? observerError = trap clientObserver.onEvent(readonlyEvent);
        if observerError is error {
            return;
        }
    }
}

isolated function sanitizedEventHeaders(map<string|string[]> eventHeaders)
        returns map<string|string[]> {
    map<string|string[]> sanitizedHeaders = {};
    foreach var [headerName, headerValue] in eventHeaders.entries() {
        string normalizedName = headerName.toLowerAscii();
        if normalizedName == "authorization" || normalizedName == "proxy-authorization" ||
                normalizedName == "cookie" || normalizedName == "set-cookie" ||
                normalizedName == "x-api-key" || normalizedName == "api-key" ||
                normalizedName == "x-auth-token" || normalizedName == "x-access-token" ||
                normalizedName == "x-goog-api-key" {
            sanitizedHeaders[headerName] = [REDACTED_VALUE];
        } else {
            sanitizedHeaders[headerName] = headerValue.clone();
        }
    }
    return sanitizedHeaders;
}

isolated function sanitizedResponseHeaders(http:Response httpResponse)
        returns map<string|string[]> {
    map<string|string[]> responseHeaders = {};
    foreach string headerName in httpResponse.getHeaderNames() {
        string[]|error headerValues = httpResponse.getHeaders(headerName);
        if headerValues is string[] {
            responseHeaders[headerName] = headerValues;
        }
    }
    return sanitizedEventHeaders(responseHeaders);
}

isolated function sanitizedTokenParameters(map<string> tokenParameters) returns map<string> {
    map<string> sanitizedParameters = {};
    foreach var [parameterName, parameterValue] in tokenParameters.entries() {
        string normalizedName = parameterName.toLowerAscii();
        // `subject_token` and `actor_token` carry the token exchanged at the Identity Provider,
        // such as the user's ID token, and `assertion` carries the ID-JAG.
        if normalizedName == "client_secret" || normalizedName == "client_assertion" ||
                normalizedName == "code" || normalizedName == "code_verifier" ||
                normalizedName == "refresh_token" || normalizedName == "access_token" ||
                normalizedName == "subject_token" || normalizedName == "actor_token" ||
                normalizedName == "assertion" {
            sanitizedParameters[parameterName] = REDACTED_VALUE;
        } else {
            sanitizedParameters[parameterName] = parameterValue;
        }
    }
    return sanitizedParameters;
}

# Encodes token request parameters as the `application/x-www-form-urlencoded` body that is sent,
# with credentials redacted. The redaction marker is left unencoded so it stays readable.
#
# + tokenParameters - Token request parameters, including client authentication parameters
# + return - The sanitized form body, or an `OAuthTokenError` if a value could not be encoded
isolated function sanitizedTokenRequestBody(map<string> tokenParameters) returns string|Error {
    string[] pairs = [];
    foreach var [parameterName, parameterValue] in sanitizedTokenParameters(tokenParameters).entries() {
        string encodedValue = parameterValue == REDACTED_VALUE ? parameterValue : check encodeValue(parameterValue);
        pairs.push(parameterName + "=" + encodedValue);
    }
    return string:'join("&", ...pairs);
}

# Redacts the tokens in a token endpoint response and keeps the rest, such as `token_type`,
# `issued_token_type`, `expires_in`, `scope`, and error details. For a token exchange,
# `access_token` carries the issued token, such as an ID-JAG.
#
# + tokenResponse - Token endpoint response object
# + return - The response with token values redacted
isolated function sanitizedTokenResponse(map<json> tokenResponse) returns map<json> {
    map<json> sanitizedResponse = {};
    foreach var [fieldName, fieldValue] in tokenResponse.entries() {
        string normalizedName = fieldName.toLowerAscii();
        if normalizedName == "access_token" || normalizedName == "refresh_token" ||
                normalizedName == "id_token" {
            sanitizedResponse[fieldName] = REDACTED_VALUE;
        } else {
            sanitizedResponse[fieldName] = fieldValue.clone();
        }
    }
    return sanitizedResponse;
}

# Returns the token endpoint response body to report to observers. JSON objects are reported
# with their tokens redacted. Other bodies are reported only for error responses, which carry
# no tokens.
#
# + payload - Response body parsed as JSON
# + responseText - Response body as text
# + statusCode - Response status
# + return - The body to report, or `()` when it is not reported
isolated function tokenResponseEventBody(json|error payload, string|error responseText, int statusCode)
        returns string? {
    if payload is map<json> {
        return sanitizedTokenResponse(payload).toJsonString();
    }
    if statusCode != http:STATUS_OK && responseText is string && responseText != "" {
        return responseText;
    }
    return ();
}
