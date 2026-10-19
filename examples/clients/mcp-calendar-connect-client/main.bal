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
import ballerina/io;
import ballerina/jwt;
import ballerina/mcp;

configurable int port = 9093;
# Secret of the demo's HS256 access tokens, shared with the calendar server.
configurable string tokenSecret = ?;

const TOKEN_ISSUER = "https://login.example.com";

final string serverUrl = string `http://localhost:${port}`;
// Stand-ins for tokens an authorization server would issue to each user.
final string aliceToken = check userToken("alice");
final string malloryToken = check userToken("mallory");
// Stands in for the user's browser.
final http:Client browser = check new (serverUrl);

isolated int urlPrompts = 0;

public function main() returns error? {
    mcp:StreamableHttpClient calendar = check new (serverUrl + "/mcp",
        auth = {token: aliceToken},
        elicitationHandler = handleElicitation
    );
    _ = check calendar->connect({name: "Calendar demo client", version: "1.0.0"});
    // callTool answers each elicitation through the handler and continues until the tool completes.
    mcp:CallToolResult result = check calendar->callTool({name: "listEvents"});
    io:println("Events: ", result.content);
    check calendar->close();
}

// Plays Alice. A real client shows the URL, asks for consent and opens it in a browser.
isolated function handleElicitation(mcp:InputRequest request) returns mcp:InputResponse|mcp:ClientError {
    mcp:FormElicitationParams|mcp:UrlElicitationParams params = request.params;
    if params is mcp:FormElicitationParams {
        return {action: "decline"};
    }
    io:println(params.message, ": ", params.url);
    int prompt;
    lock {
        urlPrompts += 1;
        prompt = urlPrompts;
    }
    if prompt == 1 {
        // Mallory got hold of the link, but the page only completes it for Alice.
        io:println("Mallory opens the link: ", openLink(params.url, malloryToken));
        io:println("Alice accepts without opening the link yet");
    } else {
        io:println("Alice opens the link: ", openLink(params.url, aliceToken));
    }
    // Accepting tells the server the user agreed to open the URL, not that the step is done.
    return {action: "accept"};
}

isolated function openLink(string url, string token) returns string {
    if !url.startsWith(serverUrl) {
        return "Not a link to the calendar server";
    }
    http:Response|error page = browser->get(url.substring(serverUrl.length()), {Authorization: "Bearer " + token});
    if page is error {
        return page.message();
    }
    string|error body = page.getTextPayload();
    return string `${page.statusCode} ${body is string ? body : ""}`;
}

isolated function userToken(string subject) returns string|error {
    return jwt:issue({
        issuer: TOKEN_ISSUER,
        username: subject,
        audience: serverUrl + "/mcp",
        signatureConfig: {algorithm: jwt:HS256, config: tokenSecret}
    });
}
