// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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
import ballerina/test;

const INTERNAL_DETAIL = "connection to db-7 refused";

@StreamableHttpServiceConfig {info: {name: "header-bound-tool", version: "1"}, sessionMode: STATELESS}
service StreamableHttpService /headerBoundTool on dispatcherErrorListener {
    @Tool {description: "Echoes the tenant header", schema: {'type: "object"}}
    remote isolated function tenant(@http:Header {name: "X-Tenant"} string tenant) returns string => tenant;
}

@StreamableHttpServiceConfig {info: {name: "header-bound-advanced", version: "1"}, sessionMode: STATELESS}
service StreamableHttpAdvancedService /headerBoundAdvanced on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {
        tools: [{name: "tenant", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams, @http:Header {name: "X-Tenant"} string tenant)
            returns ToolResult => {content: [{'type: "text", text: tenant}]};
}

@StreamableHttpServiceConfig {info: {name: "header-bound-listing", version: "1"}, sessionMode: STATELESS}
service StreamableHttpAdvancedService /headerBoundListing on dispatcherErrorListener {
    remote isolated function onListTools(@http:Header {name: "X-Tenant"} string tenant) returns ToolPage => {
        tools: [{name: tenant, inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
}

@StreamableHttpServiceConfig {info: {name: "opaque-failures", version: "1"}, sessionMode: STATELESS}
service StreamableHttpAdvancedService /opaqueFailures on dispatcherErrorListener {
    remote isolated function onListTools() returns ToolPage => {
        tools: [{name: "fail", inputSchema: {'type: "object"}}, {name: "explode", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams callParams) returns ToolResult|error {
        if callParams.name == "explode" {
            panic error(INTERNAL_DETAIL);
        }
        return error(INTERNAL_DETAIL);
    }
}

isolated function legacyToolPost(string servicePath, string methodName, json params = {})
        returns http:Response|error {
    json requestMessage = {"jsonrpc": JSONRPC_VERSION, "id": 300, "method": methodName, "params": params};
    return dispatcherErrorClient->post(servicePath, requestMessage, headers = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: LATEST_LEGACY_PROTOCOL_VERSION
    });
}

isolated function modernToolCall(string servicePath, string toolName) returns http:Response|error =>
    dispatcherPost(servicePath, REQUEST_CALL_TOOL, {"name": toolName}, {[NAME_HEADER]: toolName});

@test:Config {}
function testHeaderBindingFailureIsInvalidParamsOnBothProtocols() returns error? {
    foreach string servicePath in ["/headerBoundTool", "/headerBoundAdvanced"] {
        http:Response modern = check modernToolCall(servicePath, "tenant");
        check assertJsonRpcError(modern, 200, INVALID_PARAMS, "no header value found");

        http:Response legacy = check legacyToolPost(servicePath, REQUEST_CALL_TOOL, {"name": "tenant"});
        check assertJsonRpcError(legacy, 200, INVALID_PARAMS, "no header value found");
    }

    http:Response modernListing = check dispatcherPost("/headerBoundListing", REQUEST_LIST_TOOLS);
    check assertJsonRpcError(modernListing, 200, INVALID_PARAMS, "no header value found");
    http:Response legacyListing = check legacyToolPost("/headerBoundListing", REQUEST_LIST_TOOLS);
    check assertJsonRpcError(legacyListing, 200, INVALID_PARAMS, "no header value found");
}

@test:Config {}
function testAdvancedToolFailuresHideTheirDetailOnBothProtocols() returns error? {
    foreach string toolName in ["fail", "explode"] {
        http:Response modern = check modernToolCall("/opaqueFailures", toolName);
        check assertJsonRpcError(modern, 200, INTERNAL_ERROR, string `Tool '${toolName}' failed unexpectedly.`);
        test:assertFalse((check modern.getTextPayload()).includes(INTERNAL_DETAIL));

        http:Response legacy = check legacyToolPost("/opaqueFailures", REQUEST_CALL_TOOL, {"name": toolName});
        check assertJsonRpcError(legacy, 200, INTERNAL_ERROR, string `Tool '${toolName}' failed unexpectedly.`);
        test:assertFalse((check legacy.getTextPayload()).includes(INTERNAL_DETAIL));
    }

    // A ServerError is meant for the caller and keeps its message.
    http:Response serverError = check modernToolCall("/failCall", "echo");
    check assertJsonRpcError(serverError, 200, INTERNAL_ERROR, "tool execution is unavailable");
}
