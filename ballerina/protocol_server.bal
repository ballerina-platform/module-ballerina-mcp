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

isolated function isModernRequest(JsonRpcRequest|JsonRpcNotification requestMessage, http:Headers requestHeaders) returns boolean {
    // initialize always belongs to the legacy handshake, including older clients with a version header.
    if requestMessage.method == REQUEST_INITIALIZE {
        return false;
    }
    record {}? requestMeta = requestMessage.params?._meta;
    if requestMeta is record {} && requestMeta.hasKey(PROTOCOL_META_KEY) {
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
        jsonrpc: JSONRPC_VERSION,
        id: requestId,
        'error: {
            code: UNSUPPORTED_PROTOCOL_VERSION,
            message: "Unsupported protocol version",
            data: {supported: supportedVersions, requested: requestedVersion}
        }
    }
};

isolated function modernError(int errorCode, string errorMessage, RequestId requestId)
        returns http:BadRequest => {body: createJsonRpcError(errorCode, errorMessage, requestId)};

isolated function modernCapabilities(StreamableHttpServiceConfiguration serviceConfig, boolean supportsSubscriptions = false) returns ServerCapabilities {
    ServerCapabilities serverCapabilities = {...(serviceConfig.options?.capabilities ?: {})};
    // No runtime for these optional capabilities is installed by this module.
    foreach string capabilityName in ["tasks", "logging", "prompts", "resources", "completions"] {
        _ = serverCapabilities.removeIfHasKey(capabilityName);
    }
    serverCapabilities.tools = {listChanged: supportsSubscriptions};
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

isolated function handleModernRequest(Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService mcpService,
        JsonRpcRequest requestMessage, http:Request httpRequest, http:Headers requestHeaders,
        StreamableHttpServiceConfiguration serviceConfig) returns http:Ok|http:BadRequest|http:NotFound|http:Forbidden|http:Response {
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
            capabilities: modernCapabilities(serviceConfig,
                mcpService is StreamableHttpAdvancedService && hasSubscriptionHandler(mcpService))
        };
        string? instructionsText = serviceConfig.options?.instructions;
        if instructionsText is string {
            discoverResult.instructions = instructionsText;
        }
        return modernResult(discoverResult, serviceConfig.info, requestMessage.id, cacheable = true);
    }
    if requestMessage.method == "subscriptions/listen" && mcpService is StreamableHttpAdvancedService &&
            hasSubscriptionHandler(mcpService) {
        RequestParams listenParams = requestMessage.params ?: {};
        SubscriptionFilter|error requestedFilter = listenParams["notifications"].cloneWithType();
        if requestedFilter is error {
            return createJsonRpcErrorResponse(INVALID_PARAMS, "Invalid subscription filter", requestMessage.id);
        }
        SubscriptionFilter acceptedFilter = {toolsListChanged: requestedFilter.toolsListChanged};
        var eventSource = trap invokeOnSubscribe(mcpService, acceptedFilter);
        if eventSource is error {
            return createJsonRpcErrorResponse(INTERNAL_ERROR, eventSource.message(), requestMessage.id);
        }
        ServerSubscriptionStream streamIterator = new (eventSource, requestMessage.id, acceptedFilter);
        stream<http:SseEvent, error?> responseStream = new (streamIterator);
        http:Response httpResponse = new;
        httpResponse.setSseEventStream(responseStream);
        httpResponse.setHeader("X-Accel-Buffering", "no");
        return httpResponse;
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
            var requiredCapabilities = inputError.detail()["requiredCapabilities"];
            if requiredCapabilities is anydata && requiredCapabilities is map<anydata> {
                return <http:BadRequest>{
                    body: {
                        jsonrpc: JSONRPC_VERSION,
                        id: requestMessage.id,
                        'error: {
                            code: MISSING_REQUIRED_CLIENT_CAPABILITY,
                            message: inputError.message(),
                            data: {requiredCapabilities: requiredCapabilities}
                        }
                    }
                };
            }
            return createJsonRpcErrorResponse(INTERNAL_ERROR, inputError.message(), requestMessage.id);
        }
    }
    if callResult is ProtocolCallToolResult && callResult.isError != true {
        OutputSchema? outputSchema = selectedTool.outputSchema;
        if outputSchema is OutputSchema {
            if !callResult.hasKey("structuredContent") {
                return createJsonRpcErrorResponse(INTERNAL_ERROR, "Missing structured output for declared outputSchema",
                        requestMessage.id);
            }
        }
    }
    return modernResult(callResult, serviceConfig.info, requestMessage.id);
}

