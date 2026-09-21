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

const PROTECTED_RESOURCE_METADATA_PATH = "/.well-known/oauth-protected-resource";
const AUTHORIZATION_SERVER_METADATA_PATH = "/.well-known/oauth-authorization-server";
const OPENID_CONFIGURATION_PATH = "/.well-known/openid-configuration";

# Components of an absolute HTTP URL used by discovery.
#
# + scheme - Lowercase URL scheme
# + origin - Lowercase scheme and authority
# + path - Path with its original case
# + query - Query including the leading `?`, or an empty string
type UrlParts record {|
    string scheme;
    string origin;
    string path;
    string query;
|};

# Parses the `Bearer` challenge from a `WWW-Authenticate` response header. Unrecognised
# parameters are ignored, and a header with no recognised parameter yields an empty record.
#
# + headerValue - Value of the `WWW-Authenticate` header
# + return - The parsed challenge
isolated function parseBearerChallenge(string headerValue) returns BearerChallenge? {
    string value = headerValue.trim();
    string lower = value.toLowerAscii();
    int parameterStart;
    if lower == "bearer" {
        parameterStart = value.length();
    } else if lower.startsWith("bearer ") {
        parameterStart = 7;
    } else {
        int? bearerStart = lower.indexOf(", bearer ");
        if bearerStart is () {
            return ();
        }
        parameterStart = bearerStart + 9;
    }

    BearerChallenge challenge = {};
    string parameters = value.substring(parameterStart);
    int position = 0;
    while position < parameters.length() {
        while position < parameters.length() &&
                (parameters.substring(position, position + 1) == " " ||
                parameters.substring(position, position + 1) == "\t" ||
                parameters.substring(position, position + 1) == ",") {
            position += 1;
        }
        int nameStart = position;
        while position < parameters.length() &&
                isAuthTokenChar(parameters.substring(position, position + 1)) {
            position += 1;
        }
        if position == nameStart {
            break;
        }
        string key = parameters.substring(nameStart, position).toLowerAscii();
        while position < parameters.length() &&
                (parameters.substring(position, position + 1) == " " ||
                parameters.substring(position, position + 1) == "\t") {
            position += 1;
        }
        if position >= parameters.length() || parameters.substring(position, position + 1) != "=" {
            // A following authentication scheme is not a Bearer parameter.
            break;
        }
        position += 1;
        while position < parameters.length() &&
                (parameters.substring(position, position + 1) == " " ||
                parameters.substring(position, position + 1) == "\t") {
            position += 1;
        }
        string authParamValue = "";
        if position < parameters.length() && parameters.substring(position, position + 1) == "\"" {
            position += 1;
            boolean closed = false;
            while position < parameters.length() {
                string character = parameters.substring(position, position + 1);
                position += 1;
                if character == "\"" {
                    closed = true;
                    break;
                }
                if character == "\\" {
                    if position >= parameters.length() {
                        return ();
                    }
                    character = parameters.substring(position, position + 1);
                    position += 1;
                }
                authParamValue += character;
            }
            if !closed {
                return ();
            }
        } else {
            int valueStart = position;
            while position < parameters.length() &&
                    isAuthTokenChar(parameters.substring(position, position + 1)) {
                position += 1;
            }
            if position == valueStart {
                return ();
            }
            authParamValue = parameters.substring(valueStart, position);
        }
        match key {
            "resource_metadata" => {
                challenge.resourceMetadata = authParamValue;
            }
            "scope" => {
                challenge.scope = authParamValue;
            }
            "error" => {
                challenge.errorCode = authParamValue;
            }
            "error_description" => {
                challenge.errorDescription = authParamValue;
            }
            _ => {
            }
        }
        while position < parameters.length() &&
                (parameters.substring(position, position + 1) == " " ||
                parameters.substring(position, position + 1) == "\t") {
            position += 1;
        }
        if position < parameters.length() && parameters.substring(position, position + 1) != "," {
            return ();
        }
    }
    return challenge;
}

