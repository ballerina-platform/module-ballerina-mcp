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
import ballerina/test;

listener Listener pvServerListener = check new (3201);

@ServiceConfig {
    info: {
        name: "Protocol Version Test Server",
        version: "1.0.0"
    },
    sessionMode: STATELESS
}
service Service /mcp on pvServerListener {
    @Tool {
        description: "Echoes the provided message back to the caller."
    }
    remote function echo(string message) returns string => message;
}

final http:Client pvServerClient = check new ("http://localhost:3201");

isolated function sendToServer(json payload, map<string|string[]> extraHeaders = {}) returns http:Response|error {
    map<string|string[]> headers = {
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON
    };
    foreach var [key, value] in extraHeaders.entries() {
        headers[key] = value;
    }
    return pvServerClient->post("/mcp", payload, headers);
}

isolated function initializePayload(string protocolVersion) returns json => {
    jsonrpc: JSONRPC_VERSION,
    id: 1,
    method: REQUEST_INITIALIZE,
    params: {
        protocolVersion: protocolVersion,
        capabilities: {},
        clientInfo: {name: "test-client", version: "1.0.0"}
    }
};

final json LIST_TOOLS_PAYLOAD = {
    jsonrpc: JSONRPC_VERSION,
    id: 2,
    method: REQUEST_LIST_TOOLS,
    params: {}
};

// Negotiation: server echoes a supported requested version.
@test:Config {}
function testServerEchoesSupportedNegotiatedVersion() returns error? {
    http:Response response = check sendToServer(initializePayload("2025-06-18"));
    test:assertEquals(response.statusCode, 200);
    json body = check response.getJsonPayload();
    json result = check body.result;
    string negotiated = check result.protocolVersion.ensureType();
    test:assertEquals(negotiated, "2025-06-18");
}

// Negotiation: server falls back to its latest version for an unsupported request.
@test:Config {}
function testServerFallsBackToLatestForUnsupportedVersion() returns error? {
    http:Response response = check sendToServer(initializePayload("1.0.0"));
    test:assertEquals(response.statusCode, 200);
    json body = check response.getJsonPayload();
    json result = check body.result;
    string negotiated = check result.protocolVersion.ensureType();
    test:assertEquals(negotiated, LATEST_PROTOCOL_VERSION);
}

// Transport: initialize is exempt from header validation even if an invalid header is present.
@test:Config {}
function testServerExemptsInitializeFromProtocolVersionHeader() returns error? {
    http:Response response = check sendToServer(initializePayload("2025-11-25"),
            {[PROTOCOL_VERSION_HEADER]: "1999-01-01"});
    test:assertEquals(response.statusCode, 200, "initialize must not be subject to MCP-Protocol-Version validation");
}

// Transport: a supported MCP-Protocol-Version header is accepted on subsequent requests.
@test:Config {}
function testServerAcceptsSupportedProtocolVersionHeader() returns error? {
    http:Response response = check sendToServer(LIST_TOOLS_PAYLOAD,
            {[PROTOCOL_VERSION_HEADER]: "2025-06-18"});
    test:assertEquals(response.statusCode, 200);
}

// Transport: a missing MCP-Protocol-Version header is tolerated for backward compatibility.
@test:Config {}
function testServerAllowsMissingProtocolVersionHeader() returns error? {
    http:Response response = check sendToServer(LIST_TOOLS_PAYLOAD);
    test:assertEquals(response.statusCode, 200);
}

// Transport: an unsupported MCP-Protocol-Version header must be rejected with 400.
@test:Config {}
function testServerRejectsUnsupportedProtocolVersionHeader() returns error? {
    http:Response response = check sendToServer(LIST_TOOLS_PAYLOAD,
            {[PROTOCOL_VERSION_HEADER]: "1999-01-01"});
    test:assertEquals(response.statusCode, 400,
            "unsupported MCP-Protocol-Version header must be rejected with 400 Bad Request");
}