isolated function listProtocolTools(Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService mcpService,
        http:Request httpRequest, http:Headers requestHeaders, StreamableHttpServiceConfiguration serviceConfig)
        returns ProtocolListToolsResult|error {
    ListToolsResult|Error listResult = error ServerError("Unsupported MCP service");
    if mcpService is StreamableHttpAdvancedService {
        ListToolsResult|ProtocolListToolsResult|error advancedResult =
                trap invokeAdvancedOnListTools(mcpService, requestHeaders, httpRequest,
                    extractHeaderValues(requestHeaders), serviceConfig.httpConfig.treatNilableAsOptional);
        if advancedResult is ProtocolListToolsResult {
            return advancedResult.cloneWithType();
        }
        if advancedResult is error {
            listResult = trapListToolsFailure(advancedResult);
        } else {
            ListToolsResult|error convertedResult = advancedResult.cloneWithType();
            listResult = convertedResult is error ? error ServerError(convertedResult.message()) : convertedResult;
        }
    } else if mcpService is AdvancedService {
        listResult = trapListToolsFailure(trap invokeOnListTools(mcpService));
    } else if mcpService is Service|StreamableHttpService {
        return listProtocolToolsForRemoteFunctions(mcpService);
    }
    else {
        return error("Unsupported MCP service");
    }
    return (check listResult).cloneWithType();
}

isolated function callProtocolTool(Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService mcpService,
        CallToolParams callParams, http:Request httpRequest, http:Headers requestHeaders,
        StreamableHttpServiceConfiguration serviceConfig) returns ProtocolCallToolResult|InputRequiredResult|error {
    CallToolParams applicationParams = callParams.clone();
    Meta applicationMeta = {...(callParams._meta ?: {})};
    foreach string metaKey in [PROTOCOL_META_KEY, CAPABILITIES_META_KEY, CLIENT_INFO_META_KEY, LOG_LEVEL_META_KEY] {
        _ = applicationMeta.removeIfHasKey(metaKey);
    }
    if applicationMeta.length() == 0 {
        _ = applicationParams.removeIfHasKey("_meta");
    } else {
        applicationParams._meta = applicationMeta;
    }
    CallToolResult|error callResult = error ServerError("Unsupported MCP service");
    if mcpService is StreamableHttpAdvancedService {
        CallToolResult|ProtocolCallToolResult|InputRequiredResult|error advancedResult =
                trap invokeAdvancedOnCallTool(mcpService, applicationParams, (), requestHeaders, httpRequest,
                    extractHeaderValues(requestHeaders), serviceConfig.httpConfig.treatNilableAsOptional);
        if advancedResult is ProtocolCallToolResult|InputRequiredResult {
            return advancedResult;
        }
        if advancedResult is error {
            callResult = advancedResult;
        } else {
            callResult = advancedResult.cloneWithType();
        }
    } else if mcpService is AdvancedService {
        callResult = trap invokeOnCallTool(mcpService, applicationParams, ());
    } else if mcpService is Service|StreamableHttpService {
        ProtocolCallToolResult|error structuredResult = trap callProtocolToolForRemoteFunctions(mcpService,
                applicationParams, (), requestHeaders, httpRequest,
                extractHeaderValues(requestHeaders), serviceConfig.httpConfig.treatNilableAsOptional);
        if structuredResult is error {
            return toToolExecutionError(structuredResult, callParams.name).cloneWithType();
        }
        return structuredResult;
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
            return error("Client did not declare the required capability: " + capabilityName,
                    requiredCapabilities = {[capabilityName]: {}});
        }
        if inputRequest.method == "elicitation/create" {
            RequestParams inputParams = inputRequest.params ?: {};
            anydata inputMode = inputParams["mode"] ?: "form";
            if inputMode != "form" && inputMode != "url" {
                return error("Invalid elicitation mode");
            }
            record {} elicitationCapabilities = clientCapabilities.elicitation ?: {};
            boolean supportedMode = inputMode == "form" ?
                    (elicitationCapabilities.length() == 0 || elicitationCapabilities.hasKey("form")) :
                    elicitationCapabilities.hasKey("url");
            if !supportedMode {
                return error("Client did not declare the required elicitation mode",
                        requiredCapabilities = {elicitation: {[<string>inputMode]: {}}});
            }
        }
    }
}
