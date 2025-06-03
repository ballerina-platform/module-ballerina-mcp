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

# Processes a server response and extracts the result.
#
# + serverResponse - The response from the server, which may be a single JsonRpcMessage, a stream, or a transport error.
# + return - Extracted ServerResult, ServerResponseError, or StreamError.
isolated function processServerResponse(JsonRpcMessage|stream<JsonRpcMessage, StreamError?>|StreamableHttpTransportError? serverResponse)
        returns ServerResult|ServerResponseError|StreamError {

    // If response is a stream, extract the result from the stream.
    if serverResponse is stream<JsonRpcMessage, StreamError?> {
        return extractResultFromMessageStream(serverResponse);
    }

    // If response is a direct JsonRpcMessage, convert it to a result.
    if serverResponse is JsonRpcMessage {
        return convertMessageToResult(serverResponse);
    }

    // Null response: indicates malformed or missing server reply.
    if serverResponse is () {
        return error MalformedResponseError("Received null response from server.");
    }

    // If a transport error is returned, wrap as a ServerResponseError.
    if serverResponse is StreamableHttpTransportError {
        return error ServerResponseError(
            string `Transport error connecting to server: ${serverResponse.message()}`
        );
    }
}

# Extracts the first valid result from a stream of JsonRpcMessages.
#
# + messageStream - The stream of JsonRpcMessages to process.
# + return - The first valid ServerResult, a specific ServerResponseError, or StreamError.
isolated function extractResultFromMessageStream(stream<JsonRpcMessage, StreamError?> messageStream)
        returns ServerResult|ServerResponseError|StreamError {

    record {|JsonRpcMessage value;|}|StreamError? streamItem = messageStream.next();
    // Iterate until a valid result or an error is found.
    while streamItem !is () {
        if streamItem is StreamError {
            return streamItem;
        }

        JsonRpcMessage message = streamItem.value;
        return convertMessageToResult(message);
    }

    return error InvalidMessageTypeError("No valid messages found in server message stream.");
}

# Converts a JsonRpcMessage to a ServerResult.
#
# + message - The JsonRpcMessage to convert.
# + return - The extracted ServerResult, or an InvalidMessageTypeError.
isolated function convertMessageToResult(JsonRpcMessage message) returns ServerResult|ServerResponseError {
    if message is JsonRpcResponse {
        return message.result;
    }
    return error InvalidMessageTypeError("Received message from server is not a valid JsonRpcResponse.");
}
