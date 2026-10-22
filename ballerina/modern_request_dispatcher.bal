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
import ballerina/log;

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
    return headerVersion is string && !isLegacyProtocolVersion(headerVersion);
}

isolated function advertisedProtocolVersions(StreamableHttpServiceConfiguration serviceConfig) returns string[] =>
    serviceConfig.protocolMode == "modern" ? MODERN_PROTOCOL_VERSIONS :
        [...MODERN_PROTOCOL_VERSIONS, ...LEGACY_PROTOCOL_VERSIONS];

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

isolated function modernCapabilities(StreamableHttpServiceConfiguration serviceConfig) returns ServerCapabilities {
    ServerCapabilities serverCapabilities = {...(serviceConfig.options?.capabilities ?: {})};
    // No runtime for these optional capabilities is installed by this module.
    foreach string capabilityName in ["tasks", "logging", "prompts", "resources", "completions"] {
        _ = serverCapabilities.removeIfHasKey(capabilityName);
    }
    serverCapabilities.tools = {listChanged: false};
    return serverCapabilities;
}

isolated function modernResult(WireResult resultValue, Implementation serverInfo, RequestId requestId,
        CacheHint? cacheHint = ()) returns http:Ok {
    WireResult wireResult = {...resultValue};
    wireResult["resultType"] = wireResult["resultType"] ?: "complete";
    ResultMeta resultMeta = {...(wireResult._meta ?: {})};
    Implementation effectiveServerInfo = resultMeta.serverInfo ?: serverInfo;
    _ = resultMeta.removeIfHasKey("serverInfo");
    resultMeta[SERVER_INFO_META_KEY] = effectiveServerInfo;
    wireResult._meta = resultMeta;
    // Each hint field resolves independently: the handler's value, then the configured hint, then the default.
    if cacheHint is CacheHint {
        wireResult["ttlMs"] = wireResult["ttlMs"] ?: cacheHint.ttlMs ?: 0;
        wireResult["cacheScope"] = wireResult["cacheScope"] ?: cacheHint.cacheScope ?: "private";
    }
    return {body: {jsonrpc: JSONRPC_VERSION, id: requestId, result: wireResult}};
}

