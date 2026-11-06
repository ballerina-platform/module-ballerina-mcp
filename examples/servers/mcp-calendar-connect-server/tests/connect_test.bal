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
import ballerina/mcp.v2 as mcpv2;
import ballerina/test;

final http:Client browser = check new (origin);

@test:Config {}
function testToolCompletesOnlyAfterTheConnectPageRecordsTheConnection() returns error? {
    mcpv2:StreamableHttpClient alice = check userClient("alice");
    mcpv2:CallToolResult|mcpv2:InputRequiredResult result = check alice->callToolOnce({name: "listEvents"});
    mcpv2:InputRequiredResult firstAsk = check askedToConnect(result);

    // Accepting only means the user agreed to open the link, so the tool asks again.
    result = check alice->callToolOnce(continuation(firstAsk));
    mcpv2:InputRequiredResult secondAsk = check askedToConnect(result);
    test:assertEquals(connectUrl(secondAsk), connectUrl(firstAsk));

    http:Response page = check openConnectPage(connectUrl(secondAsk), "alice");
    test:assertEquals(page.statusCode, http:STATUS_OK);

    result = check alice->callToolOnce(continuation(secondAsk));
    if result !is mcpv2:CallToolResult {
        return error("Expected the tool to complete after the connection was recorded");
    }
    test:assertEquals(result.content[0],
            <mcpv2:TextContent>{'type: "text", text: "[\"09:30 Standup\",\"14:00 Design review\"]"});
    check alice->close();
}

@test:Config {}
function testConnectPageRejectsAnotherUser() returns error? {
    mcpv2:StreamableHttpClient carol = check userClient("carol");
    mcpv2:CallToolResult|mcpv2:InputRequiredResult result = check carol->callToolOnce({name: "listEvents"});
    mcpv2:InputRequiredResult ask = check askedToConnect(result);

    http:Response page = check openConnectPage(connectUrl(ask), "mallory");
    test:assertEquals(page.statusCode, http:STATUS_FORBIDDEN);

    // Mallory's visit did not connect Carol's calendar.
    result = check carol->callToolOnce(continuation(ask));
    _ = check askedToConnect(result);
    check carol->close();
}

@test:Config {}
function testDecliningToConnectEndsTheCall() returns error? {
    mcpv2:StreamableHttpClient dave = check userClient("dave");
    mcpv2:CallToolResult|mcpv2:InputRequiredResult result = check dave->callToolOnce({name: "listEvents"});
    mcpv2:InputRequiredResult ask = check askedToConnect(result);

    result = check dave->callToolOnce(continuation(ask, {action: "decline"}));
    if result !is mcpv2:CallToolResult {
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

function userClient(string subject) returns mcpv2:StreamableHttpClient|error {
    mcpv2:StreamableHttpClient mcpClient = check new (mcpUrl,
        protocolMode = "modern",
        httpConfig = {auth: {token: check userToken(subject)}},
        // Advertises URL-mode elicitation; callToolOnce never invokes it.
        elicitationHandler = isolated function(mcpv2:ElicitRequest request) returns mcpv2:ElicitResult|mcpv2:ClientError =>
            error mcpv2:ClientError("Not called by callToolOnce")
    );
    _ = check mcpClient->connect();
    return mcpClient;
}

isolated function askedToConnect(mcpv2:CallToolResult|mcpv2:InputRequiredResult result)
        returns mcpv2:InputRequiredResult|error {
    if result is mcpv2:InputRequiredResult {
        return result;
    }
    return error("Expected the tool to ask the user to connect");
}

isolated function connectUrl(mcpv2:InputRequiredResult result) returns string {
    mcpv2:InputRequest request = (<map<mcpv2:InputRequest>>result.inputRequests).get("connect");
    return (<mcpv2:UrlElicitationParams>request.params).url;
}

isolated function continuation(mcpv2:InputRequiredResult result, mcpv2:ElicitResult answer = {action: "accept"})
        returns mcpv2:CallToolParams => {
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
