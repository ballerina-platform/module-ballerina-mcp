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

// Keep wire-only additions out of the established application result APIs.
isolated function applicationResult(Result resultValue) returns Result {
    Result applicationValue = {...resultValue};
    foreach string fieldName in ["resultType", "ttlMs", "cacheScope"] {
        _ = applicationValue.removeIfHasKey(fieldName);
    }
    record {} applicationMeta = {...(applicationValue._meta ?: {})};
    _ = applicationMeta.removeIfHasKey(SERVER_INFO_META_KEY);
    if applicationMeta.length() == 0 {
        _ = applicationValue.removeIfHasKey("_meta");
    } else {
        applicationValue._meta = applicationMeta;
    }
    return applicationValue;
}

// Adapts a modern tool list to the established client API. Scalar output schemas cannot be
// represented by ToolDefinition, whose schema type has historically required an object root.
isolated function legacyCompatibleToolList(ProtocolListToolsResult protocolResult) returns ListToolsResult {
    ToolDefinition[] tools = [];
    foreach ProtocolToolDefinition protocolTool in protocolResult.tools {
        ToolDefinition toolInfo = {
            name: protocolTool.name,
            inputSchema: protocolTool.inputSchema
        };
        if protocolTool.title is string {
            toolInfo.title = protocolTool.title;
        }
        if protocolTool.icons is Icon[] {
            toolInfo.icons = protocolTool.icons;
        }
        if protocolTool.description is string {
            toolInfo.description = protocolTool.description;
        }
        if protocolTool.annotations is ToolAnnotations {
            toolInfo.annotations = protocolTool.annotations;
        }
        tools.push(toolInfo);
    }
    ListToolsResult resultValue = {tools};
    if protocolResult.nextCursor is Cursor {
        resultValue.nextCursor = protocolResult.nextCursor;
    }
    Result applicationValue = applicationResult(protocolResult);
    if applicationValue._meta is record {} {
        resultValue._meta = applicationValue._meta;
    }
    return resultValue;
}

// Adapts a modern result to the established client API. Preserve object structured content,
// which fits the historical type, and leave scalar, array, and null values to callToolWithResult().
isolated function legacyCompatibleToolResult(ProtocolCallToolResult protocolResult) returns CallToolResult {
    CallToolResult resultValue = {content: protocolResult.content};
    json structuredContent = protocolResult["structuredContent"];
    if structuredContent is map<json> {
        resultValue.structuredContent = structuredContent;
    }
    if protocolResult.isError is boolean {
        resultValue.isError = protocolResult.isError;
    }
    Result applicationValue = applicationResult(protocolResult);
    if applicationValue._meta is record {} {
        resultValue._meta = applicationValue._meta;
    }
    return resultValue;
}
