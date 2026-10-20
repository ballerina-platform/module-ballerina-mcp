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
import ballerina/jwt;
import ballerina/mcp;
import ballerina/test;

final http:Client browser = check new (origin);

@test:Config {}
function testToolCompletesOnlyAfterTheConnectPageRecordsTheConnection() returns error? {
    mcp:StreamableHttpClient alice = check userClient("alice");
    mcp:CallToolResult|mcp:InputRequiredResult result = check alice->callToolOnce({name: "listEvents"});
    mcp:InputRequiredResult firstAsk = check askedToConnect(result);

    // Accepting only means the user agreed to open the link, so the tool asks again.
    result = check alice->callToolOnce(continuation(firstAsk));
    mcp:InputRequiredResult secondAsk = check askedToConnect(result);
    test:assertEquals(connectUrl(secondAsk), connectUrl(firstAsk));

    http:Response page = check openConnectPage(connectUrl(secondAsk), "alice");
    test:assertEquals(page.statusCode, http:STATUS_OK);

    result = check alice->callToolOnce(continuation(secondAsk));
    if result !is mcp:CallToolResult {
        return error("Expected the tool to complete after the connection was recorded");
    }
    test:assertEquals(result.content[0],
            <mcp:TextContent>{'type: "text", text: "[\"09:30 Standup\",\"14:00 Design review\"]"});
    check alice->close();
}

@test:Config {}
function testConnectPageRejectsAnotherUser() returns error? {
    mcp:StreamableHttpClient carol = check userClient("carol");
    mcp:CallToolResult|mcp:InputRequiredResult result = check carol->callToolOnce({name: "listEvents"});
    mcp:InputRequiredResult ask = check askedToConnect(result);

    http:Response page = check openConnectPage(connectUrl(ask), "mallory");
    test:assertEquals(page.statusCode, http:STATUS_FORBIDDEN);

    // Mallory's visit did not connect Carol's calendar.
    result = check carol->callToolOnce(continuation(ask));
    _ = check askedToConnect(result);
    check carol->close();
}

@test:Config {}
function testDecliningToConnectEndsTheCall() returns error? {
    mcp:StreamableHttpClient dave = check userClient("dave");
    mcp:CallToolResult|mcp:InputRequiredResult result = check dave->callToolOnce({name: "listEvents"});
    mcp:InputRequiredResult ask = check askedToConnect(result);

    result = check dave->callToolOnce(continuation(ask, {action: "decline"}));
    if result !is mcp:CallToolResult {
        return error("Expected the tool to stop asking after a decline");
    }
    test:assertEquals(result.isError, true);
    check dave->close();
}

isolated function userToken(string subject) returns string|error {
    return jwt:issue({
        issuer: TOKEN_ISSUER,
        username: subject,
        audience: mcpUrl,
        signatureConfig: {algorithm: jwt:HS256, config: tokenSecret}
    });
}

function userClient(string subject) returns mcp:StreamableHttpClient|error {
    mcp:StreamableHttpClient mcpClient = check new (mcpUrl,
        protocolMode = "modern",
        httpConfig = {auth: {token: check userToken(subject)}},
        // Advertises URL-mode elicitation; callToolOnce never invokes it.
        elicitationHandler = isolated function(mcp:ElicitRequest request) returns mcp:ElicitResult|mcp:ClientError =>
            error mcp:ClientError("Not called by callToolOnce")
    );
    _ = check mcpClient->connect();
    return mcpClient;
}

isolated function askedToConnect(mcp:CallToolResult|mcp:InputRequiredResult result)
        returns mcp:InputRequiredResult|error {
    if result is mcp:InputRequiredResult {
        return result;
    }
    return error("Expected the tool to ask the user to connect");
}

isolated function connectUrl(mcp:InputRequiredResult result) returns string {
    mcp:InputRequest request = (<map<mcp:InputRequest>>result.inputRequests).get("connect");
    return (<mcp:UrlElicitationParams>request.params).url;
}

isolated function continuation(mcp:InputRequiredResult result, mcp:ElicitResult answer = {action: "accept"})
        returns mcp:CallToolParams => {
    name: "listEvents",
    inputResponses: {"connect": answer},
    requestState: <string>result.requestState
};

function openConnectPage(string url, string subject) returns http:Response|error {
    if !url.startsWith(origin) {
        return error("Not a link to this server: " + url);
    }
    string token = check userToken(subject);
    return browser->get(url.substring(origin.length()), {Authorization: "Bearer " + token});
}
