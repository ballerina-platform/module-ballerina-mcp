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

type DeleteConfirmation record {|
    boolean confirmed;
|};

final readonly & FormSchema deleteConfirmationSchema = {
    properties: {confirmed: {'type: "boolean", description: "Delete it?"}},
    required: ["confirmed"]
};

@StreamableHttpServiceConfig {info: {name: "basic-elicitation", version: "1"}}
service StreamableHttpService /basic on new StreamableHttpListener(3250) {
    @Tool {description: "Deletes a file after confirmation", schema: {'type: "object"}}
    remote isolated function deleteFile(Context context) returns string|InputRequiredResult {
        DeleteConfirmation? confirmation = context.acceptedContent("confirm");
        if confirmation is () {
            return {inputRequests: {"confirm": elicitForm("Delete the file?", deleteConfirmationSchema)}};
        }
        return confirmation.confirmed ? "deleted" : "kept";
    }

    @Tool {description: "Describes the answer it received", schema: {'type: "object"}}
    remote isolated function inspectAnswer(Context context) returns string {
        DeleteConfirmation? confirmation = context.acceptedContent("confirm");
        ElicitResult? answer = context.elicitResult("confirm");
        return string `${confirmation is () ? "nil" : confirmation.confirmed.toString()}|${
            answer is () ? "none" : answer.action}`;
    }

    @Tool {description: "Connects an account out of band", schema: {'type: "object"}}
    remote isolated function connectAccount(Context context) returns string|InputRequiredResult {
        if context.elicitResult("connect")?.action != "accept" {
            return {
                inputRequests: {"connect": elicitUrl("Connect your account", "https://example.com/connect")},
                requestState: "account-42"
            };
        }
        return string `connected:${context.requestState() ?: "none"}`;
    }
}

const BASIC_ELICITATION_URL = "http://localhost:3250/basic";

@test:Config {}
function testBasicToolCompletesWithAcceptedContent() returns error? {
    StreamableHttpClient basicClient = check new (BASIC_ELICITATION_URL, elicitationHandler = confirmTestElicitation);
    _ = check basicClient->connect();
    CallToolResult callResult = check basicClient->callTool({name: "deleteFile"});
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "deleted"});
    check basicClient->close();
}

@test:Config {}
function testAcceptedContentOnlyReturnsAcceptedAnswersOfTheRightShape() returns error? {
    StreamableHttpClient basicClient = check new (BASIC_ELICITATION_URL);
    _ = check basicClient->connect();
    [map<InputResponse>, string][] cases = [
        [{}, "nil|none"],
        [{"other": {action: "accept", content: {confirmed: true}}}, "nil|none"],
        [{"confirm": {action: "decline"}}, "nil|decline"],
        [{"confirm": {action: "cancel"}}, "nil|cancel"],
        [{"confirm": {action: "accept"}}, "nil|accept"],
        [{"confirm": {action: "accept", content: {confirmed: "yes"}}}, "nil|accept"],
        [{"confirm": {action: "accept", content: {confirmed: true, extra: "field"}}}, "nil|accept"],
        [{"confirm": {action: "accept", content: {confirmed: false}}}, "false|accept"]
    ];
    foreach [map<InputResponse>, string] [inputResponses, expected] in cases {
        CallToolResult|InputRequiredResult callResult =
            check basicClient->callToolOnce({name: "inspectAnswer", inputResponses});
        if callResult !is CallToolResult {
            test:assertFail("Expected a completed result");
        }
        test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: expected},
            inputResponses.toString());
    }
    check basicClient->close();
}

@test:Config {}
function testBasicToolCompletesUrlElicitationWithRequestState() returns error? {
    lock {
        openedUrls.removeAll();
    }
    StreamableHttpClient basicClient = check new (BASIC_ELICITATION_URL, elicitationHandler = openTestUrl);
    _ = check basicClient->connect();
    CallToolResult callResult = check basicClient->callTool({name: "connectAccount"});
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "connected:account-42"});
    lock {
        test:assertEquals(openedUrls, ["https://example.com/connect"]);
    }
    check basicClient->close();
}

@test:Config {}
function testLegacyCallsSeeAnEmptyContext() returns error? {
    StreamableHttpClient legacyClient = check new (BASIC_ELICITATION_URL, protocolMode = "legacy");
    _ = check legacyClient->connect();
    CallToolResult|InputRequiredResult callResult = check legacyClient->callToolOnce({
        name: "inspectAnswer",
        inputResponses: {"confirm": {action: "accept", content: {confirmed: true}}},
        requestState: "ignored"
    });
    if callResult !is CallToolResult {
        test:assertFail("Expected a completed result");
    }
    test:assertEquals(callResult.content[0], <TextContent>{'type: "text", text: "nil|none"});

    CallToolResult|InputRequiredResult|ClientError inputRequired = legacyClient->callToolOnce({name: "deleteFile"});
    if inputRequired !is ClientError {
        test:assertFail("Expected the legacy input-required error");
    }
    test:assertTrue(inputRequired.message().includes("Input-required tool calls require modern MCP"),
        inputRequired.message());
    check legacyClient->close();
}