isolated function handleModernRequest(StreamableHttpService|StreamableHttpAdvancedService mcpService,
        JsonRpcRequest requestMessage, http:Request httpRequest, http:Headers requestHeaders,
        StreamableHttpServiceConfiguration serviceConfig, RequestStateSigner requestStateSigner,
        ServerAuthenticator? authenticator = (), readonly & AuthContext? authContext = ())
        returns http:Ok|http:BadRequest|http:NotFound|http:Forbidden|http:InternalServerError|http:Response {
    string requestedVersion = getProtocolVersionFromHeaders(requestHeaders) ?: "";
    if serviceConfig.protocolMode == "legacy" || requiresLegacySession(mcpService) {
        return unsupportedProtocolResponse(requestedVersion, LEGACY_PROTOCOL_VERSIONS, requestMessage.id);
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
    if !isModernProtocolVersion(requestedVersion) {
        return unsupportedProtocolResponse(requestedVersion, advertisedProtocolVersions(serviceConfig),
                requestMessage.id);
    }
    string|error methodHeader = requestHeaders.getHeader(METHOD_HEADER);
    if methodHeader is error || methodHeader != requestMessage.method {
        return modernError(HEADER_MISMATCH, "Mcp-Method must match the request method", requestMessage.id);
    }
    if requestMessage.method == "server/discover" {
        CacheHint discoverHint = serviceConfig.cacheHints.discover ?: {};
        DiscoverResult discoverResult = {
            supportedVersions: advertisedProtocolVersions(serviceConfig),
            capabilities: modernCapabilities(serviceConfig),
            ttlMs: discoverHint.ttlMs ?: 0,
            cacheScope: discoverHint.cacheScope ?: "private"
        };
        string? instructionsText = serviceConfig.options?.instructions;
        if instructionsText is string {
            discoverResult.instructions = instructionsText;
        }
        return modernResult(discoverResult, serviceConfig.info, requestMessage.id, discoverHint);
    }
    if requestMessage.method != REQUEST_LIST_TOOLS && requestMessage.method != REQUEST_CALL_TOOL {
        return <http:NotFound>{body: createJsonRpcError(METHOD_NOT_FOUND, "Method not found", requestMessage.id)};
    }
    Cursor?|http:Ok cursor = requestMessage.method == REQUEST_LIST_TOOLS ? requestCursor(requestMessage) : ();
    if cursor is http:Ok {
        return cursor;
    }
    ToolPage|error toolList = listValidatedToolPage(mcpService, httpRequest, requestHeaders,
            serviceConfig, authContext, cursor);
    if toolList is error {
        return listingFailureResponse(toolList, authenticator, requestMessage.id);
    }
    if requestMessage.method == REQUEST_LIST_TOOLS {
        toolList.tools = toolList.tools.sort(key = isolated function(ToolInfo toolInfo) returns string => toolInfo.name);
        return modernResult(toolList, serviceConfig.info, requestMessage.id, serviceConfig.cacheHints.listTools ?: {});
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
    // A paginating service may list the tool on a later page.
    ToolInfo? selectedTool = findTool(toolList, callParams.name);
    map<boolean> visitedCursors = {};
    Cursor? nextCursor = toolList.nextCursor;
    while selectedTool is () && nextCursor is Cursor && !visitedCursors.hasKey(nextCursor) &&
            visitedCursors.length() < MAX_TOOL_LIST_PAGES - 1 {
        visitedCursors[nextCursor] = true;
        ToolPage|error page = listValidatedToolPage(mcpService, httpRequest, requestHeaders,
                serviceConfig, authContext, nextCursor);
        if page is error {
            return listingFailureResponse(page, authenticator, requestMessage.id);
        }
        selectedTool = findTool(page, callParams.name);
        nextCursor = page.nextCursor;
    }
    if selectedTool is () {
        return createJsonRpcErrorResponse(INVALID_PARAMS, "Unknown tool name", requestMessage.id);
    }
    if authenticator is ServerAuthenticator && authContext is AuthContext {
        http:Forbidden? denied = authenticator.authorizeTool(authContext, callParams.name);
        if denied is http:Forbidden {
            return denied;
        }
    }
    Error? headerError = validateToolHeaders(selectedTool.inputSchema, callParams.arguments ?: {}, requestHeaders);
    if headerError is Error {
        return modernError(HEADER_MISMATCH, headerError.message(), requestMessage.id);
    }
    string? requestState = callParams.requestState;
    if requestState is string {
        string|error verifiedState = requestStateSigner.verify(requestState, callParams, authContext);
        if verifiedState is error {
            log:printDebug("Rejected request state", verifiedState, toolName = callParams.name);
            return <http:Ok>{
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: requestMessage.id,
                    'error: {
                        code: INVALID_PARAMS,
                        message: "Invalid or expired requestState",
                        data: {reason: "invalid_request_state"}
                    }
                }
            };
        }
        callParams.requestState = verifiedState;
    }
    ToolResult|InputRequiredResult|error callResult = callProtocolTool(mcpService, callParams,
            httpRequest, requestHeaders, serviceConfig, authContext);
    if callResult is InsufficientScopeError {
        return insufficientScopeFor(authenticator, callResult);
    }
    if callResult is error {
        return createJsonRpcErrorResponse(handlerErrorCode(callResult),
                toServerError(callResult, callParams.name).message(), requestMessage.id);
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
        string? returnedState = callResult.requestState;
        if returnedState is string {
            string|error signedState = requestStateSigner.sign(returnedState, callParams, authContext);
            if signedState is error {
                return createJsonRpcErrorResponse(INTERNAL_ERROR, "Failed to sign request state", requestMessage.id);
            }
            callResult.requestState = signedState;
        }
    }
    if callResult is ToolResult && callResult.isError != true {
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

# Lists one page of a service's tools for a modern request, rejecting invalid header declarations.
isolated function listValidatedToolPage(StreamableHttpService|StreamableHttpAdvancedService mcpService,
        http:Request httpRequest, http:Headers requestHeaders, StreamableHttpServiceConfiguration serviceConfig,
        readonly & AuthContext? authContext, Cursor? cursor) returns ToolPage|error {
    ToolPage toolList = check listProtocolTools(mcpService, httpRequest, requestHeaders, serviceConfig,
            authContext, cursor);
    foreach ToolInfo toolInfo in toolList.tools {
        _ = toolInfo.removeIfHasKey("execution");
        var headerDefinition = toolParameterHeaders(toolInfo.inputSchema, {});
        // An invalid header declaration is a defect in the service, never the caller's invalid params.
        if headerDefinition is Error {
            return error ServerError(headerDefinition.message());
        }
    }
    int? ttlMs = toolList.ttlMs;
    if ttlMs is int && ttlMs < 0 {
        log:printError("onListTools returned a negative ttlMs; using 0", ttlMs = ttlMs);
        toolList.ttlMs = 0;
    }
    return toolList;
}

isolated function listingFailureResponse(error failure, ServerAuthenticator? authenticator, RequestId requestId)
        returns http:Ok|http:Forbidden|http:InternalServerError {
    // The tool list also resolves `tools/call`, so a listing that needs more scope challenges both.
    if failure is InsufficientScopeError {
        return insufficientScopeFor(authenticator, failure);
    }
    return createJsonRpcErrorResponse(handlerErrorCode(failure), failure.message(), requestId);
}

isolated function findTool(ToolPage toolList, string toolName) returns ToolInfo? {
    foreach ToolInfo toolInfo in toolList.tools {
        if toolInfo.name == toolName {
            return toolInfo;
        }
    }
    return ();
}

isolated function listProtocolTools(StreamableHttpService|StreamableHttpAdvancedService mcpService,
        http:Request httpRequest, http:Headers requestHeaders, StreamableHttpServiceConfiguration serviceConfig,
        readonly & AuthContext? authContext, Cursor? cursor = ()) returns ToolPage|error {
    ToolPage|Error listResult = error ServerError("Unsupported MCP service");
    if mcpService is StreamableHttpAdvancedService {
        ToolPage|error advancedResult =
                trap invokeAdvancedOnListTools(mcpService, cursor, requestHeaders, httpRequest,
                    extractHeaderValues(requestHeaders), serviceConfig.httpConfig.treatNilableAsOptional,
                    authContext);
        if advancedResult is error {
            listResult = trapListToolsFailure(advancedResult);
        } else {
            listResult = advancedResult;
        }
    } else if mcpService is StreamableHttpService {
        return listProtocolToolsForRemoteFunctions(mcpService);
    }
    else {
        return error("Unsupported MCP service");
    }
    return (check listResult).cloneWithType();
}

isolated function callProtocolTool(StreamableHttpService|StreamableHttpAdvancedService mcpService,
        CallToolParams callParams, http:Request httpRequest, http:Headers requestHeaders,
        StreamableHttpServiceConfiguration serviceConfig, readonly & AuthContext? authContext)
        returns ToolResult|InputRequiredResult|error {
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
    ToolResult|error callResult = error ServerError("Unsupported MCP service");
    if mcpService is StreamableHttpAdvancedService {
        ToolResult|InputRequiredResult|error advancedResult =
                trap invokeAdvancedOnCallTool(mcpService, applicationParams, (), requestHeaders, httpRequest,
                    extractHeaderValues(requestHeaders), serviceConfig.httpConfig.treatNilableAsOptional,
                    authContext);
        if advancedResult is InputRequiredResult {
            return advancedResult;
        }
        if advancedResult is error {
            callResult = advancedResult;
        } else {
            callResult = advancedResult.cloneWithType();
        }
    } else if mcpService is StreamableHttpService {
        Context toolContext = new ((callParams.inputResponses ?: {}).cloneReadOnly(), callParams.requestState);
        ToolResult|InputRequiredResult|error structuredResult = trap callProtocolToolForRemoteFunctions(mcpService,
                applicationParams, (), requestHeaders, httpRequest,
                extractHeaderValues(requestHeaders), serviceConfig.httpConfig.treatNilableAsOptional,
                authContext, toolContext);
        if structuredResult is InsufficientScopeError || structuredResult is ParameterBindingError {
            return structuredResult;
        }
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
        FormElicitationParams|UrlElicitationParams inputParams = inputRequest.params;
        if !clientCapabilities.hasKey("elicitation") {
            return error("Client did not declare the required capability: elicitation",
                    requiredCapabilities = {elicitation: {[inputParams.mode]: {}}});
        }
        record {} elicitationCapabilities = clientCapabilities.elicitation ?: {};
        boolean supportedMode = inputParams.mode == "form" ?
                (elicitationCapabilities.length() == 0 || elicitationCapabilities.hasKey("form")) :
                elicitationCapabilities.hasKey("url");
        if !supportedMode {
            return error("Client did not declare the required elicitation mode",
                    requiredCapabilities = {elicitation: {[inputParams.mode]: {}}});
        }
        if inputParams is FormElicitationParams {
            check validateFormElicitation(inputParams);
        } else {
            check validateUrlElicitation(inputParams);
        }
    }
}

isolated function validateUrlElicitation(UrlElicitationParams urlParams) returns Error? {
    if urlParams.message.trim().length() == 0 {
        return error("URL elicitation must have a message");
    }
    // A scheme and a host, so the client can open the link without a base URL.
    if !re `[A-Za-z][A-Za-z0-9+.\-]*://([^\s/?#@]*@)?(\[[0-9A-Fa-f:.]+\]|[^\s/?#@:\[\]]+)(:[0-9]*)?([/?#]\S*)?`
            .isFullMatch(urlParams.url) {
        return error("URL elicitation must have an absolute URL");
    }
}

isolated function validateFormElicitation(FormElicitationParams formParams) returns Error? {
    if formParams.message.trim().length() == 0 {
        return error("Form elicitation must have a message");
    }
    map<FormFieldSchema> properties = formParams.requestedSchema.properties;
    foreach string fieldName in formParams.requestedSchema.required ?: [] {
        if !properties.hasKey(fieldName) {
            return error(string `Form schema requires undeclared field '${fieldName}'`);
        }
    }
    foreach [string, FormFieldSchema] [fieldName, fieldSchema] in properties.entries() {
        // MCP keeps the enumNames shape only so clients can read older servers.
        if fieldSchema is LegacyTitledEnumFieldSchema {
            return error(string `Form schema field '${fieldName}' uses enumNames; use oneOf with titles`);
        }
        if !isValidFormField(fieldSchema) {
            return error(string `Form schema field '${fieldName}' is outside the allowed subset`);
        }
    }
}

// The types fix each field's shape; this checks the constraints types cannot express.
isolated function isValidFormField(FormFieldSchema fieldSchema) returns boolean {
    if fieldSchema is StringFieldSchema {
        return isValidRange(fieldSchema.minLength, fieldSchema.maxLength);
    }
    if fieldSchema is NumberFieldSchema {
        decimal? minimum = fieldSchema.minimum;
        decimal? maximum = fieldSchema.maximum;
        return minimum is () || maximum is () || minimum <= maximum;
    }
    if fieldSchema is EnumFieldSchema {
        return isValidSelection(fieldSchema.'enum, fieldSchema.default);
    }
    if fieldSchema is TitledEnumFieldSchema {
        return isValidSelection(fieldSchema.oneOf.map(option => option.'const), fieldSchema.default);
    }
    if fieldSchema is MultiSelectEnumFieldSchema {
        return isValidRange(fieldSchema.minItems, fieldSchema.maxItems) &&
                isValidSelection(fieldSchema.items.'enum, ...fieldSchema.default ?: []);
    }
    if fieldSchema is TitledMultiSelectEnumFieldSchema {
        return isValidRange(fieldSchema.minItems, fieldSchema.maxItems) &&
                isValidSelection(fieldSchema.items.anyOf.map(option => option.'const), ...fieldSchema.default ?: []);
    }
    return true;
}

isolated function isValidRange(int? minimum, int? maximum) returns boolean =>
    (minimum ?: 0) >= 0 && (maximum ?: 0) >= 0 && (minimum is () || maximum is () || minimum <= maximum);

isolated function isValidSelection(string[] options, string?... selected) returns boolean {
    foreach string? selectedValue in selected {
        if selectedValue is string && options.indexOf(selectedValue) is () {
            return false;
        }
    }
    return options.length() > 0;
}
