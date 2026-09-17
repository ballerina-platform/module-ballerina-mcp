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

isolated function newTestMcpService() returns StreamableHttpAdvancedService =>
    @StreamableHttpConfig {info: {name: "lifecycle", version: "1"}}
    service object {
        remote isolated function onListTools() returns ListToolsResult => {
            tools: [{name: "ping", inputSchema: {'type: "object"}}]
        };

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {
            content: [{'type: "text", text: "pong"}]
        };
    };

@test:Config {}
function testListenerReportsHttpListenerInitFailure() {
    StreamableHttpListener|Error invalidListener = new (3215, {
        secureSocket: {key: {path: "/nonexistent/keystore.p12", password: "unused"}}
    });
    test:assertTrue(invalidListener is Error);
    if invalidListener is Error {
        test:assertTrue(invalidListener.message().includes("Failed to initialize HTTP listener"));
    }
}

@test:Config {}
function testListenerLifecycleOverAnExistingHttpListener() returns error? {
    http:Listener sharedHttpListener = check new (3212);
    StreamableHttpListener mcpListener = check new (sharedHttpListener);
    StreamableHttpAdvancedService mcpService = newTestMcpService();

    check mcpListener.attach(mcpService, "/lifecycle");
    check mcpListener.'start();

    http:Client lifecycleClient = check new ("http://localhost:3212");
    http:Response listResponse = check lifecycleClient->post("/lifecycle", {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        method: REQUEST_LIST_TOOLS,
        params: {_meta: {[PROTOCOL_META_KEY]: MODERN_PROTOCOL_VERSION, [CAPABILITIES_META_KEY]: {}}}
    }, headers = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: MODERN_PROTOCOL_VERSION,
        [METHOD_HEADER]: REQUEST_LIST_TOOLS
    });
    test:assertEquals(listResponse.statusCode, 200);

    // Detaching an unattached service is a no-op rather than an error.
    check mcpListener.detach(newTestMcpService());
    check mcpListener.detach(mcpService);

    check mcpListener.gracefulStop();
}

@test:Config {}
function testListenerImmediateStop() returns error? {
    StreamableHttpListener mcpListener = check new (3213);
    check mcpListener.attach(newTestMcpService(), "/immediate");
    check mcpListener.'start();
    check mcpListener.immediateStop();
}

@test:Config {}
function testModernServicesCannotRequireLegacySessions() returns error? {
    StreamableHttpAdvancedService sessionService =
        @StreamableHttpConfig {info: {name: "session-bound", version: "1"}, protocolMode: "modern"}
        service object {
            remote isolated function onListTools() returns ListToolsResult => {tools: []};

            remote isolated function onCallTool(CallToolParams callParams, HttpSession session)
                    returns CallToolResult => {content: []};
        };

    StreamableHttpListener mcpListener = check new (3214);
    Error? attachError = mcpListener.attach(sessionService, "/sessionBound");
    test:assertTrue(attachError is DispatcherError);
    if attachError is DispatcherError {
        test:assertTrue(attachError.message().includes("cannot require mcp:HttpSession"));
    }
    check mcpListener.immediateStop();
}
