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

// A session ID puts the client on the legacy path without a handshake.
isolated function legacyMockClient(string scenario) returns StreamableHttpClient2|ClientError {
    StreamableHttpClient2 legacyClient = check new (mockUrl(scenario), sessionId = "legacy-session");
    _ = check legacyClient->connect();
    return legacyClient;
}

@test:Config {}
function testLegacyTransportSurfacesHttpFailures() returns error? {
    StreamableHttpClient2 errorStatus = check legacyMockClient("legacyErrorStatus");
    var errorStatusResult = errorStatus->listTools();
    test:assertTrue(errorStatusResult is ClientError);
    if errorStatusResult is ClientError {
        test:assertTrue(errorStatusResult.message().includes("Server returned error status 503"));
    }

    // 202 Accepted carries no body, so there is no result to extract.
    StreamableHttpClient2 accepted = check legacyMockClient("legacyAccepted");
    var acceptedResult = accepted->listTools();
    test:assertTrue(acceptedResult is MalformedResponseError);

    StreamableHttpClient2 textResponse = check legacyMockClient("legacyTextResponse");
    var textResult = textResponse->listTools();
    test:assertTrue(textResult is ServerResponseError);
    if textResult is ServerResponseError {
        test:assertTrue(textResult.message().includes("unsupported content type"));
    }

    StreamableHttpClient2 badJson = check legacyMockClient("legacyBadJson");
    var badJsonResult = badJson->listTools();
    test:assertTrue(badJsonResult is ServerResponseError);
    if badJsonResult is ServerResponseError {
        test:assertTrue(badJsonResult.message().includes("Unable to parse JSON response"));
    }
}

@test:Config {}
function testLegacyTransportReportsUnreachableServers() returns error? {
    // Port 1 is never bound, so every operation fails at the socket level.
    StreamableHttpClient2 deadClient = check new ("http://localhost:1/mcp", sessionId = "legacy-session");
    _ = check deadClient->connect();

    var listResult = deadClient->listTools();
    test:assertTrue(listResult is ClientError);
    if listResult is ClientError {
        test:assertTrue(listResult.message().includes("Failed to send message to server"));
    }

    ClientError? closeError = deadClient->close();
    test:assertTrue(closeError is ClientError);
    if closeError is ClientError {
        test:assertTrue(closeError.message().includes("Failed to terminate session"));
    }
}

@test:Config {}
function testLegacyClientRejectsUnexpectedResultTypes() returns error? {
    StreamableHttpClient2 wrongList = check legacyMockClient("legacyWrongResult");
    var listResult = wrongList->listTools();
    test:assertTrue(listResult is ListToolsError);
    if listResult is ListToolsError {
        test:assertTrue(listResult.message().includes("unexpected result type"));
    }

    var callResult = wrongList->callTool({name: "echo"});
    test:assertTrue(callResult is ToolCallError);
    if callResult is ToolCallError {
        test:assertTrue(callResult.message().includes("unexpected result type"));
    }
}

@test:Config {}
function testLegacyClientReadsResultsFromSseResponses() returns error? {
    StreamableHttpClient2 sseClient = check legacyMockClient("legacySseResult");
    ToolPage toolList = check sseClient->listTools();
    test:assertEquals(toolList.tools, []);
}

@test:Config {}
function testLegacyHandshakeValidatesTheInitializeResult() returns error? {
    StreamableHttpClient2 badInit = check new (mockUrl("legacyBadInit"), protocolMode = "legacy");
    var badInitResult = badInit->initializeLegacy();
    test:assertTrue(badInitResult is ClientInitializationError);
    if badInitResult is ClientInitializationError {
        test:assertTrue(badInitResult.message().includes("unexpected response type"));
    }

    StreamableHttpClient2 badVersion = check new (mockUrl("legacyBadVersion"), protocolMode = "legacy");
    var badVersionResult = badVersion->initializeLegacy();
    test:assertTrue(badVersionResult is ProtocolVersionError);
    if badVersionResult is ProtocolVersionError {
        test:assertTrue(badVersionResult.message().includes("is not supported"));
    }

    StreamableHttpClient2 goodHandshake = check new (mockUrl("legacyOk"), protocolMode = "legacy");
    ConnectionInfo connection = check goodHandshake->initializeLegacy();
    test:assertEquals(connection.protocolVersion, LATEST_LEGACY_PROTOCOL_VERSION);
    test:assertEquals(connection.serverInfo?.name, "mock");
}

@test:Config {}
function testLegacySseResponseSurfacesTransformationErrors() returns error? {
    StreamableHttpClient2 malformedStream = check legacyMockClient("sseMalformedStream");
    var malformedResult = malformedStream->listTools();
    test:assertTrue(malformedResult is TypeConversionError);

    StreamableHttpClient2 missingData = check legacyMockClient("sseMissingData");
    // An event without data is not dispatched, so the stream ends without a result.
    var missingDataResult = missingData->listTools();
    test:assertTrue(missingDataResult is InvalidMessageTypeError);
}

@test:Config {}
function testAdditionalHeadersOverrideGeneratedTransportHeaders() returns error? {
    StreamableHttpClient2 legacyClient = check legacyMockClient("ok");
    // Casing differs from the generated header, exercising the case-insensitive replacement.
    ToolPage toolList = check legacyClient->listTools({"Accept": CONTENT_TYPE_JSON});
    test:assertEquals(toolList.tools.length(), 1);
}

@test:Config {}
function testCloseResetsTheClientWhenSessionTerminationFails() returns error? {
    StreamableHttpAdvancedService sessionService = @StreamableHttpServiceConfig {
        info: {name: "closing-session", version: "1"},
        sessionMode: STATEFUL
    } isolated service object {
        remote isolated function onListTools() returns ToolPage => {tools: []};

        remote isolated function onCallTool(CallToolParams callParams) returns ToolResult => {content: []};
    };
    StreamableHttpListener sessionListener = check new (3225);
    check sessionListener.attach(sessionService, "/mcp");
    check sessionListener.'start();
    StreamableHttpClient2 sessionClient = check new ("http://localhost:3225/mcp", protocolMode = "legacy");
    _ = check sessionClient->connect();

    // With the server gone, the session DELETE fails at the network level.
    check sessionListener.immediateStop();
    ClientError? closeResult = sessionClient->close();
    test:assertTrue(closeResult is ClientError);
    ToolPage|ClientError listResult = sessionClient->listTools();
    if listResult !is ClientError {
        test:assertFail("expected the client to be disconnected");
    }
    test:assertEquals(listResult.message(), "Client is not connected; call connect() first");
    // A second close does not retry the DELETE, so the local session was dropped.
    ClientError? secondClose = sessionClient->close();
    test:assertEquals(secondClose, ());
}
