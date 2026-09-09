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

isolated function isModernRequest(JsonRpcRequest requestMessage, http:Headers requestHeaders) returns boolean {
    // initialize always belongs to the legacy handshake, including older clients with a version header.
    if requestMessage.method == REQUEST_INITIALIZE {
        return false;
    }
    Meta? requestMeta = requestMessage.params?._meta;
    if requestMeta is Meta && requestMeta.hasKey(PROTOCOL_META_KEY) {
        return true;
    }
    string? headerVersion = getProtocolVersionFromHeaders(requestHeaders);
    foreach string legacyVersion in ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"] {
        if legacyVersion == headerVersion {
            return false;
        }
    }
    return headerVersion is string;
}

isolated function unsupportedProtocolResponse(string requestedVersion, string[] supportedVersions, RequestId? requestId)
        returns http:BadRequest => {
    body: {
        jsonrpc: JSONRPC_VERSION, id: requestId,
        'error: {code: UNSUPPORTED_PROTOCOL_VERSION, message: "Unsupported protocol version",
            data: {supported: supportedVersions, requested: requestedVersion}}
    }
};

isolated function modernError(int errorCode, string errorMessage, RequestId requestId)
        returns http:BadRequest => {body: createJsonRpcError(errorCode, errorMessage, requestId)};

isolated function modernCapabilities(StreamableHttpServiceConfiguration serviceConfig) returns ServerCapabilities {
    ServerCapabilities serverCapabilities = {...(serviceConfig.options?.capabilities ?: {})};
    // No runtime for these optional capabilities is installed by this module.
    foreach string capabilityName in ["tasks", "logging", "prompts", "resources", "completions"] {
        _ = serverCapabilities.removeIfHasKey(capabilityName);
    }
    serverCapabilities.tools = {listChanged: false};
    return serverCapabilities;
}

isolated function modernResult(Result resultValue, Implementation serverInfo, RequestId requestId,
        boolean cacheable = false) returns http:Ok {
    Result wireResult = {...resultValue};
    wireResult["resultType"] = wireResult["resultType"] ?: "complete";
    record {} resultMeta = {...(wireResult._meta ?: {})};
    resultMeta[SERVER_INFO_META_KEY] = serverInfo;
    wireResult._meta = resultMeta;
    if cacheable {
        wireResult["ttlMs"] = wireResult["ttlMs"] ?: 0;
        wireResult["cacheScope"] = wireResult["cacheScope"] ?: "private";
    }
    return {body: {jsonrpc: JSONRPC_VERSION, id: requestId, result: wireResult}};
}

