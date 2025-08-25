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

# Configuration options for the Streamable HTTP client transport.
#
# + sessionId - Optional session identifier for continued interactions.
public type StreamableHttpClientTransportConfig record {|
    *http:ClientConfiguration;
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

        StreamableHttpClientTransportConfig {sessionId, ...clientConfig} = config;
        clientConfig.followRedirects = clientConfig.followRedirects ?: {
            enabled: true
        };
        do {
            self.httpClient = check new (serverUrl, clientConfig);
        } on fail error e {
            return error HttpClientError(string `Unable to initialize HTTP client for '${serverUrl}': ${e.message()}`);
        }
        self.sessionId = sessionId;
    }

    # Sends a JSON-RPC message to the server and returns the response.
    #
    # + message - The JSON-RPC message to send.
    # + return - A JSON-RPC response message, a stream of messages, or a transport error.
    isolated function sendMessage(JsonRpcMessage message)
            returns JsonRpcMessage|stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError? {
        map<string> headers = self.prepareRequestHeaders();
        headers[CONTENT_TYPE_HEADER] = CONTENT_TYPE_JSON;
        headers[ACCEPT_HEADER] = string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`;

        do {
            http:Response response = check self.httpClient->post("", message, headers = headers);

            // Handle session ID in the initialization response.
            string|error sessionIdHeader = response.getHeader(SESSION_ID_HEADER);
            if sessionIdHeader is string {
                lock {
                    self.sessionId = sessionIdHeader;
                }
            }

            // If response is 202 Accepted, there is no content to process.
            if response.statusCode == http:STATUS_ACCEPTED {
                return;
            }

            // Dispatch response based on content type.
            string contentType = response.getContentType();
            if contentType.includes(CONTENT_TYPE_SSE) {
                return self.processServerSentEvents(response);
            } else if contentType.includes(CONTENT_TYPE_JSON) {
                return self.processJsonResponse(response);
            } else {
                return error UnsupportedContentTypeError(
                    string `Server returned unsupported content type '${contentType}'.`
                );
            }
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
            return check payload.cloneWithType();
        } on fail error e {
            return error ResponseParsingError(
                string `Unable to parse JSON response: ${e.message()}`
            );
        }
    }
}