isolated function isAuthTokenChar(string character) returns boolean {
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-.^_`|~".includes(character);
}

# Builds the well-known protected resource metadata URLs for an MCP server, in the order
# they are to be tried (RFC 9728).
#
# + serverUrl - Canonical URI of the MCP server
# + return - Candidate URLs, or a `OAuthDiscoveryError` if `serverUrl` is not absolute
isolated function buildProtectedResourceMetadataUrls(string serverUrl) returns string[]|Error {
    UrlParts parts = check parseAbsoluteUrl(serverUrl);
    string resourcePath = resourcePathForWellKnownUrl(parts.path);
    if resourcePath == "" && parts.query == "" {
        return [parts.origin + PROTECTED_RESOURCE_METADATA_PATH];
    }
    return [
        parts.origin + PROTECTED_RESOURCE_METADATA_PATH + resourcePath + parts.query,
        parts.origin + PROTECTED_RESOURCE_METADATA_PATH
    ];
}

# Retrieves a protected resource metadata document (RFC 9728), trying each candidate URL in
# order.
#
# The `resource` value in the retrieved document is compared against `expectedResource` by
# exact string comparison, as required by RFC 9728 section 3.3. A mismatch fails immediately
# rather than falling through to the next candidate: section 7.3 requires that metadata whose
# `resource` does not match the resource identifier being accessed must not be used, since an
# attacker-controlled document could otherwise redirect the client to a rogue authorization
# server.
#
# + candidateUrls - URLs to try, in priority order
# + expectedResource - Canonical URI of the resource being accessed
# + config - HTTP settings for the request
# + observer - Optional observer for authorization metadata events
# + return - The parsed metadata, or a `OAuthDiscoveryError` if no candidate yielded a document
isolated function discoverProtectedResourceMetadata(string[] candidateUrls, string expectedResource,
        readonly & AuthHttpConfig config = {}, ClientObserver? observer = ())
        returns ProtectedResourceMetadata|Error {
    Error? lastError = ();
    int candidateIndex = 0;
    foreach string candidate in candidateUrls {
        json|Error payload = fetchJson(candidate, config, observer, MCP_SERVER);
        if payload is Error {
            lastError = payload;
            candidateIndex += 1;
            continue;
        }
        ProtectedResourceMetadata|error metadata = payload.cloneWithType();
        if metadata is error {
            lastError = error OAuthDiscoveryError(
                string `Protected resource metadata at '${candidate}' is not well formed.`, metadata);
            candidateIndex += 1;
            continue;
        }
        // The second well-known candidate is derived from the origin rather than the full
        // endpoint URL. RFC 9728 section 3.3 therefore requires its document to identify
        // that origin. A challenge-provided URL is the only candidate and continues to be
        // checked against the exact MCP resource URL used for the request.
        boolean rootFallback = candidateUrls.length() > 1 &&
            candidateIndex == candidateUrls.length() - 1;
        string candidateResource = rootFallback
            ? check resourceOrigin(expectedResource)
            : expectedResource;
        if metadata.'resource != candidateResource {
            return error OAuthDiscoveryError(string `Protected resource metadata at '${candidate}' declares ` +
                string `resource '${metadata.'resource}', which does not match the requested resource ` +
                string `'${candidateResource}'.`);
        }
        if metadata.authorization_servers.length() == 0 {
            lastError = error OAuthDiscoveryError(string `Protected resource metadata at '${candidate}' ` +
                string `lists no authorization servers.`);
            candidateIndex += 1;
            continue;
        }
        return metadata;
    }
    Error? cause = lastError;
    string attempted = string:'join(", ", ...candidateUrls);
    if cause is Error {
        return error OAuthDiscoveryError(string `Failed to retrieve protected resource metadata. ` +
            string `Tried: ${attempted}. Last error: ${cause.message()}`, cause);
    }
    return error OAuthDiscoveryError(
        string `Failed to retrieve protected resource metadata. Tried: ${attempted}.`);
}

# Builds the candidate authorization server metadata URLs for an issuer, in the priority
# order defined by the specification.
#
# + issuer - Issuer identifier of the authorization server
# + return - Candidate URLs, or a `OAuthDiscoveryError` if `issuer` is not absolute
isolated function buildAuthorizationServerMetadataUrls(string issuer) returns string[]|Error {
    UrlParts parts = check parseAbsoluteUrl(issuer);
    string normalized = normalizeIssuerPath(parts.path);
    if normalized == "" {
        return [
            parts.origin + AUTHORIZATION_SERVER_METADATA_PATH,
            parts.origin + OPENID_CONFIGURATION_PATH
        ];
    }
    return [
        parts.origin + AUTHORIZATION_SERVER_METADATA_PATH + normalized,
        parts.origin + OPENID_CONFIGURATION_PATH + normalized,
        parts.origin + normalized + OPENID_CONFIGURATION_PATH
    ];
}