isolated function handleModernRequest(Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService|ProtocolService mcpService,
        JsonRpcRequest requestMessage, http:Request httpRequest, http:Headers requestHeaders,
        StreamableHttpServiceConfiguration serviceConfig) returns http:Ok|http:BadRequest|http:NotFound|http:Forbidden {
    string|http:HeaderNotFoundError originHeader = requestHeaders.getHeader("origin");
    if originHeader is string {
        boolean allowedOrigin = false;
        foreach string allowedValue in serviceConfig.allowedOrigins {
            if allowedValue == originHeader {
                allowedOrigin = true;
                break;
            }
        }
        if !allowedOrigin {
            return <http:Forbidden>{body: createJsonRpcError(INVALID_REQUEST, "Origin is not allowed", requestMessage.id)};
        }
    }
    string requestedVersion = getProtocolVersionFromHeaders(requestHeaders) ?: "";
    if serviceConfig.protocolMode == "legacy" || requiresLegacySession(mcpService) {
        return unsupportedProtocolResponse(requestedVersion,
                SUPPORTED_PROTOCOL_VERSIONS.filter(versionValue => versionValue != MODERN_PROTOCOL_VERSION),
                requestMessage.id);
    }
    ModernRequestMeta|error requestMeta = requestMessage.params?._meta.cloneWithType();
    if requestMeta is error {
        return modernError(INVALID_PARAMS, "Required protocol version and client capabilities metadata is missing or invalid",
                requestMessage.id);
    }
    if requestedVersion != requestMeta.io\.modelcontextprotocol\/protocolVersion ||
            requestedVersion == "" {
        return modernError(HEADER_MISMATCH, "MCP-Protocol-Version must match request metadata", requestMessage.id);
    }
    if requestedVersion != MODERN_PROTOCOL_VERSION {
        return unsupportedProtocolResponse(requestedVersion,
                serviceConfig.protocolMode == "modern" ? [MODERN_PROTOCOL_VERSION] : SUPPORTED_PROTOCOL_VERSIONS,
                requestMessage.id);
    }
    string|error methodHeader = requestHeaders.getHeader(METHOD_HEADER);
    if methodHeader is error || methodHeader != requestMessage.method {
        return modernError(HEADER_MISMATCH, "Mcp-Method must match the request method", requestMessage.id);
    }
    if requestMessage.method == "server/discover" {
        DiscoverResult discoverResult = {
            supportedVersions: serviceConfig.protocolMode == "modern" ? [MODERN_PROTOCOL_VERSION] : SUPPORTED_PROTOCOL_VERSIONS,
            capabilities: modernCapabilities(serviceConfig)
        };
        string? instructionsText = serviceConfig.options?.instructions;
        if instructionsText is string {
            discoverResult.instructions = instructionsText;
        }
        return modernResult(discoverResult, serviceConfig.info, requestMessage.id, cacheable = true);
    }
    if requestMessage.method != REQUEST_LIST_TOOLS && requestMessage.method != REQUEST_CALL_TOOL {
        return <http:NotFound>{body: createJsonRpcError(METHOD_NOT_FOUND, "Method not found", requestMessage.id)};
    }
    ProtocolListToolsResult|error toolList = listProtocolTools(mcpService, httpRequest, requestHeaders, serviceConfig);
    if toolList is error {
        return createJsonRpcErrorResponse(INTERNAL_ERROR, toolList.message(), requestMessage.id);
    }
    foreach ProtocolToolDefinition toolInfo in toolList.tools {
        _ = toolInfo.removeIfHasKey("execution");
        Error? schemaError = validateToolSchema(toolInfo);
        if schemaError is Error {
            return createJsonRpcErrorResponse(INTERNAL_ERROR, schemaError.message(), requestMessage.id);
        }
        var headerDefinition = toolParameterHeaders(toolInfo.inputSchema, {});
        if headerDefinition is Error {
            return createJsonRpcErrorResponse(INTERNAL_ERROR, headerDefinition.message(), requestMessage.id);
        }
    }
    if toolList.ttlMs < 0 {
        return createJsonRpcErrorResponse(INTERNAL_ERROR, "ttlMs must be non-negative", requestMessage.id);
    }
    if requestMessage.method == REQUEST_LIST_TOOLS {
        toolList.tools = toolList.tools.sort(key = isolated function(ProtocolToolDefinition toolInfo) returns string => toolInfo.name);
        return modernResult(toolList, serviceConfig.info, requestMessage.id, cacheable = true);
    }
    CallToolParams|error callParams = requestMessage.params.cloneWithType();
    if callParams is error {
        return createJsonRpcErrorResponse(INVALID_PARAMS, "Invalid tool call parameters", requestMessage.id);
    }
    string|error nameHeader = requestHeaders.getHeader(NAME_HEADER);
    if nameHeader is error {
        return modernError(HEADER_MISMATCH, "Missing Mcp-Name header", requestMessage.id);
    }
    string|Error decodedName = decodeProtocolHeader(nameHeader);
    if decodedName is Error || decodedName != callParams.name {
        return modernError(HEADER_MISMATCH, "Mcp-Name must match the tool name", requestMessage.id);
    }
    ProtocolToolDefinition? selectedTool = ();
    foreach ProtocolToolDefinition toolInfo in toolList.tools {
        if toolInfo.name == callParams.name {
            selectedTool = toolInfo;
            break;
        }
    }
    if selectedTool is () {
        return createJsonRpcErrorResponse(INVALID_PARAMS, "Unknown tool name", requestMessage.id);
    }
    Error? headerError = validateToolHeaders(selectedTool.inputSchema, callParams.arguments ?: {}, requestHeaders);
    if headerError is Error {
        return modernError(HEADER_MISMATCH, headerError.message(), requestMessage.id);
    }
    Error? inputSchemaError = validateProtocolSchema(selectedTool.inputSchema.toJsonString(),
            (callParams.arguments ?: {}).toJsonString(), true);
    if inputSchemaError is Error {
        return modernResult(toToolExecutionError(inputSchemaError, callParams.name), serviceConfig.info, requestMessage.id);
    }
    if callParams.task !is () {
        return createJsonRpcErrorResponse(INVALID_PARAMS, "Legacy task parameters are not supported in modern MCP",
                requestMessage.id);
    }
    ProtocolCallToolResult|InputRequiredResult|error callResult = callProtocolTool(mcpService, callParams,
            httpRequest, requestHeaders, serviceConfig);
    if callResult is error {
        return createJsonRpcErrorResponse(INTERNAL_ERROR, callResult.message(), requestMessage.id);
    }
    if callResult is InputRequiredResult {
        Error? inputError = validateInputRequired(callResult, requestMeta.io\.modelcontextprotocol\/clientCapabilities);
        if inputError is Error {
            return modernError(MISSING_REQUIRED_CLIENT_CAPABILITY, inputError.message(), requestMessage.id);
        }
    }
    if callResult is ProtocolCallToolResult && callResult.isError != true {
        OutputSchema? outputSchema = selectedTool.outputSchema;
        if outputSchema is OutputSchema {
            if !callResult.hasKey("structuredContent") {
                return createJsonRpcErrorResponse(INTERNAL_ERROR, "Missing structured output for declared outputSchema",
                        requestMessage.id);
            }
            Error? outputError = validateProtocolSchema(outputSchema.toJsonString(),
                    callResult?.structuredContent.toJsonString(), true);
            if outputError is Error {
                return createJsonRpcErrorResponse(INTERNAL_ERROR, outputError.message(), requestMessage.id);
            }
        }
    }
    return modernResult(callResult, serviceConfig.info, requestMessage.id);
}

