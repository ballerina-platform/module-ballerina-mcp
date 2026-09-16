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

// A separate decoder leaves the public legacy JsonRpcMessage union unchanged.
isolated class ProtocolMessageStream {
    public isolated function init(stream<http:SseEvent, error?> sseEventStream) {
        self.attachSseStream(sseEventStream);
    }

    public isolated function next() returns record {|WireMessage value;|}|StreamError? {
        while true {
            var streamItem = self.getNextSseEvent();
            if streamItem is error {
                return error SseEventStreamError(streamItem.message());
            }
            if streamItem is () {
                return;
            }
            string? eventData = streamItem.value.data;
            if eventData is () || eventData == "" {
                continue;
            }
            WireMessage|error messageValue = eventData.fromJsonStringWithType();
            if messageValue is error {
                return error TypeConversionError("Malformed JSON-RPC SSE event", messageValue);
            }
            return {value: messageValue};
        }
    }

    public isolated function close() returns StreamError? {
        error? closeError = self.closeSseEventStream();
        if closeError is error {
            return error SseEventStreamError(closeError.message());
        }
    }

    private isolated function attachSseStream(stream<http:SseEvent, error?> sseEventStream) = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SseEventStreamHelper"
    } external;

    private isolated function getNextSseEvent() returns record {|http:SseEvent value;|}?|error? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SseEventStreamHelper"
    } external;

    private isolated function closeSseEventStream() returns error? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SseEventStreamHelper"
    } external;
}

isolated function readProtocolResponse(http:Response httpResponse, RequestId requestId, boolean modernResponse = true)
        returns Result|ClientError {
    WireMessage messageValue;
    if httpResponse.getContentType().includes(CONTENT_TYPE_SSE) {
        stream<http:SseEvent, error?>|error eventStream = httpResponse.getSseEventStream();
        if eventStream is error {
            return error ResponseParsingError(eventStream.message());
        }
        ProtocolMessageStream messageStream = new (eventStream);
        Result|ClientError responseValue = readProtocolStream(messageStream, requestId, modernResponse);
        StreamError? closeError = messageStream.close();
        if closeError is StreamError && responseValue !is ClientError {
            return closeError;
        }
        return responseValue;
    }
    var payloadValue = httpResponse.getJsonPayload();
    if payloadValue is error {
        return error HttpClientError("Server returned a non-JSON response", statusCode = httpResponse.statusCode);
    }
    WireMessage|error parsedValue = payloadValue.cloneWithType();
    if parsedValue is error {
        return error ResponseParsingError("Malformed JSON-RPC response", parsedValue, statusCode = httpResponse.statusCode);
    }
    messageValue = parsedValue;
    return protocolMessageResult(messageValue, requestId, modernResponse, httpResponse.statusCode);
}

isolated function readProtocolStream(ProtocolMessageStream messageStream, RequestId requestId, boolean modernResponse)
        returns Result|ClientError {
    while true {
        var streamItem = messageStream.next();
        if streamItem is StreamError {
            return streamItem;
        }
        if streamItem is () {
            return error ResponseParsingError("Response stream ended before a final response; the request was not replayed");
        }
        if streamItem.value is JsonRpcNotification {
            continue;
        }
        return protocolMessageResult(streamItem.value, requestId, modernResponse, 200);
    }
}

isolated function protocolMessageResult(WireMessage messageValue, RequestId requestId, boolean modernResponse, int statusCode)
        returns Result|ClientError {
    if messageValue is WireError {
        RequestId? responseId = messageValue?.id;
        if responseId is RequestId && responseId != requestId {
            return error ResponseParsingError("JSON-RPC error response ID does not match the request");
        }
        JsonRpcError normalizedError = {jsonrpc: JSONRPC_VERSION, id: responseId, 'error: messageValue.'error};
        return error ServerResponseError(messageValue.'error.message, rpcError = normalizedError, statusCode = statusCode);
    }
    if messageValue !is WireResponse || messageValue.id != requestId {
        return error ResponseParsingError("JSON-RPC response ID does not match the request");
    }
    if statusCode < 200 || statusCode >= 300 {
        return error HttpClientError("HTTP error response contained a success result", statusCode = statusCode);
    }
    Result resultValue = messageValue.result;
    anydata resultType = resultValue["resultType"];
    if modernResponse && resultType !is string {
        return error ResponseParsingError("Modern result is missing required resultType");
    }
    if resultType != () && resultType != "complete" && resultType != "input_required" {
        return error ResponseParsingError("Unsupported resultType");
    }
    return resultValue;
}

isolated function shouldUseLegacy(ClientError probeError) returns boolean {
    var statusCode = probeError.detail()["statusCode"];
    if statusCode == 401 || statusCode == 403 || (statusCode is int && statusCode >= 500) {
        return false;
    }
    var rpcValue = probeError.detail()["rpcError"];
    if rpcValue is JsonRpcError {
        int errorCode = rpcValue.'error.code;
        if errorCode == HEADER_MISMATCH || errorCode == MISSING_REQUIRED_CLIENT_CAPABILITY {
            return false;
        }
        if errorCode == UNSUPPORTED_PROTOCOL_VERSION {
            anydata errorData = rpcValue.'error?.data;
            if errorData is map<anydata> {
                anydata supportedVersions = errorData["supported"];
                if supportedVersions is string[] {
                    if supportedVersions.some(versionValue => versionValue == MODERN_PROTOCOL_VERSION) {
                        return false;
                    }
                    foreach string versionValue in supportedVersions {
                        foreach string supportedVersion in SUPPORTED_PROTOCOL_VERSIONS {
                            if versionValue == supportedVersion {
                                return true;
                            }
                        }
                    }
                    return false;
                }
            }
            return false;
        }
        return true;
    }
    return statusCode == 400 || statusCode == 404 || statusCode == 405 || probeError is ResponseParsingError;
}
