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

const REDIRECTING_SERVER_URL = "http://localhost:3263/moved";

// Redirects every request to the modern test server, which needs no authorization.
service /moved on new http:Listener(3263) {
    resource function post .() returns http:TemporaryRedirect =>
        {headers: {"Location": "http://localhost:3205/mcp"}};
}

@test:Config {}
function testRedirectsFollowedByDefault() returns error? {
    StreamableHttpClient2 mcpClient = check new (REDIRECTING_SERVER_URL, protocolMode = "modern");
    ConnectionInfo info = check mcpClient->connect();
    test:assertEquals(info.protocolVersion, LATEST_MODERN_PROTOCOL_VERSION);
}

@test:Config {}
function testRedirectsNotFollowedWhenDisabled() returns error? {
    StreamableHttpClient2 mcpClient = check new (REDIRECTING_SERVER_URL, protocolMode = "modern",
        httpConfig = {followRedirects: {enabled: false}});
    ConnectionInfo|ClientError result = mcpClient->connect();
    test:assertTrue(result is ClientError);
}

@test:Config {}
function testRedirectsNotFollowedWithOAuth() returns error? {
    StreamableHttpClient2 mcpClient = check new (REDIRECTING_SERVER_URL, protocolMode = "modern",
        httpConfig = {auth: preRegisteredConfig()});
    ConnectionInfo|ClientError result = mcpClient->connect();
    test:assertTrue(result is ClientError);
}

@test:Config {}
function testOAuthRejectsEnabledRedirects() {
    StreamableHttpClient2|ClientError result = new ("https://mcp.example.com/mcp",
        httpConfig = {auth: preRegisteredConfig(), followRedirects: {enabled: true}});
    if result !is ClientInitializationError {
        test:assertFail("Expected a ClientInitializationError for redirects with OAuth");
    }
}

@test:Config {}
function testOAuthAcceptsDisabledRedirects() returns error? {
    StreamableHttpClient2 _ = check new ("https://mcp.example.com/mcp",
        httpConfig = {auth: preRegisteredConfig(), followRedirects: {enabled: false}});
}
