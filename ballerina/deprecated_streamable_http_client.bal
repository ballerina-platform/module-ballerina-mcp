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
import ballerina/jballerina.java;

# Represents an MCP client built on top of the Streamable HTTP transport.
#
# # Deprecated
# This client speaks only the legacy protocol. Use `mcp:StreamableHttpClient2`, which also speaks the
# modern protocol and falls back to the legacy one.
@deprecated
public distinct isolated client class StreamableHttpClient {
    # Transport for communication with the MCP server.
    private DeprecatedClientTransport transport;
    # Server capabilities.
    private ServerCapabilities? serverCapabilities = ();
    # Server implementation information.
    private Implementation? serverInfo = ();
    # Request ID generator for tracking requests.
    private int requestId = 0;

    # Creates a new MCP client with the specified transport configuration.
    #
    # + serverUrl - MCP server URL
    # + config - Client transport configuration
    # + return - `ClientError` if transport creation fails, `()` on success
    public isolated function init(string serverUrl, *StreamableHttpClientTransportConfig config) returns ClientError? {
        self.transport = check new (serverUrl, config);
    }

    # Initializes the MCP connection by performing protocol handshake and capability exchange.
    #
    # + clientInfo - Client implementation information
    # + capabilities - Client capabilities to advertise
    # + headers - Optional headers to include with the request
    # + return - `ClientError` if initialization fails, `()` on success
    isolated remote function initialize(Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}, map<string|string[]> headers = {}) returns ClientError? {
        lock {
            string? sessionId = self.transport.getSessionId();

            // If a session ID exists, assume reconnection and skip initialization.
            if sessionId is string {
                return;
            }
        }

        // Prepare and send the initialization request.
        InitializeRequest initRequest = {
            params: {
                protocolVersion: LATEST_PROTOCOL_VERSION,
                capabilities: capabilities,
                clientInfo: clientInfo
            }
        };

        ServerResult response = check self.sendRequestMessage(initRequest, headers);

        if response !is InitializeResult {
            return error ClientInitializationError(
                    string `Initialization failed: unexpected response type '${
                        (typeof response).toString()}' received from server.`
                );
        }

        // Validate protocol compatibility.
        final string protocolVersion = response.protocolVersion;
        if (!SUPPORTED_PROTOCOL_VERSIONS.some(v => v == protocolVersion)) {
            return error ProtocolVersionError(
                    string `Server protocol version '${
                        protocolVersion}' is not supported. Supported versions: ${
                        SUPPORTED_PROTOCOL_VERSIONS.toString()}.`
                );
        }

        lock {
            self.serverCapabilities = response.capabilities.cloneReadOnly();
            self.serverInfo = response.serverInfo.cloneReadOnly();
            // Record the negotiated version so it is sent as the MCP-Protocol-Version header
            // on all subsequent requests (including the initialized notification below).
            self.transport.setProtocolVersion(protocolVersion);
        }

        check self.sendNotificationMessage(<InitializedNotification>{});
    }

    # Opens a server-sent events (SSE) stream for asynchronous server-to-client communication.
    #
    # + return - Stream of JsonRpcMessages or a ClientError.
    isolated remote function subscribeToServerMessages() returns stream<JsonRpcMessage, StreamError?>|ClientError {
        lock {
            return self.transport.establishEventStream();
        }
    }

    # Retrieves the list of available tools from the server.
    #
    # + headers - Optional headers to include with the request
    # + return - List of available tools or a ClientError.
    isolated remote function listTools(map<string|string[]> headers = {}) returns ListToolsResult|ClientError {
        ListToolsRequest listToolsRequest = {};

        ServerResult result = check self.sendRequestMessage(listToolsRequest, headers);
        if result is ListToolsResult {
            return result;
        } else {
            return error ListToolsError(
                string `Tool listing failed: unexpected result type '${(typeof result).toString()}' received.`
            );
        }
    }

    # Executes a tool on the server with the given parameters.
    #
    # + params - Tool execution parameters, including name and arguments
    # + headers - Optional headers to include with the request
    # + return - Result of the tool execution or a ClientError.
    isolated remote function callTool(CallToolParams params, map<string|string[]> headers = {})
            returns CallToolResult|ClientError {
        // Reject task-augmented calls when the server hasn't advertised task support.
        if params.task !is () {
            lock {
                if self.serverCapabilities?.tasks?.requests?.tools?.call is () {
                    return error ToolCallError("Server does not support task-augmented tool calls");
                }
            }
        }

        CallToolRequest toolCallRequest = {
            params: params
        };

        ServerResult result = check self.sendRequestMessage(toolCallRequest, headers);
        if result is CallToolResult {
            return result;
        } else {
            return error ToolCallError(
                string `Tool call failed: unexpected result type '${(typeof result).toString()}' received.`
            );
        }
    }

    # Closes the session and disconnects from the server.
    #
    # + return - A `ClientError` if closure fails, or `()` on success.
    isolated remote function close() returns ClientError? {
        lock {
            do {
                check self.transport.terminateSession();
                self.serverCapabilities = ();
                self.serverInfo = ();
                return;
            } on fail error e {
                return error ClientError(string `Failed to disconnect from server: ${e.message()}`, e);
            }
        }
    }

    # Sends a request message to the server and returns the server's response.
    #
    # + request - The request object to send
    # + headers - Optional headers to include with the request
    # + return - ServerResult, a stream of results, or a ClientError.
    private isolated function sendRequestMessage(Request request, map<string|string[]> headers = {})
            returns ServerResult|ClientError {
        lock {
            self.requestId += 1;

            JsonRpcRequest jsonRpcRequest = {
                ...request.cloneReadOnly(),
                jsonrpc: JSONRPC_VERSION,
                id: self.requestId
            };

            JsonRpcMessage|stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError? response =
                self.transport.sendMessage(jsonRpcRequest, headers.cloneReadOnly());
            return processDeprecatedClientResponse(response).cloneReadOnly();
        }
    }

    # Sends a notification message to the server.
    #
    # + notification - The notification object to send.
    # + return - A `ClientError` if sending fails, or `()` on success.
    private isolated function sendNotificationMessage(Notification notification) returns ClientError? {
        lock {
            JsonRpcNotification jsonRpcNotification = {
                ...notification.cloneReadOnly(),
                jsonrpc: JSONRPC_VERSION
            };

            _ = check self.transport.sendMessage(jsonRpcNotification);
        }
    }
}

