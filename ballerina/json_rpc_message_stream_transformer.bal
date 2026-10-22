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

# Transforms a stream of SSE events into a stream of JsonRpcMessages.
isolated class JsonRpcMessageStreamTransformer {

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
        record {|http:SseEvent value;|}|error? sseEventRecord = self.getNextSseEvent();

        if sseEventRecord is () {
            return; // End of stream.
        }

        if sseEventRecord is error {
            return error SseEventStreamError(
                string `Failed to retrieve SSE event: ${sseEventRecord.message()}`
            );
        }

        string? eventData = sseEventRecord.value.data;
        JsonRpcMessage|JsonRpcMessageTransformationError jsonRpcMessage = self.convertSseDataToJsonRpcMessage(eventData);

        if jsonRpcMessage is JsonRpcMessageTransformationError {
            return jsonRpcMessage;
        }

        return {
            value: jsonRpcMessage
        };
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
