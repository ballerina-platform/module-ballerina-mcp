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

const CHALLENGING_SERVER_URL = "http://localhost:3218/challenge";

// The challenge names an HTTP metadata document, so authorization fails before any token request.
isolated function challengeResponse() returns http:Response {
    http:Response challenge = new;
    challenge.statusCode = http:STATUS_UNAUTHORIZED;
    challenge.setHeader(WWW_AUTHENTICATE_HEADER,
        "Bearer resource_metadata=\"http://localhost:3218/.well-known/oauth-protected-resource\"");
    return challenge;
}

service /challenge on new http:Listener(3218) {
    resource function post .() returns http:Response => challengeResponse();

    resource function get .() returns http:Response => challengeResponse();
}

function assertAuthorizationFailure(any|error result) {
    if result !is AuthorizationError {
        test:assertFail(string `Expected an AuthorizationError, found: ${result is error ? result.message() : "a value"}`);
    }
    test:assertTrue(result.message().includes("Last error: 'http://localhost:3218' does not use HTTPS"), result.message());
}

@test:Config {}
function testModernRequestsSurfaceAuthorizationError() returns error? {
    StreamableHttpClient mcpClient = check new (CHALLENGING_SERVER_URL, auth = preRegisteredConfig());
    var connectResult = mcpClient->connect();
    assertAuthorizationFailure(connectResult);

    _ = check mcpClient.adoptDiscovery({supportedVersions: [MODERN_PROTOCOL_VERSION], capabilities: {}});
    var listenResult = mcpClient->listen();
    assertAuthorizationFailure(listenResult);
}

@test:Config {}
function testLegacyRequestsSurfaceAuthorizationError() returns error? {
    StreamableHttpClient mcpClient = check new (CHALLENGING_SERVER_URL, auth = preRegisteredConfig(),
        sessionId = "legacy-session");
    _ = check mcpClient->connect();
    var listResult = mcpClient->listTools();
    assertAuthorizationFailure(listResult);
    var listenResult = mcpClient->listen();
    assertAuthorizationFailure(listenResult);
}