# Discovers authorization server metadata for an issuer.
#
# The `issuer` in the retrieved document is compared against the requested issuer by exact
# string comparison, as required by RFC 8414 section 3.3. A mismatch fails immediately
# rather than falling through to the next candidate.
#
# + issuer - Issuer identifier of the authorization server
# + config - HTTP settings for the requests
# + observer - Optional observer for authorization metadata events
# + return - The parsed metadata, or a `OAuthDiscoveryError` if no candidate yielded a document
isolated function discoverAuthorizationServerMetadata(string issuer,
        readonly & AuthHttpConfig config = {}, ClientObserver? observer = ())
        returns AuthorizationServerMetadata|Error {
    string[] candidates = check buildAuthorizationServerMetadataUrls(issuer);
    Error? lastError = ();
    foreach string candidate in candidates {
        json|Error payload = fetchJson(candidate, config, observer);
        if payload is Error {
            lastError = payload;
            continue;
        }
        AuthorizationServerMetadata|error metadata = payload.cloneWithType();
        if metadata is error {
            lastError = error OAuthDiscoveryError(
                string `Authorization server metadata at '${candidate}' is not well formed.`, metadata);
            continue;
        }
        if metadata.issuer != issuer {
            return error OAuthDiscoveryError(string `Authorization server metadata at '${candidate}' ` +
                string `declares issuer '${metadata.issuer}', which does not match the requested ` +
                string `issuer '${issuer}'.`);
        }
        return metadata;
    }
    Error? cause = lastError;
    if cause is Error {
        return error OAuthDiscoveryError(
            string `Failed to discover authorization server metadata for '${issuer}': ${cause.message()}`, cause);
    }
    return error OAuthDiscoveryError(
        string `Failed to discover authorization server metadata for '${issuer}'.`);
}

# Derives the canonical URI of an MCP server, used to build the well-known metadata
# locations. The scheme and host are lowercased. URLs with fragments are rejected because
# fragments are not valid MCP resource identifiers.
#
# + serverUrl - URL of the MCP server
# + return - The canonical URI, or a `OAuthDiscoveryError` if `serverUrl` is not absolute
isolated function canonicalResourceUri(string serverUrl) returns string|Error {
    UrlParts parts = check parseAbsoluteUrl(serverUrl.trim());
    string path = parts.path == "/" ? "" : parts.path;
    return parts.origin + path + parts.query;
}

# Returns the origin of a protected-resource identifier.
#
# The root RFC 9728 well-known fallback is derived from this value, so its metadata document
# must identify this origin rather than an endpoint path beneath it.
#
# + resourceUri - Protected-resource identifier
# + return - Its scheme and authority, or a `OAuthDiscoveryError` if it is not absolute
isolated function resourceOrigin(string resourceUri) returns string|Error {
    UrlParts parts = check parseAbsoluteUrl(resourceUri);
    return parts.origin;
}

# Parses an absolute HTTP URL without losing its query or changing path case.
#
# + targetUrl - URL to parse
# + return - Parsed URL parts, or a `OAuthDiscoveryError`
isolated function parseAbsoluteUrl(string targetUrl) returns UrlParts|Error {
    if targetUrl.includes("#") {
        return error OAuthDiscoveryError(string `'${targetUrl}' contains a fragment.`);
    }
    int? schemeEnd = targetUrl.indexOf("://");
    if schemeEnd is () || schemeEnd == 0 {
        return error OAuthDiscoveryError(string `'${targetUrl}' is not an absolute URL.`);
    }
    string scheme = targetUrl.substring(0, schemeEnd).toLowerAscii();
    if scheme != "http" && scheme != "https" {
        return error OAuthDiscoveryError(string `'${targetUrl}' does not use HTTP or HTTPS.`);
    }

    int authorityStart = schemeEnd + 3;
    int? slash = targetUrl.indexOf("/", authorityStart);
    int? queryStart = targetUrl.indexOf("?", authorityStart);
    int authorityEnd = targetUrl.length();
    if slash is int && (queryStart is () || slash < queryStart) {
        authorityEnd = slash;
    } else if queryStart is int {
        authorityEnd = queryStart;
    }
    if authorityEnd == authorityStart {
        return error OAuthDiscoveryError(string `'${targetUrl}' has no authority.`);
    }
    string authority = targetUrl.substring(authorityStart, authorityEnd);
    if authority.includes("@") {
        return error OAuthDiscoveryError(string `'${targetUrl}' must not contain user information.`);
    }

    string path = "";
    if slash is int && slash == authorityEnd {
        int pathEnd = queryStart is int ? queryStart : targetUrl.length();
        path = targetUrl.substring(slash, pathEnd);
    }
    string query = queryStart is int ? targetUrl.substring(queryStart) : "";
    return {
        scheme: scheme,
        origin: scheme + "://" + authority.toLowerAscii(),
        path: path,
        query: query
    };
}

# Splits an absolute URL into its origin and path components.
#
# + targetUrl - The URL to split
# + return - The origin and path, or a `OAuthDiscoveryError` if the URL is not absolute
isolated function splitUrl(string targetUrl) returns [string, string]|Error {
    UrlParts parts = check parseAbsoluteUrl(targetUrl);
    string path = parts.path == "" ? "/" : parts.path;
    return [parts.origin, path + parts.query];
}

