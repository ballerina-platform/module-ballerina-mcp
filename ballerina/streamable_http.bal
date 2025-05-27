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

# Configuration options for the StreamableHTTPClientTransport.
#
# + sessionId - Session ID for the connection. This is used to identify the session on the server.
# When not provided and connecting to a server that supports session IDs, the server will generate a new session ID.
public type StreamableHttpClientTransportOptions record {|
    string? sessionId = ();
|};

type SseHandler function (stream<JSONRPCServerMessage, error?> 'stream) returns future<error?>;

distinct class StreamableHttpClientTransport {
    private final string url;
    private final http:Client httpClient;
    private string? sessionId;

    private SseHandler? streamHandler = ();
    future<error?>? responseFuture = ();

    function init(string url, StreamableHttpClientTransportOptions? options = ()) returns error? {
        self.url = url;
        self.httpClient = check new (url);
        self.sessionId = options?.sessionId;
    }

    function send(JSONRPCMessage message) returns JSONRPCServerMessage|stream<JSONRPCServerMessage, error?>|error? {
        map<string> headers = self.commonHeaders();
        headers[CONTENT_TYPE_HEADER] = CONTENT_TYPE_JSON;
        headers[ACCEPT_HEADER] = string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`;

        http:Response response = check self.httpClient->post("/", message, headers = headers);

        // Handle sessionId during the initialization request
        string|error sessionId = response.getHeader(SESSION_ID_HEADER);
        if sessionId is string {
            self.sessionId = sessionId;
        }

        // TODO: Handle Authorization

        // If the response is 202 Accepted, there's no body to process
        if response.statusCode == 202 {
            if (self.isInitializedNotification(message)) {
                stream<JSONRPCServerMessage, error?> serverMsgEventStream = check self.startSse();
                SseHandler? streamHandler = self.streamHandler;
                if streamHandler is SseHandler {
                    self.responseFuture = streamHandler(serverMsgEventStream);
                }
            }
            return;
        }

        // Handle the response based on the content type
        string contentType = response.getContentType();
        if contentType.includes(CONTENT_TYPE_SSE) {
            stream<http:SseEvent, error?> sseEventStream = check response.getSseEventStream();
            ServerMessageEventStreamGenerator serverMsgEventStreamGenerator = check new (sseEventStream);
            stream<JSONRPCServerMessage, error?> serverMsgEventStream = new (serverMsgEventStreamGenerator);
            return serverMsgEventStream;
        } else if contentType.includes(CONTENT_TYPE_JSON) {
            json jsonPayload = check response.getJsonPayload();
            JSONRPCServerMessage serverMsg = check jsonPayload.cloneWithType();
            return serverMsg;
        } else {
            return error UnsupportedContentTypeError("Unsupported content type: " + contentType);
        }
    }

    function getSessionId() returns string? {
        return self.sessionId;
    }

    function setSseHandler(SseHandler handler) {
        self.streamHandler = handler;
    }

    function waitForCompletion() returns error? {
        future<error?>? responseFuture = self.responseFuture;
        if (responseFuture is ()) {
            return ();
        }
        return wait responseFuture;
    }

    private function startSse() returns stream<JSONRPCServerMessage, error?>|error {
        map<string> headers = self.commonHeaders();
        headers[ACCEPT_HEADER] = "text/event-stream";

        stream<http:SseEvent, error?> sseEventStream = check self.httpClient->get("/", headers = headers);
        ServerMessageEventStreamGenerator serverMsgEventStreamGenerator = check new (sseEventStream);
        stream<JSONRPCServerMessage, error?> serverMsgEventStream = new (serverMsgEventStreamGenerator);
        return serverMsgEventStream;
    }

    private function commonHeaders() returns map<string> {
        map<string> headers = {};
        string? sessionId = self.sessionId;
        if (sessionId is string) {
            headers[SESSION_ID_HEADER] = sessionId;
        }
        return headers;
    }

    private function isInitializedNotification(JSONRPCServerMessage message) returns boolean {
        if message is JSONRPCNotification {
            if message.method == "notifications/initialized" {
                return true;
            }
        }
        return false;
    }
}
