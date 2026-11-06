// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
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
import ballerina/log;

# Configuration options for the Streamable HTTP client transport.
public type StreamableHttpClientConfig record {|
    # Auto probes discovery and falls back to the legacy handshake.
    ProtocolMode protocolMode = "auto";
    # HTTP transport settings, including authorization
    HttpClientConfig httpConfig = {};
    # Reuse of modern results while their caching hints keep them fresh. `()` disables reuse.
    ResultCacheConfig? resultCache = {};
    # Answers elicitations in input-required results, and advertises the elicitation capability.
    ElicitationHandler elicitationHandler?;
    # Maximum number of input-required continuations per call.
    int maxInputRounds = 10;
    # Legacy session to resume; cannot be combined with `"modern"`.
    string sessionId?;
|};

# HTTP settings of the client. The fields mirror `http:ClientConfiguration`, and are copied
# because `auth` also accepts `OAuth2DiscoveryConfig`.
public type HttpClientConfig record {|
    # HTTP protocol version supported by the client
    http:HttpVersion httpVersion = http:HTTP_2_0;
    # HTTP/1.x specific settings
    http:ClientHttp1Settings http1Settings = {};
    # HTTP/2 specific settings
    http:ClientHttp2Settings http2Settings = {};
    # Maximum time in seconds to wait for a response
    decimal timeout = 30;
    # Controls the `Forwarded` and `X-Forwarded-For` headers when acting as a proxy
    string forwarded = "disable";
    # HTTP redirect handling. `()` follows redirects, except with `OAuth2DiscoveryConfig`,
    # which cannot be combined with enabled redirects
    http:FollowRedirects? followRedirects = ();
    # Request connection pool configuration
    http:PoolConfiguration? poolConfig = ();
    # HTTP response cache configuration
    http:CacheConfig cache = {};
    # Request and response compression behavior
    http:Compression compression = http:COMPRESSION_AUTO;
    # How requests to the MCP server are authorized. `OAuth2DiscoveryConfig` obtains access
    # tokens through MCP authorization; `http:ClientAuthConfig` supplies an existing credential.
    (http:ClientAuthConfig|OAuth2DiscoveryConfig)? auth = ();
    # Circuit breaker configuration
    http:CircuitBreakerConfig? circuitBreaker = ();
    # Automatic retry configuration
    http:RetryConfig? retryConfig = ();
    # Cookie handling configuration
    http:CookieConfig? cookieConfig = ();
    # Response size and header limits
    http:ResponseLimitConfigs responseLimits = {};
    # Proxy server configuration, also used for authorization requests
    http:ProxyConfig? proxy = ();
    # Enables payload validation against constraints
    boolean validation = true;
    # Low level socket configuration
    http:ClientSocketConfig socketConfig = {};
    # Enables relaxed response data binding
    boolean laxDataBinding = false;
    # SSL/TLS configuration, also used for authorization requests
    http:ClientSecureSocket? secureSocket = ();
|};

# Configures how the client reuses modern results that carry caching hints. Each client keeps its own
# cache and is treated as a single authorization context, so configure credentials through
# `httpConfig.auth` rather than per-call headers, or use a separate client for each user. A call
# that passes its own `Authorization` header bypasses the cache.
public type ResultCacheConfig record {|
    # Upper bound, in milliseconds, on how long a result is treated as fresh
    int maxTtlMs = 86400000;
    # Maximum number of results kept; the least recently used result is dropped first
    int maxEntries = 1024;
|};

# Selects how a call uses the client's result cache.
# - `use` serves a fresh cached result, or fetches and caches the response
# - `refresh` always fetches and caches the response
# - `bypass` always fetches and leaves the cache untouched
public type CacheMode "use"|"refresh"|"bypass";

# Derives the HTTP settings for metadata and token endpoint requests. The trust store and
# proxy are carried over from the transport configuration; other settings use OAuth defaults.
#
# + config - The HTTP settings of the transport
# + return - HTTP settings for authorization requests
isolated function deriveAuthClientConfig(HttpClientConfig config)
        returns AuthHttpConfig {
    AuthHttpConfig derived = {};
    http:ClientSecureSocket? secureSocket = config.secureSocket;
    if secureSocket is http:ClientSecureSocket {
        derived.secureSocket = secureSocket;
    }
    http:ProxyConfig? proxy = config.proxy;
    if proxy is http:ProxyConfig {
        derived.proxy = proxy;
    }
    return derived;
}

