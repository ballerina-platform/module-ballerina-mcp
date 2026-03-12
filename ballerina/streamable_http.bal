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

# Represents the OAuth 2.0 client configuration required to interact
# with an external Authorization Server and validate issued access tokens.
@display {label: "OAuth Client Configuration"}
public type AgentIdAuthConfig record {|

    # The base URL of the Authorization Server used to resolve
    # OAuth 2.0 endpoints such as authorization, token, and introspection.
    @display {label: "Authorization Server Base URL"}
    string baseAuthUrl?;

    # The OAuth 2.0 client identifier issued to this client application
    @display {label: "Client ID"}
    string clientId?;

    # The redirect URI registered for the OAuth client
    @display {label: "Redirect URI"}
    string redirectUri?;

    # Scopes required to invoke this tool
    @display {label: "Required Scopes"}
    string|string[] scopes?;

    # Indicates whether PKCE (Proof Key for Code Exchange) is enabled
    # for the Authorization Code flow.
    @display {label: "Enable PKCE"}
    boolean isPkceEnabled = false;
|};

#Configuration options for the Streamable HTTP client transport.
public type StreamableHttpClientTransportConfig record {|
    # HTTP protocol version supported by the client
    http:HttpVersion httpVersion = http:HTTP_2_0;
    # HTTP/1.x specific settings
    http:ClientHttp1Settings http1Settings = {};
    # HTTP/2 specific settings
    http:ClientHttp2Settings http2Settings = {};
    # Maximum time(in seconds) to wait for a response before the request times out
    decimal timeout = 30;
    # The choice of setting `Forwarded`/`X-Forwarded-For` header, when acting as a proxy
    string forwarded = "disable";
    # HTTP redirect handling configurations (with 3xx status codes)
    http:FollowRedirects? followRedirects = ();
    # Configurations associated with the request connection pool
    http:PoolConfiguration? poolConfig = ();
    # HTTP response caching related configurations
    http:CacheConfig cache = {};
    # Enable request/response compression (using `accept-encoding` header)
    http:Compression compression = http:COMPRESSION_AUTO;
    # Client authentication options (Basic, Bearer token, OAuth, etc.)
    # Circuit breaker configurations to prevent cascading failures
    http:CircuitBreakerConfig? circuitBreaker = ();
    # Automatic retry settings for failed requests
    http:RetryConfig? retryConfig = ();
    # Cookie handling settings for session management
    http:CookieConfig? cookieConfig = ();
    # Configurations related to client authentication
    http:ClientAuthConfig|AgentIdAuthConfig? auth = ();
    # Limits for response size and headers (to prevent memory issues)
    http:ResponseLimitConfigs responseLimits = {};
    # Proxy server settings if requests need to go through a proxy
    http:ProxyConfig? proxy = ();
    # Enable automatic payload validation for request/response data against constraints
    boolean validation = true;
    # Low-level socket settings (timeouts, buffer sizes, etc.)
    http:ClientSocketConfig socketConfig = {};
    # Enable relaxed data binding on the client side.
    # When enabled:
    # - `null` values in JSON are allowed to be mapped to optional fields
    # - missing fields in JSON are allowed to be mapped as `null` values
    boolean laxDataBinding = false;
    # SSL/TLS-related options
    http:ClientSecureSocket? secureSocket = ();
    # Optional session identifier for continued interactions
    string sessionId?;
|};

# Provides HTTP-based client transport with support for streaming.
isolated class StreamableHttpClientTransport {
    private final string serverUrl;
    private final http:Client httpClient;
    private string? sessionId;

    # Initializes the HTTP client transport with the provided server URL.
    #
    # + serverUrl - The URL of the server endpoint.
    # + config - Optional configuration, such as session ID.
    # + return - A StreamableHttpTransportError if initialization fails; otherwise, nil.
    isolated function init(string serverUrl, *StreamableHttpClientTransportConfig config)
            returns StreamableHttpTransportError? {
        self.serverUrl = serverUrl;
        StreamableHttpClientTransportConfig {sessionId, auth, ...clientConfig} = config;
        clientConfig.followRedirects = clientConfig.followRedirects ?: {
            enabled: true
        };
        do {
            http:ClientConfiguration httpClientAction = {...clientConfig};
            if auth is http:ClientAuthConfig {
                httpClientAction.auth = auth;
            }
            self.httpClient = check new (serverUrl, httpClientAction);
        } on fail error e {
            return error HttpClientError(
                string `Unable to initialize HTTP client for '${serverUrl}': ${e.message()}`
            );
        }
        self.sessionId = sessionId;
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
            http:Response response = check self.httpClient->post("", message, headers = headers);

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
            return error HttpClientError(string `Failed to send message to server: ${e.message()}`);
        }
    }

    # Establishes a Server-Sent Events (SSE) stream with the server.
    #
    # + return - A stream of JsonRpcMessages, or a StreamableHttpTransportError.
    isolated function establishEventStream() returns stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError {
        map<string> headers = self.prepareRequestHeaders();
        headers[ACCEPT_HEADER] = CONTENT_TYPE_SSE;

        do {
            stream<http:SseEvent, error?> sseEventStream = check self.httpClient->get("", headers = headers);

            JsonRpcMessageStreamTransformer streamTransformer = new (sseEventStream);
            return new stream<JsonRpcMessage, StreamError?>(streamTransformer);
        } on fail error e {
            return error SseStreamEstablishmentError(
                string `Failed to establish SSE connection with server: ${e.message()}`
            );
        }
    }

    # Terminates the current session with the server.
    #
    # + return - A StreamableHttpTransportError if termination fails; otherwise, nil.
    isolated function terminateSession() returns StreamableHttpTransportError? {
        lock {
            if self.sessionId is () {
                return;
            }

            map<string> headers = self.prepareRequestHeaders();
            headers[CONTENT_TYPE_HEADER] = CONTENT_TYPE_JSON;

            do {
                http:Response response = check self.httpClient->delete("", headers = headers);

                if response.statusCode == 405 {
                    return error SessionOperationError("Server does not support session termination.");
                }

                self.sessionId = ();
                return;
            } on fail error e {
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

    # Prepares common HTTP headers for requests, including the session ID if present.
    #
    # + return - Map of common headers to include in each request.
    private isolated function prepareRequestHeaders() returns map<string> {
        lock {
            string? currentSessionId = self.sessionId;
            return currentSessionId is string ? {[SESSION_ID_HEADER]: currentSessionId} : {};
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
            JsonRpcMessage|http:ErrorPayload result = check payload.cloneWithType();
            if result is JsonRpcMessage {
                return result;
            }
            return error HttpClientError(
                string `Received error response from server: ${result.toJsonString()}`
            );
        } on fail error e {
            return error ResponseParsingError(
                string `Unable to parse JSON response: ${e.message()}`
            );
        }
    }
}
