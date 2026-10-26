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

import ballerina/test;

// Callers may pass read-only values; `clone()` returns those as they are, so the client must copy before mutating.

@test:Config {}
function testCallToolCopiesReadOnlyParams() returns error? {
    StreamableHttpClient modernClient = check new ("http://localhost:3205/mcp",
        elicitationHandler = confirmTestElicitation);
    _ = check modernClient->connect();
    CallToolParams & readonly params = {name: "ask"};
    CallToolResult callResult = check modernClient->callTool(params);
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "accept:true:echo-only-state"});
    check modernClient->close();
}

@test:Config {before: stubCacheOAuthNetwork, after: restoreCacheOAuthNetwork}
function testAuthorizedRequestCopiesReadOnlyHeaders() returns error? {
    StreamableHttpClient oauthClient = check connectedOAuthCacheClient("readOnlyHeaders");
    map<string|string[]> & readonly headers = {"x-trace": "1"};
    _ = check oauthClient->listTools(headers);
}

@test:Config {}
function testCapabilitiesCopyReadOnlyInput() {
    ClientCapabilities & readonly capabilities = {extensions: {"x-ext": {}}};
    ClientCapabilities withExtension = withOAuthExtensionCapability(capabilities, "io.example/oauth");
    test:assertEquals(withExtension.extensions, {"x-ext": {}, "io.example/oauth": {}});
    ClientCapabilities withElicitation = withElicitationCapability(capabilities);
    test:assertEquals(withElicitation.elicitation, {form: {}, url: {}});
}

@test:Config {}
function testUrlAnswerCopiesReadOnlyResult() {
    ElicitRequest request = {params: {mode: "url", message: "Open", url: "https://example.com"}};
    ElicitResult & readonly answer = {action: "accept", content: {"leaked": "x"}};
    test:assertEquals(withSubmittedContentOnly(request, answer), {action: "accept"});
}