# Provides HTTP-based client transport with support for streaming.
isolated class DeprecatedClientTransport {
    private final string serverUrl;
    private final http:Client httpClient;
    private string? sessionId;
    # Protocol version negotiated during initialization, sent on all subsequent requests.
    private string? protocolVersion = ();

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

            DeprecatedMessageStreamTransformer streamTransformer = new (sseEventStream);
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
                self.protocolVersion = ();
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
            DeprecatedMessageStreamTransformer streamTransformer = new (sseEventStream);
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

# Transforms a stream of SSE events into a stream of JsonRpcMessages.
isolated class DeprecatedMessageStreamTransformer {

    # Initializes the transformer with an SSE event stream.
    #
    # + sseEventStream - The SSE event stream to use as input.
    public isolated function init(stream<http:SseEvent, error?> sseEventStream) {
        self.attachSseStream(sseEventStream);
    }

    # Retrieves the next JsonRpcMessage from the SSE event stream.
    #
    # + return - A record with the next JsonRpcMessage, a StreamError, or nil if the stream is complete.
    public isolated function next() returns record {|JsonRpcMessage value;|}|StreamError? {
        while true {
            record {|http:SseEvent value;|}|error? sseEventRecord = self.getNextSseEvent();

            if sseEventRecord is () {
                return; // End of stream.
            }

            if sseEventRecord is error {
                return error SseEventStreamError(
                    string `Failed to retrieve SSE event: ${sseEventRecord.message()}`
                );
            }

            // Keep-alive comments and empty-data priming events carry no message, so they are skipped.
            string? eventData = sseEventRecord.value.data;
            if eventData is () || eventData == "" {
                continue;
            }
            JsonRpcMessage|JsonRpcMessageTransformationError jsonRpcMessage =
                self.convertSseDataToJsonRpcMessage(eventData);

            if jsonRpcMessage is JsonRpcMessageTransformationError {
                return jsonRpcMessage;
            }

            return {
                value: jsonRpcMessage
            };
        }
    }

    # Closes the underlying SSE event stream.
    #
    # + return - A StreamError if closing fails, or nil if successful.
    public isolated function close() returns StreamError? {
        error? closeError = self.closeSseEventStream();
        if closeError is error {
            return error SseEventStreamError(string `Failed to close SSE event stream: ${closeError.message()}`);
        }
        return;
    }

    # Attaches the SSE event stream to this transformer instance.
    #
    # + sseEventStream - The stream of SSE events to bind.
    private isolated function attachSseStream(stream<http:SseEvent, error?> sseEventStream) = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SseEventStreamHelper"
    } external;

    # Retrieves the next event from the SSE stream.
    #
    # + return - Record containing the next SSE event, error, or nil if the stream is complete.
    private isolated function getNextSseEvent() returns record {|http:SseEvent value;|}?|error? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SseEventStreamHelper"
    } external;

    # Closes the attached SSE event stream.
    #
    # + return - Error if closing fails, or nil if successful.
    private isolated function closeSseEventStream() returns error? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SseEventStreamHelper"
    } external;

    # Converts SSE event data to a JsonRpcMessage.
    #
    # + eventData - The `data` field from an SSE event.
    # + return - A JsonRpcMessage or a JsonRpcMessageTransformationError.
    private isolated function convertSseDataToJsonRpcMessage(string? eventData) returns JsonRpcMessage|JsonRpcMessageTransformationError {
        if eventData is () {
            return error MissingSseDataError("SSE event is missing the required 'data' field.");
        }

        JsonRpcMessage|error message = eventData.fromJsonStringWithType();
        if message is error {
            return error TypeConversionError(string `Failed to convert JSON data to JsonRpcMessage: ${message.message()}`);
        }

        return message;
    }
}

