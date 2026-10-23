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

// The approved differences between 1.4.0 and 1.5.0 on the legacy wire.

listener StreamableHttpListener legacyWireListener = check new (3275);

final http:Client legacyWireClient = check new ("http://localhost:3275");

type WireInfo record {|
    string a;
    int b;
|};

@StreamableHttpServiceConfig {
    info: {name: "legacy-wire", version: "1.0.0"},
    options: {instructions: "Call greet first."},
    sessionMode: STATELESS
}
service StreamableHttpService /wire on legacyWireListener {
    @Tool {description: "Greets", schema: {'type: "object", properties: {name: {'type: "string"}}}}
    remote isolated function greet(string name) returns string => "hi " + name;

    @Tool {description: "Returns nothing", schema: {'type: "object"}}
    remote isolated function nothing() {
    }

    @Tool {description: "Returns a record", schema: {'type: "object"}}
    remote isolated function info() returns WireInfo => {a: "x", b: 1};

    @Tool {description: "Returns xml", schema: {'type: "object"}}
    remote isolated function markup() returns xml => xml `<a>b</a>`;
}

@StreamableHttpServiceConfig {
    info: {name: "legacy-wire-cors", version: "1.0.0"},
    httpConfig: {cors: {allowOrigins: ["https://trusted.example"]}},
    sessionMode: STATELESS
}
service StreamableHttpService /wireCors on legacyWireListener {
    @Tool {description: "Greets", schema: {'type: "object"}}
    remote isolated function greet() returns string => "hi";
}

isolated function wirePost(string path, json body, map<string> extraHeaders = {}) returns http:Response|error {
    map<string> requestHeaders = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: LATEST_LEGACY_PROTOCOL_VERSION
    };
    foreach var [name, value] in extraHeaders.entries() {
        requestHeaders[name] = value;
    }
    return legacyWireClient->post(path, body, headers = requestHeaders);
}

isolated function wireCall(string tool, json arguments = {}, json extraParams = {}) returns json|error {
    map<json> params = {name: tool, arguments};
    if extraParams is map<json> {
        foreach var [key, value] in extraParams.entries() {
            params[key] = value;
        }
    }
    http:Response response = check wirePost("/wire", {jsonrpc: JSONRPC_VERSION, id: 1, method: "tools/call", params});
    test:assertEquals(response.statusCode, 200);
    return response.getJsonPayload();
}

@test:Config {}
function testLegacyOriginDefaultsToLoopback() returns error? {
    json listRequest = {jsonrpc: JSONRPC_VERSION, id: 1, method: "tools/list"};
    foreach string origin in ["http://localhost", "http://localhost:6274", "https://127.0.0.1:8443", "http://[::1]:3000"] {
        http:Response allowed = check wirePost("/wire", listRequest, {"origin": origin});
        test:assertEquals(allowed.statusCode, 200, origin);
    }
    foreach string origin in ["https://evil.example", "http://localhost.evil.example", "file://localhost"] {
        http:Response rejected = check wirePost("/wire", listRequest, {"origin": origin});
        check assertJsonRpcError(rejected, 403, INVALID_REQUEST, "Origin is not allowed");
        json rejectedBody = check rejected.getJsonPayload();
        test:assertEquals(rejectedBody.id, ());
    }
    http:Response withoutOrigin = check wirePost("/wire", listRequest);
    test:assertEquals(withoutOrigin.statusCode, 200);
}

@test:Config {}
function testLegacyOriginFollowsConfiguredAllowList() returns error? {
    json listRequest = {jsonrpc: JSONRPC_VERSION, id: 1, method: "tools/list"};
    http:Response listed = check wirePost("/wireCors", listRequest, {"origin": "https://trusted.example"});
    test:assertEquals(listed.statusCode, 200);
    // Configuring an allow list replaces the loopback default.
    http:Response loopback = check wirePost("/wireCors", listRequest, {"origin": "http://localhost:3000"});
    check assertJsonRpcError(loopback, 403, INVALID_REQUEST, "Origin is not allowed");
}

@test:Config {}
function testLegacyCallIgnoresTask() returns error? {
    json body = check wireCall("greet", {name: "x"}, {task: {ttl: 1000}});
    test:assertEquals(body.result, {content: [{'type: "text", text: "hi x"}]});
}

@test:Config {}
function testClientStripsTaskFromReadOnlyParams() {
    CallToolParams & readonly params = {name: "greet", arguments: {"name": "x"}, task: {ttl: 1000}};
    test:assertEquals(withoutTask(params), {name: "greet", arguments: {"name": "x"}});
}

@test:Config {}
function testLegacyResultsAreJsonText() returns error? {
    json nothing = check wireCall("nothing");
    test:assertEquals(nothing.result, {content: []});
    json info = check wireCall("info");
    test:assertEquals(info.result, {content: [{'type: "text", text: {a: "x", b: 1}.toJsonString()}]});
    json markup = check wireCall("markup");
    test:assertEquals(markup.result, {content: [{'type: "text", text: "\"<a>b</a>\""}]});
}

@test:Config {}
function testLegacyRejectsWronglyTypedParams() returns error? {
    http:Response cursor = check wirePost("/wire",
            {jsonrpc: JSONRPC_VERSION, id: 1, method: "tools/list", params: {cursor: 5}});
    check assertJsonRpcError(cursor, 200, INVALID_PARAMS, "Invalid cursor");
    json requestState = check wireCall("greet", {name: "x"}, {requestState: 5});
    test:assertEquals(requestState.'error.code, INVALID_PARAMS);
    json inputResponses = check wireCall("greet", {name: "x"}, {inputResponses: "none"});
    test:assertEquals(inputResponses.'error.code, INVALID_PARAMS);
}

@test:Config {}
function testLegacyInitializeCarriesInstructions() returns error? {
    foreach string version in LEGACY_PROTOCOL_VERSIONS {
        http:Response response = check wirePost("/wire", {
            jsonrpc: JSONRPC_VERSION,
            id: 1,
            method: REQUEST_INITIALIZE,
            params: {protocolVersion: version, capabilities: {}, clientInfo: {name: "t", version: "1"}}
        });
        json body = check response.getJsonPayload();
        test:assertEquals(body.result.instructions, "Call greet first.", version);
    }
}

@test:Config {}
function testLegacyDeleteWithModernHeaderIsNotAllowed() returns error? {
    http:Response response = check legacyWireClient->delete("/wire", headers = {
        [PROTOCOL_VERSION_HEADER]: LATEST_MODERN_PROTOCOL_VERSION
    });
    test:assertEquals(response.statusCode, 405);
}

@test:Config {}
function testUnknownVersionHeaderGetsTheLegacyAnswer() returns error? {
    map<string> unknownVersion = {[PROTOCOL_VERSION_HEADER]: "1999-01-01"};
    http:Response request = check wirePost("/wire", {
        jsonrpc: JSONRPC_VERSION,
        id: 7,
        method: "tools/list",
        params: {_meta: {[PROTOCOL_META_KEY]: "1999-01-01", [CAPABILITIES_META_KEY]: {}}}
    }, unknownVersion);
    test:assertEquals(request.statusCode, 400);
    test:assertEquals(check request.getJsonPayload(), {
        jsonrpc: JSONRPC_VERSION,
        id: (),
        'error: {code: INVALID_REQUEST, message: "Unsupported MCP-Protocol-Version header: 1999-01-01"}
    });

    http:Response notification = check wirePost("/wire",
            {jsonrpc: JSONRPC_VERSION, method: NOTIFICATION_INITIALIZED}, unknownVersion);
    test:assertEquals(notification.statusCode, 400);
    test:assertEquals(check notification.getJsonPayload(), {
        jsonrpc: JSONRPC_VERSION,
        id: (),
        'error: {code: INVALID_REQUEST, message: "Unsupported MCP-Protocol-Version header: 1999-01-01"}
    });
}

@test:Config {}
function testModernMetaKeyWithLegacyHeaderStaysLegacy() returns error? {
    http:Response response = check wirePost("/wire", {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        method: "tools/list",
        params: {_meta: {[PROTOCOL_META_KEY]: LATEST_MODERN_PROTOCOL_VERSION, [CAPABILITIES_META_KEY]: {}}}
    });
    json body = check response.getJsonPayload();
    map<json> result = check body.result.ensureType();
    test:assertFalse(result.hasKey("resultType"));
}