# Provides HTTP-based client transport with support for streaming.
isolated class StreamableHttpClientTransport {
    private final string serverUrl;
    private final http:Client httpClient;
    # Acquires and holds access tokens when MCP authorization is configured.
    private final ClientOAuthProvider? oauthProvider;
    private string? sessionId;
    # Protocol version negotiated during initialization, sent on all subsequent requests.
    private string? protocolVersion = ();
    private final ResultCache resultCache;

    # Initializes the HTTP client transport with the provided server URL.
    #
    # + serverUrl - The URL of the server endpoint.
    # + config - Optional configuration, such as session ID and authorization.
    # + return - A StreamableHttpTransportError if initialization fails; otherwise, nil.
    isolated function init(string serverUrl, *StreamableHttpClientConfig config)
            returns StreamableHttpTransportError? {
        self.serverUrl = serverUrl;

        // `auth` may hold an `OAuth2DiscoveryConfig`, which is handled by this module rather
        // than by the HTTP client.
        HttpClientConfig httpConfig = config.httpConfig;
        HttpClientConfig {auth: authConfig, ...rest} = httpConfig;
        http:ClientConfiguration clientConfig = {...rest};

        OAuth2DiscoveryConfig? oauth =
            authConfig is OAuth2DiscoveryConfig ? authConfig : ();
        if authConfig is http:ClientAuthConfig {
            clientConfig.auth = authConfig;
        }

        // Redirects stay off with MCP authorization: the token is attached here, outside the
        // `allowAuthHeaders` guard, so a redirect could leak it or hide the challenge.
        if oauth is () {
            clientConfig.followRedirects = clientConfig.followRedirects ?: {enabled: true};
        }
        do {
            self.httpClient = check new (serverUrl, clientConfig);
        } on fail error e {
            return error HttpClientError(string `Unable to initialize HTTP client for '${serverUrl}': ${e.message()}`);
        }

        if oauth is () {
            self.oauthProvider = ();
        } else {
            ClientOAuthProvider|Error provider =
                new (serverUrl, oauth, deriveAuthClientConfig(httpConfig));
            if provider is Error {
                return error AuthorizationError(
                    string `Invalid authorization configuration for '${serverUrl}': ${provider.message()}`,
                    provider);
            }
            self.oauthProvider = provider;
        }
        self.sessionId = config.sessionId;
        self.resultCache = new (config.resultCache);
    }

    isolated function cache() returns ResultCache => self.resultCache;

    // Returns the configured MCP authorization extension, if any.
    isolated function oauthExtension() returns string? {
        ClientOAuthProvider? provider = self.oauthProvider;
        return provider is ClientOAuthProvider ? provider.oauthExtension() : ();
    }

    # Returns the `Authorization` header value to send with a request, if one is available.
    #
    # + challenge - Challenge from a rejected request, when retrying after one
    # + return - The header value, `()` if authorization is not configured or has not yet
    # been established, or an `AuthorizationError`
    private isolated function getAuthorizationValue(BearerChallenge? challenge = ())
            returns string?|AuthorizationError {
        ClientOAuthProvider? provider = self.oauthProvider;
        if provider is () {
            return ();
        }
        string?|Error value = challenge is ()
            ? provider.tryGetAuthorizationHeader()
            : provider.getAuthorizationHeader(challenge);
        if value is Error {
            return error AuthorizationError(
                string `Failed to obtain authorization for '${self.serverUrl}': ${value.message()}`, value);
        }
        return value;
    }

    # Sends one request to the MCP server, authorizing it and retrying once if the server
    # responds with an authorization challenge.
    #
    # + method - Which request to send
    # + headers - Headers to send, excluding authorization
    # + message - Request body, for `POST`
    # + acquire - Whether the request may start or refresh an OAuth flow
    # + return - The final response, or a transport error
    private isolated function execute(OutboundMethod method, map<string|string[]> headers,
            JsonRpcMessage? message = (), boolean acquire = true)
            returns http:Response|StreamableHttpTransportError {
        map<string|string[]> requestHeaders = headers.clone();
        string? authorization = acquire
            ? check self.getAuthorizationValue()
            : self.peekAuthorizationValue();
        if authorization is string {
            requestHeaders[AUTHORIZATION_HEADER] = authorization;
        }

        http:Response response = check self.dispatch(method, requestHeaders, message);
        if !acquire {
            return response;
        }
        // Retried once: a second rejection means authorizing again would not help.
        BearerChallenge? challenge = self.retryableChallenge(response);
        if challenge is BearerChallenge {
            string? retryAuthorization = check self.getAuthorizationValue(challenge);
            if retryAuthorization is string {
                // A token obtained after a challenge may carry other scopes, so the server may list other tools.
                if retryAuthorization != authorization {
                    self.resultCache.invalidate(REQUEST_LIST_TOOLS);
                }
                requestHeaders[AUTHORIZATION_HEADER] = retryAuthorization;
                return self.dispatch(method, requestHeaders, message);
            }
        }
        return response;
    }

    # Performs a single HTTP request, with no authorization handling.
    #
    # + method - Which request to send
    # + headers - Headers to send
    # + message - Request body, for `POST`
    # + return - The response, or a transport error
    private isolated function dispatch(OutboundMethod method, map<string|string[]> headers,
            JsonRpcMessage? message) returns http:Response|StreamableHttpTransportError {
        do {
            match method {
                POST => {
                    return check self.httpClient->post("", message, headers = headers);
                }
                _ => {
                    return check self.httpClient->delete("", headers = headers);
                }
            }
        } on fail error e {
            return error HttpClientError(string `Failed to send request to server: ${e.message()}`);
        }
    }

    # Returns a cached authorization header without contacting the authorization server.
    #
    # + return - The header value, or `()` if no usable token is cached
    private isolated function peekAuthorizationValue() returns string? {
        ClientOAuthProvider? provider = self.oauthProvider;
        return provider is () ? () : provider.peekAuthorizationHeader();
    }

    # Determines whether a response is an authorization challenge worth retrying. A 403 is
    # only retried when it carries `error="insufficient_scope"`.
    #
    # + response - The response to inspect
    # + return - The parsed challenge, or `()` if the response should not be retried
    private isolated function retryableChallenge(http:Response response) returns BearerChallenge? {
        if self.oauthProvider is () {
            return ();
        }
        int status = response.statusCode;
        if status != http:STATUS_UNAUTHORIZED && status != http:STATUS_FORBIDDEN {
            return ();
        }
        string|error headerValue = response.getHeader(WWW_AUTHENTICATE_HEADER);
        BearerChallenge? challenge = headerValue is string
            ? parseBearerChallenge(headerValue)
            : (status == http:STATUS_UNAUTHORIZED ? {} : ());
        if challenge is () {
            return ();
        }
        if status == http:STATUS_FORBIDDEN && challenge?.errorCode != INSUFFICIENT_SCOPE {
            return ();
        }
        return challenge;
    }

    # Sends a JSON-RPC message to the server and returns the response.
    #
    # + message - The JSON-RPC message to send
    # + additionalHeaders - Optional additional headers to include with the request
    # + return - A JSON-RPC response message, a stream of messages, or a transport error.
    isolated function sendMessage(JsonRpcMessage message, map<string|string[]> additionalHeaders = {})
            returns JsonRpcMessage|stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError? {
        map<string|string[]> headers = self.prepareRequestHeaders();
        headers[CONTENT_TYPE_HEADER] = CONTENT_TYPE_JSON;
        headers[ACCEPT_HEADER] = string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`;

        // Merge additional headers, with additional headers overriding defaults
        foreach var [key, value] in additionalHeaders.entries() {
            foreach string headerName in headers.keys().filter(k => k.toLowerAscii() == key.toLowerAscii()) {
                _ = headers.remove(headerName);
            }
            headers[key] = value;
        }

        do {
            http:Response response = check self.execute(POST, headers, message);

            // Handle session ID in the initialization response.
            string|error sessionIdHeader = response.getHeader(SESSION_ID_HEADER);
            if sessionIdHeader is string {
                lock {
                    self.sessionId = sessionIdHeader;
                }
            }

            if response.statusCode < 200 || response.statusCode >= 300 {
                return error HttpClientError(
                    string `Server returned error status ${response.statusCode}: ${response.reasonPhrase}`
                );
            }

            // If response is 202 Accepted, there is no content to process.
            if response.statusCode == http:STATUS_ACCEPTED {
                return;
            }

            if message !is JsonRpcRequest {
                return;
            }

            string contentType = response.getContentType();
            if contentType.includes(CONTENT_TYPE_SSE) {
                return self.processServerSentEvents(response);
            }
            if contentType.includes(CONTENT_TYPE_JSON) {
                return self.processJsonResponse(response);
            }
            return error UnsupportedContentTypeError(
                string `Server returned unsupported content type '${contentType}'.`
            );
        } on fail error e {
            if e is AuthorizationError {
                return e;
            }
            return error HttpClientError(string `Failed to send message to server: ${e.message()}`, e);
        }
    }

    isolated function sendProtocolRequest(JsonRpcRequest requestMessage, map<string|string[]> additionalHeaders,
            map<string> parameterHeaders = {}, boolean requireResultType = true) returns Result|ClientError {
        map<string|string[]> requestHeaders = check prepareProtocolRequestHeaders(requestMessage, additionalHeaders, parameterHeaders);
        http:Response httpResponse = check self.execute(POST, requestHeaders, requestMessage);
        return readProtocolResponse(httpResponse, requestMessage.id, requireResultType);
    }

    # Terminates the current session with the server.
    #
    # + return - A StreamableHttpTransportError if termination fails; otherwise, nil.
    isolated function terminateSession() returns StreamableHttpTransportError? {
        if self.getSessionId() is () {
            return;
        }
        lock {
            if self.sessionId is () {
                self.protocolVersion = ();
                return;
            }

            map<string|string[]> headers = self.prepareRequestHeaders();
            headers[CONTENT_TYPE_HEADER] = CONTENT_TYPE_JSON;

            do {
                // Closing a session must not initiate an interactive authorization flow.
                http:Response response = check self.execute(DELETE, headers, acquire = false);
                // A 405 means the server does not support client-initiated termination, which the
                // Streamable HTTP transport allows; the session is still considered closed locally.
                if response.statusCode == 405 {
                    log:printDebug("Server does not allow session termination");
                } else if response.statusCode != 200 && response.statusCode != 204 {
                    log:printWarn(string `Session termination failed: ${response.statusCode}`);
                }

                self.sessionId = ();
                self.protocolVersion = ();
                return;
            } on fail error e {
                // The session is abandoned locally either way; the server expires it on its own.
                self.sessionId = ();
                self.protocolVersion = ();
                return error SessionOperationError(
                    string `Failed to terminate session: ${e.message()}`
                );
            }
        }
    }

    # Returns the current session ID, or nil if no session is active.
    #
    # + return - The current session ID as a string, or nil if not set.
    isolated function getSessionId() returns string? {
        lock {
            return self.sessionId;
        }
    }

    # Records the protocol version negotiated during initialization. Once set, it is included as the
    # `MCP-Protocol-Version` header on all subsequent requests, as required by the Streamable HTTP transport.
    #
    # + protocolVersion - The negotiated protocol version.
    isolated function setProtocolVersion(string protocolVersion) {
        lock {
            self.protocolVersion = protocolVersion;
        }
    }

    # Prepares common HTTP headers for requests, including the session ID if present.
    #
    # + return - Map of common headers to include in each request.
    private isolated function prepareRequestHeaders() returns map<string> {
        lock {
            map<string> headers = {};
            string? currentSessionId = self.sessionId;
            if currentSessionId is string {
                headers[SESSION_ID_HEADER] = currentSessionId;
            }
            string? currentProtocolVersion = self.protocolVersion;
            if currentProtocolVersion is string {
                headers[PROTOCOL_VERSION_HEADER] = currentProtocolVersion;
            }
            return headers.clone();
        }
    }

    # Processes a Server-Sent Events HTTP response into a stream of JsonRpcMessages.
    #
    # + response - The HTTP response containing SSE data.
    # + return - A stream of JsonRpcMessages, or a StreamableHttpTransportError.
    private isolated function processServerSentEvents(http:Response response)
            returns stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError {
        do {
            stream<http:SseEvent, error?> sseEventStream = check response.getSseEventStream();
            JsonRpcMessageStreamTransformer streamTransformer = new (sseEventStream);
            return new stream<JsonRpcMessage, StreamError?>(streamTransformer);
        } on fail error e {
            return error ResponseParsingError(
                string `Unable to process SSE response: ${e.message()}`
            );
        }
    }

    # Processes a JSON HTTP response into a JsonRpcMessage.
    #
    # + response - The HTTP response containing JSON data.
    # + return - A JsonRpcMessage, or a StreamableHttpTransportError.
    private isolated function processJsonResponse(http:Response response)
            returns JsonRpcMessage|StreamableHttpTransportError {
        do {
            json payload = check response.getJsonPayload();
            return check toLegacyMessage(payload);
        } on fail error e {
            return error ResponseParsingError(
                string `Unable to parse JSON response: ${e.message()}`
            );
        }
    }
}