# Processes a server response and extracts the result.
#
# + serverResponse - The response from the server, which may be a single JsonRpcMessage, a stream, or a transport error.
# + return - Extracted ServerResult, ServerResponseError, or StreamError.
isolated function processDeprecatedClientResponse(JsonRpcMessage|stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError? serverResponse)
        returns ServerResult|ServerResponseError|StreamError {

    if serverResponse is stream<JsonRpcMessage, StreamError?> {
        return extractDeprecatedClientStreamResult(serverResponse);
    }

    if serverResponse is JsonRpcMessage {
        return extractDeprecatedClientResult(serverResponse);
    }

    if serverResponse is () {
        return error MalformedResponseError("Received null response from server.");
    }

    return error ServerResponseError(
        string `Transport error connecting to server: ${serverResponse.message()}`
    );
}

# Extracts the first valid result from a stream of JsonRpcMessages.
#
# + messageStream - The stream of JsonRpcMessages to process.
# + return - The first valid ServerResult, a specific ServerResponseError, or StreamError.
isolated function extractDeprecatedClientStreamResult(stream<JsonRpcMessage, StreamError?> messageStream)
        returns ServerResult|ServerResponseError|StreamError {

    record {|JsonRpcMessage value;|}|StreamError? streamItem = messageStream.next();
    // Iterate until a valid result or an error is found.
    while streamItem !is () {
        if streamItem is StreamError {
            return streamItem;
        }

        JsonRpcMessage message = streamItem.value;
        if message is JsonRpcResponse {
            return message.result;
        }
        streamItem = messageStream.next();
    }

    return error InvalidMessageTypeError("No valid messages found in server message stream.");
}

# Extracts the result from a JsonRpcMessage and converts it to a ServerResult.
#
# + message - The JsonRpcMessage to convert.
# + return - The extracted ServerResult, or an InvalidMessageTypeError.
isolated function extractDeprecatedClientResult(JsonRpcMessage message) returns ServerResult|ServerResponseError {
    if message is JsonRpcResponse {
        return message.result;
    }
    if message is JsonRpcError {
        return error ServerResponseError(string `Received JSON-RPC error from server: ${message.toJsonString()}`);
    }
    return error InvalidMessageTypeError("Received message from server is not a valid JsonRpcResponse.");
}