# Returns the resource path to append to an RFC 9728 well-known prefix.
#
# Only the root path separator is omitted. A trailing slash on a non-root path can be
# semantically significant and is therefore preserved.
#
# + path - The path component of a URL
# + return - An empty string for a root path, otherwise the unchanged path
isolated function resourcePathForWellKnownUrl(string path) returns string {
    if path == "" || path == "/" {
        return "";
    }
    return path;
}

# Normalizes an authorization-server issuer path for well-known URL construction.
# RFC 8414 requires a terminating slash to be removed before inserting the suffix.
#
# + path - The issuer path component
# + return - An empty string for a root path, otherwise the path without a trailing slash
isolated function normalizeIssuerPath(string path) returns string {
    if path == "" || path == "/" {
        return "";
    }
    if path.endsWith("/") {
        return path.substring(0, path.length() - 1);
    }
    return path;
}

# Creates an HTTP client for a metadata or token endpoint. Retries and redirects are
# disabled: an authorization code is single use, so a replayed token request cannot succeed.
#
# + origin - Scheme, host and port of the endpoint
# + config - HTTP settings to apply
# + return - The client, or a `OAuthDiscoveryError` if it could not be created
isolated function createAuthClient(string origin, readonly & AuthHttpConfig config)
        returns http:Client|Error {
    if !origin.toLowerAscii().startsWith("https://") {
        return error OAuthDiscoveryError(string `'${origin}' does not use HTTPS. MCP authorization ` +
            string `endpoints must be served over HTTPS.`);
    }
    http:Client|error httpClient = new (origin, {
        httpVersion: config.httpVersion,
        timeout: config.timeout,
        secureSocket: config?.secureSocket,
        proxy: config?.proxy,
        retryConfig: (),
        followRedirects: ()
    });
    if httpClient is error {
        return error OAuthDiscoveryError(
            string `Failed to create an HTTP client for '${origin}'.`, httpClient);
    }
    return httpClient;
}

# Performs a GET request and returns the JSON payload.
#
# + targetUrl - Absolute URL to request
# + config - HTTP settings for the request
# + observer - Optional observer for authorization metadata events
# + eventTarget - System serving the metadata document
# + return - The JSON payload, or a `OAuthDiscoveryError`
isolated function fetchJson(string targetUrl, readonly & AuthHttpConfig config,
        ClientObserver? observer = (), ClientEventTarget eventTarget = AUTHORIZATION_SERVER)
        returns json|Error {
    [string, string] [origin, path] = check splitUrl(targetUrl);
    http:Client httpClient = check createAuthClient(origin, config);
    notifyClientObserver(observer, {
        eventType: HTTP_REQUEST,
        eventTarget: eventTarget,
        eventUrl: targetUrl,
        httpMethod: "GET"
    });
    http:Response|error response = httpClient->get(path);
    if response is error {
        notifyClientObserver(observer, {
            eventType: CLIENT_ERROR,
            eventTarget: eventTarget,
            eventUrl: targetUrl,
            httpMethod: "GET",
            eventMessage: response.message()
        });
        return error OAuthDiscoveryError(string `Request to '${targetUrl}' failed: ${response.message()}`, response);
    }
    notifyClientObserver(observer, {
        eventType: HTTP_RESPONSE,
        eventTarget: eventTarget,
        eventUrl: targetUrl,
        httpMethod: "GET",
        statusCode: response.statusCode,
        eventHeaders: sanitizedResponseHeaders(response)
    });
    if response.statusCode != http:STATUS_OK {
        string|error responseBody = response.getTextPayload();
        if responseBody is string {
            notifyClientObserver(observer, {
                eventType: HTTP_BODY,
                eventTarget: eventTarget,
                eventUrl: targetUrl,
                httpMethod: "GET",
                statusCode: response.statusCode,
                eventBody: responseBody,
                eventMessage: "Authorization metadata error response body"
            });
        }
        return error OAuthDiscoveryError(
            string `Request to '${targetUrl}' returned status ${response.statusCode}.`);
    }
    json|error payload = response.getJsonPayload();
    if payload is error {
        return error OAuthDiscoveryError(
            string `Response from '${targetUrl}' is not valid JSON.`, payload);
    }
    notifyClientObserver(observer, {
        eventType: HTTP_BODY,
        eventTarget: eventTarget,
        eventUrl: targetUrl,
        httpMethod: "GET",
        statusCode: response.statusCode,
        eventBody: payload.toJsonString(),
        eventMessage: "Authorization metadata"
    });
    return payload;
}