isolated function listProtocolTools(Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService|ProtocolService mcpService,
        http:Request httpRequest, http:Headers requestHeaders, StreamableHttpServiceConfiguration serviceConfig)
        returns ProtocolListToolsResult|error {
    if mcpService is ProtocolService {
        return trap invokeProtocolOnListTools(mcpService);
    }
    ListToolsResult|Error listResult;
    if mcpService is StreamableHttpAdvancedService {
        listResult = trapListToolsFailure(trap invokeAdvancedOnListTools(mcpService, requestHeaders, httpRequest,
                extractHeaderValues(requestHeaders), serviceConfig.httpConfig.treatNilableAsOptional));
    } else if mcpService is AdvancedService {
        listResult = trapListToolsFailure(trap invokeOnListTools(mcpService));
    } else if mcpService is Service|StreamableHttpService {
        listResult = trapListToolsFailure(trap listToolsForRemoteFunctions(mcpService));
    }
    else {
        return error("Unsupported MCP service");
    }
    return (check listResult).cloneWithType();
}

isolated function callProtocolTool(Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService|ProtocolService mcpService,
        CallToolParams callParams, http:Request httpRequest, http:Headers requestHeaders,
        StreamableHttpServiceConfiguration serviceConfig) returns ProtocolCallToolResult|InputRequiredResult|error {
    if mcpService is ProtocolService {
        return trap invokeProtocolOnCallTool(mcpService, callParams);
    }
    CallToolResult|error callResult;
    if mcpService is StreamableHttpAdvancedService {
        callResult = trap invokeAdvancedOnCallTool(mcpService, callParams, (), requestHeaders, httpRequest,
                extractHeaderValues(requestHeaders), serviceConfig.httpConfig.treatNilableAsOptional);
    } else if mcpService is AdvancedService {
        callResult = trap invokeOnCallTool(mcpService, callParams, ());
    } else if mcpService is Service|StreamableHttpService {
        callResult = trap callToolForRemoteFunctions(mcpService, callParams, (), requestHeaders, httpRequest,
                extractHeaderValues(requestHeaders), serviceConfig.httpConfig.treatNilableAsOptional);
        if callResult is error {
            callResult = toToolExecutionError(callResult, callParams.name);
        }
    }
    else {
        return error("Unsupported MCP service");
    }
    return (check callResult).cloneWithType();
}

isolated function validateInputRequired(InputRequiredResult inputResult, ClientCapabilities clientCapabilities) returns Error? {
    if inputResult.inputRequests is () && inputResult.requestState is () {
        return error("Input-required result must contain inputRequests or requestState");
    }
    foreach InputRequest inputRequest in (inputResult.inputRequests ?: {}).toArray() {
        string capabilityName = inputRequest.method == "elicitation/create" ? "elicitation" :
                inputRequest.method == "sampling/createMessage" ? "sampling" : "roots";
        if !clientCapabilities.hasKey(capabilityName) {
            return error("Client did not declare the required capability: " + capabilityName);
        }
    }
}
