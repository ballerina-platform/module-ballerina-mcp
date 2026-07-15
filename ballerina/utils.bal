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

# Validates an initialize response result and checks protocol version compatibility.
#
# + response - The result received for the initialize request.
# + return - The validated InitializeResult, or a ClientError on type or version mismatch.
isolated function validateInitializeResponse(ServerResult response) returns InitializeResult|ClientError {
    if response !is InitializeResult {
        return error ClientInitializationError(
                string `Initialization failed: unexpected response type '${
                    (typeof response).toString()}' received from server.`
            );
    }
    final string protocolVersion = response.protocolVersion;
    if (!SUPPORTED_PROTOCOL_VERSIONS.some(v => v == protocolVersion)) {
        return error ProtocolVersionError(
                string `Server protocol version '${
                    protocolVersion}' is not supported. Supported versions: ${
                    SUPPORTED_PROTOCOL_VERSIONS.toString()}.`
            );
    }
    return response;
}

# Ensures a server result is a ListToolsResult.
#
# + result - The result received for the tools/list request.
# + return - The ListToolsResult, or a ListToolsError on type mismatch.
isolated function ensureListToolsResult(ServerResult result) returns ListToolsResult|ClientError {
    if result is ListToolsResult {
        return result;
    }
    return error ListToolsError(
        string `Tool listing failed: unexpected result type '${(typeof result).toString()}' received.`
    );
}

# Ensures a server result is a CallToolResult.
#
# + result - The result received for the tools/call request.
# + return - The CallToolResult, or a ToolCallError on type mismatch.
isolated function ensureCallToolResult(ServerResult result) returns CallToolResult|ClientError {
    if result is CallToolResult {
        return result;
    }
    return error ToolCallError(
        string `Tool call failed: unexpected result type '${(typeof result).toString()}' received.`
    );
}

# Processes a server response and extracts the result.
#
# + serverResponse - The response from the server, which may be a single JsonRpcMessage, a stream, or a transport error.
# + return - Extracted ServerResult, ServerResponseError, or StreamError.
isolated function processServerResponse(JsonRpcMessage|stream<JsonRpcMessage, StreamError?>|TransportError? serverResponse)
        returns ServerResult|ServerResponseError|StreamError {

    if serverResponse is stream<JsonRpcMessage, StreamError?> {
        return extractResultFromMessageStream(serverResponse);
    }

    if serverResponse is JsonRpcMessage {
        return extractResultFromMessage(serverResponse);
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
isolated function extractResultFromMessageStream(stream<JsonRpcMessage, StreamError?> messageStream)
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
isolated function extractResultFromMessage(JsonRpcMessage message) returns ServerResult|ServerResponseError {
    if message is JsonRpcResponse {
        return message.result;
    }
    if message is JsonRpcError {
        return error ServerResponseError(string `Received JSON-RPC error from server: ${message.toJsonString()}`);
    }
    return error InvalidMessageTypeError("Received message from server is not a valid JsonRpcResponse.");
}
