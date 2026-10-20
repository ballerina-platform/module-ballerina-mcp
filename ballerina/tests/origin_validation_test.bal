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

const TRUSTED_ORIGIN = "https://trusted.example";
const UNTRUSTED_ORIGIN = "https://untrusted.example";

isolated function legacyOriginPost(http:Client httpClient, string servicePath, string? origin,
        string? token = ()) returns http:Response|error {
    map<string|string[]> requestHeaders = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`
    };
    if origin is string {
        requestHeaders["origin"] = origin;
    }
    if token is string {
        requestHeaders[AUTHORIZATION_HEADER] = "Bearer " + token;
    }
    json initializeRequest = {
        "jsonrpc": JSONRPC_VERSION,
        "id": 1,
        "method": REQUEST_INITIALIZE,
        "params": {
            "protocolVersion": LATEST_LEGACY_PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": {"name": "origin-test", "version": "1"}
        }
    };
    return httpClient->post(servicePath, initializeRequest, headers = requestHeaders);
}

isolated function modernOriginPost(http:Client httpClient, string servicePath, string? origin,
        string? token = ()) returns http:Response|error {
    map<string|string[]> requestHeaders = {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: LATEST_PROTOCOL_VERSION,
        [METHOD_HEADER]: "server/discover"
    };
    if origin is string {
        requestHeaders["origin"] = origin;
    }
    if token is string {
        requestHeaders[AUTHORIZATION_HEADER] = "Bearer " + token;
    }
    JsonRpcRequest discoverRequest = {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        method: "server/discover",
        params: {_meta: {[PROTOCOL_META_KEY]: LATEST_PROTOCOL_VERSION, [CAPABILITIES_META_KEY]: {}}}
    };
    return httpClient->post(servicePath, discoverRequest, headers = requestHeaders);
}

@test:Config {}
function testLegacyRequestsAreCheckedAgainstTheOriginAllowList() returns error? {
    http:Response rejected = check legacyOriginPost(dispatcherErrorClient, "/corsGuarded", UNTRUSTED_ORIGIN);
    check assertJsonRpcError(rejected, 403, INVALID_REQUEST, "Origin is not allowed");

    http:Response allowed = check legacyOriginPost(dispatcherErrorClient, "/corsGuarded", TRUSTED_ORIGIN);
    test:assertEquals(allowed.statusCode, 200);

    // Clients other than browsers send no Origin.
    http:Response withoutOrigin = check legacyOriginPost(dispatcherErrorClient, "/corsGuarded", ());
    test:assertEquals(withoutOrigin.statusCode, 200);
    http:Response modernWithoutOrigin = check modernOriginPost(dispatcherErrorClient, "/corsGuarded", ());
    test:assertEquals(modernWithoutOrigin.statusCode, 200);
}

@StreamableHttpServiceConfig {
    info: {name: "protected-origin-guarded", version: "1"},
    httpConfig: {
        cors: {allowOrigins: [TRUSTED_ORIGIN]},
        auth: {
            'resource: "http://localhost:3235/originGuarded",
            authorizationServers: [
                {issuer: PROTECTED_ISSUER, validator: {jwtValidatorConfig: {signatureConfig: {secret: SIGNING_KEY}}}}
            ]
        }
    }
}
service StreamableHttpService /originGuarded on serverAuthListener {
    @Tool {description: "Returns pong", schema: {'type: "object"}}
    remote isolated function ping() returns string => "pong";
}

@test:Config {}
function testOriginIsCheckedBeforeAuthentication() returns error? {
    // A cross-origin request is refused for its origin, whether or not it carries a token.
    http:Response modernRejected = check modernOriginPost(serverAuthClient, "/originGuarded", UNTRUSTED_ORIGIN);
    check assertJsonRpcError(modernRejected, 403, INVALID_REQUEST, "Origin is not allowed");
    test:assertFalse(modernRejected.hasHeader(WWW_AUTHENTICATE_HEADER));

    http:Response legacyRejected = check legacyOriginPost(serverAuthClient, "/originGuarded", UNTRUSTED_ORIGIN);
    check assertJsonRpcError(legacyRejected, 403, INVALID_REQUEST, "Origin is not allowed");
    test:assertFalse(legacyRejected.hasHeader(WWW_AUTHENTICATE_HEADER));

    http:Response legacyDeleteRejected = check serverAuthClient->delete("/originGuarded", headers = {
        "origin": UNTRUSTED_ORIGIN,
        [PROTOCOL_VERSION_HEADER]: LATEST_LEGACY_PROTOCOL_VERSION,
        [SESSION_ID_HEADER]: "unknown"
    });
    test:assertEquals(legacyDeleteRejected.statusCode, 403);

    // A request without an Origin passes the check and reaches authentication.
    http:Response modernUnauthenticated = check modernOriginPost(serverAuthClient, "/originGuarded", ());
    test:assertEquals(modernUnauthenticated.statusCode, 401);
    http:Response legacyUnauthenticated = check legacyOriginPost(serverAuthClient, "/originGuarded", ());
    test:assertEquals(legacyUnauthenticated.statusCode, 401);

    string token = check serverAuthToken(audience = "http://localhost:3235/originGuarded");
    http:Response modernAllowed = check modernOriginPost(serverAuthClient, "/originGuarded", TRUSTED_ORIGIN, token);
    test:assertEquals(modernAllowed.statusCode, 200);
    http:Response legacyAllowed = check legacyOriginPost(serverAuthClient, "/originGuarded", (), token);
    test:assertEquals(legacyAllowed.statusCode, 200);
}
