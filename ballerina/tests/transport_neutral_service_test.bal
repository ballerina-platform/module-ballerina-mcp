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

listener Listener transportNeutralListener = check new (3273);

final http:Client transportNeutralClient = check new ("http://localhost:3273");

@ServiceConfig {
    info: {name: "transport-neutral", version: "1.0.0"}
}
service AdvancedService /neutral on transportNeutralListener {
    remote isolated function onListTools() returns ListToolsResult|ServerError => {
        tools: [{name: "echo", inputSchema: {'type: "object"}}]
    };

    remote isolated function onCallTool(CallToolParams params, Session? session = ())
            returns CallToolResult|ServerError => {
        content: [{'type: "text", text: session is Session ? "with session" : "without session"}]
    };
}

isolated function modernMeta() returns map<json> => {
    "_meta": {
        [PROTOCOL_META_KEY]: LATEST_MODERN_PROTOCOL_VERSION,
        [CAPABILITIES_META_KEY]: {}
    }
};

@test:Config {}
function testAutoClientFallsBackToLegacyOnTransportNeutralService() returns error? {
    StreamableHttpClient2 autoClient = check new ("http://localhost:3273/neutral");
    ConnectionInfo connection = check autoClient->connect();
    test:assertEquals(connection.protocolVersion, LATEST_LEGACY_PROTOCOL_VERSION);
    ToolPage page = check autoClient->listTools();
    test:assertEquals(page.tools.map(toolInfo => toolInfo.name), ["echo"]);
    ToolResult result = check autoClient->callTool({name: "echo"});
    test:assertEquals(result.content, [{'type: "text", text: "with session"}]);
    check autoClient->close();
}

@test:Config {}
function testTransportNeutralServiceAnswersModernRequestsAsLegacy() returns error? {
    map<string> modernHeaders = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: LATEST_MODERN_PROTOCOL_VERSION,
        [METHOD_HEADER]: "server/discover"
    };
    json discoverRequest = {jsonrpc: JSONRPC_VERSION, id: 1, method: "server/discover", params: modernMeta()};
    http:Response modernResponse = check transportNeutralClient->post("/neutral", discoverRequest,
            headers = modernHeaders);
    test:assertEquals(modernResponse.statusCode, 400);
    test:assertEquals(check modernResponse.getJsonPayload(), {
        jsonrpc: JSONRPC_VERSION,
        id: (),
        'error: {code: INVALID_REQUEST, message: "Unsupported MCP-Protocol-Version header: 2026-07-28"}
    });

    json notification = {jsonrpc: JSONRPC_VERSION, method: NOTIFICATION_INITIALIZED};
    http:Response notificationResponse = check transportNeutralClient->post("/neutral", notification,
            headers = modernHeaders);
    test:assertEquals(notificationResponse.statusCode, 400);

    map<string> legacyHeaders = {...modernHeaders, [PROTOCOL_VERSION_HEADER]: LATEST_LEGACY_PROTOCOL_VERSION};
    http:Response legacyResponse = check transportNeutralClient->post("/neutral", discoverRequest,
            headers = legacyHeaders);
    test:assertEquals(legacyResponse.statusCode, 200);
    json legacyBody = check legacyResponse.getJsonPayload();
    test:assertEquals(legacyBody.'error, {code: METHOD_NOT_FOUND, message: "Method not found"});
}
