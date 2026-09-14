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
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/mcp;
import ballerina/test;

listener mcp:StreamableHttpListener structuredListener = check new (8789);

type Person record {|
    string name;
    int age;
|};

@mcp:StreamableHttpServiceConfig {info: {name: "structured-http", version: "1.0.0"}}
service mcp:StreamableHttpService /structuredHttp on structuredListener {
    remote isolated function stringValue() returns string => "hello";

    remote isolated function arrayValue() returns int[] => [1, 2, 3];

    remote isolated function personValue() returns Person => {name: "Alice", age: 30};

    remote isolated function nullableValue() returns string? => ();

    @mcp:Tool {structuredOutput: false}
    remote isolated function textOnlyValue() returns string => "text only";
}

@mcp:ServiceConfig {info: {name: "structured-generic", version: "1.0.0"}}
service mcp:Service /structuredGeneric on structuredListener {
    remote isolated function booleanValue() returns boolean => true;
}

@test:Config {}
function testCompilerGeneratedSchemasAndRawStructuredValues() returns error? {
    mcp:StreamableHttpClient httpClient = check new ("http://localhost:8789/structuredHttp",
            protocolMode = "modern");
    check httpClient->initialize();
    mcp:ProtocolListToolsResult listedTools = check httpClient->listToolsWithSchemas();
    map<mcp:ProtocolToolDefinition> toolsByName = {};
    foreach mcp:ProtocolToolDefinition toolInfo in listedTools.tools {
        toolsByName[toolInfo.name] = toolInfo;
    }
    check assertSchemaType(check toolsByName["stringValue"].ensureType(), "string");
    check assertSchemaType(check toolsByName["arrayValue"].ensureType(), "array");
    check assertSchemaType(check toolsByName["personValue"].ensureType(), "object");
    mcp:ProtocolToolDefinition nullableTool = check toolsByName["nullableValue"].ensureType();
    mcp:OutputSchema nullableSchema = check nullableTool.outputSchema.ensureType();
    test:assertTrue(nullableSchema.hasKey("anyOf"));
    mcp:ProtocolToolDefinition textOnlyTool = check toolsByName["textOnlyValue"].ensureType();
    test:assertEquals(textOnlyTool.outputSchema, ());

    mcp:ProtocolCallToolResult|mcp:InputRequiredResult stringResult =
            check httpClient->callToolWithResult({name: "stringValue"});
    assertStructuredValue(stringResult, "hello");
    mcp:ProtocolCallToolResult|mcp:InputRequiredResult arrayResult =
            check httpClient->callToolWithResult({name: "arrayValue"});
    assertStructuredValue(arrayResult, <json>[1, 2, 3]);
    mcp:ProtocolCallToolResult|mcp:InputRequiredResult personResult =
            check httpClient->callToolWithResult({name: "personValue"});
    assertStructuredValue(personResult, <json>{name: "Alice", age: 30});
    mcp:ProtocolCallToolResult|mcp:InputRequiredResult nullableResult =
            check httpClient->callToolWithResult({name: "nullableValue"});
    test:assertTrue(nullableResult is mcp:ProtocolCallToolResult);
    if nullableResult is mcp:ProtocolCallToolResult {
        test:assertTrue(nullableResult.hasKey("structuredContent"));
        test:assertEquals(nullableResult["structuredContent"], ());
    }
    mcp:ProtocolCallToolResult|mcp:InputRequiredResult textOnlyResult =
            check httpClient->callToolWithResult({name: "textOnlyValue"});
    test:assertTrue(textOnlyResult is mcp:ProtocolCallToolResult);
    if textOnlyResult is mcp:ProtocolCallToolResult {
        test:assertFalse(textOnlyResult.hasKey("structuredContent"));
    }
    check httpClient->close();

    mcp:StreamableHttpClient legacyClient = check new ("http://localhost:8789/structuredHttp",
            protocolMode = "legacy");
    check legacyClient->initialize();
    mcp:ListToolsResult legacyTools = check legacyClient->listTools();
    foreach mcp:ToolDefinition toolInfo in legacyTools.tools {
        test:assertEquals(toolInfo.outputSchema, ());
    }
    mcp:CallToolResult legacyResult = check legacyClient->callTool({name: "arrayValue"});
    test:assertEquals(legacyResult.structuredContent, ());
    check legacyClient->close();

    mcp:StreamableHttpClient genericClient = check new ("http://localhost:8789/structuredGeneric",
            protocolMode = "modern");
    check genericClient->initialize();
    mcp:ProtocolCallToolResult|mcp:InputRequiredResult booleanResult =
            check genericClient->callToolWithResult({name: "booleanValue"});
    assertStructuredValue(booleanResult, true);
    check genericClient->close();
}

function assertSchemaType(mcp:ProtocolToolDefinition toolInfo, string expectedType) returns error? {
    mcp:OutputSchema outputSchema = check toolInfo.outputSchema.ensureType();
    test:assertEquals(outputSchema["type"], expectedType);
}

function assertStructuredValue(mcp:ProtocolCallToolResult|mcp:InputRequiredResult resultValue,
        json expectedValue) {
    test:assertTrue(resultValue is mcp:ProtocolCallToolResult);
    if resultValue is mcp:ProtocolCallToolResult {
        test:assertEquals(resultValue["structuredContent"], expectedValue);
    }
}
