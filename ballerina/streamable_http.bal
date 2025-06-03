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

type StreamableHttpClientTransportOptions record {|
    string? sessionId = ();
|};

isolated class StreamableHttpClientTransport {
    private final string url;
    private final http:Client httpClient;
    private string? sessionId;

    isolated function init(string url, StreamableHttpClientTransportOptions? options = ()) returns error? {
        self.url = url;
        self.httpClient = check new (url);
        self.sessionId = options?.sessionId;
    }

    isolated function send(JsonRpcMessage message) returns JsonRpcMessage|stream<JsonRpcMessage, error?>|error? {
        map<string> headers = self.commonHeaders();
        headers[CONTENT_TYPE_HEADER] = CONTENT_TYPE_JSON;
        headers[ACCEPT_HEADER] = string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`;

        http:Response response = check self.httpClient->post("/", message, headers = headers);

        // Handle sessionId during the initialization request
        string|error sessionId = response.getHeader(SESSION_ID_HEADER);
        lock {
            if sessionId is string {
                self.sessionId = sessionId;
            }
        }

        // If the response is 202 Accepted, there's no body to process
        if response.statusCode == 202 {
            return;
        }

        // Handle the response based on the content type
        string contentType = response.getContentType();
        if contentType.includes(CONTENT_TYPE_SSE) {
            stream<http:SseEvent, error?> sseEventStream = check response.getSseEventStream();
            MessageEventStreamGenerator msgEventStreamGenerator = new (sseEventStream);
            stream<JsonRpcMessage, error?> msgEventStream = new (msgEventStreamGenerator);
            return msgEventStream;
        } else if contentType.includes(CONTENT_TYPE_JSON) {
            json jsonPayload = check response.getJsonPayload();
            JsonRpcMessage serverMsg = check jsonPayload.cloneWithType();
            return serverMsg;
        } else {
            return error UnsupportedContentTypeError("Unsupported content type: " + contentType);
        }
    }

    isolated function startSse() returns stream<JsonRpcMessage, error?>|error {
        map<string> headers = self.commonHeaders();
        headers[ACCEPT_HEADER] = "text/event-stream";

        stream<http:SseEvent, error?> sseEventStream = check self.httpClient->get("/", headers = headers);
        MessageEventStreamGenerator msgEventStreamGenerator = new (sseEventStream);
        stream<JsonRpcMessage, error?> msgEventStream = new (msgEventStreamGenerator);
        return msgEventStream;
    }

    isolated  function terminateSession() returns error? {
        lock {
            if (self.sessionId is ()) {
                return;
            }

            map<string> headers = self.commonHeaders();
            headers[CONTENT_TYPE_HEADER] = CONTENT_TYPE_JSON;

            http:Response response = check self.httpClient->delete("/", headers = headers);

            if response.statusCode == 405 {
                return error TransportError("Session termination not supported by the server");
            }

            self.sessionId = ();
            return;
        }
    }

    isolated function getSessionId() returns string? {
        lock {
            return self.sessionId;
        }
    }

    private isolated function commonHeaders() returns map<string> {
        lock {
            map<string> headers = {};
            string? sessionId = self.sessionId;
            if (sessionId is string) {
                headers[SESSION_ID_HEADER] = sessionId;
            }
            return headers.clone();
        }
    }
}
