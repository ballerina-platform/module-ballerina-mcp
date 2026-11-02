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

import ballerina/mcp.v2 as mcpv2;
import ballerina/test;

listener mcpv2:StreamableHttpListener structuredListener = check new (8789);

final mcpv2:ProtocolMode[] & readonly PROTOCOL_MODES = ["modern", "legacy"];

type Person record {|
    string name;
    int age;
|};

const boolean DISABLED_POLICY = false;
const boolean structuredOutput = false;
final boolean? runtimeOutputPolicy = selectRuntimeOutputPolicy();
final mcpv2:ProtocolMode runtimeLegacyMode = selectLegacyProtocolMode();

isolated function selectRuntimeOutputPolicy() returns boolean? => false;
isolated function selectLegacyProtocolMode() returns mcpv2:ProtocolMode => "legacy";

final mcpv2:McpToolConfig automaticPolicyConfig = {description: "Automatic policy"};
final mcpv2:McpToolConfig disabledPolicyConfig = {description: "Disabled policy", structuredOutput: false};

@mcpv2:StreamableHttpServiceConfig {info: {name: "structured-http", version: "1.0.0"}}
service mcpv2:StreamableHttpService /structuredHttp on structuredListener {
    @mcpv2:Tool {structuredOutput: DISABLED_POLICY}
    remote isolated function constantDisabledValue() returns int => 10;

    @mcpv2:Tool {structuredOutput}
    remote isolated function shorthandDisabledValue() returns int => 11;

    @mcpv2:Tool {structuredOutput: runtimeOutputPolicy}
    remote isolated function runtimeDisabledValue() returns int => 12;

    @mcpv2:Tool {structuredOutput: ()}
    remote isolated function nilPolicyValue() returns int => 13;

    @mcpv2:Tool {...automaticPolicyConfig}
    remote isolated function spreadAutomaticValue() returns int => 42;

    @mcpv2:Tool {...disabledPolicyConfig}
    remote isolated function spreadDisabledValue() returns int => 7;

    remote isolated function stringValue() returns string => "hello";

    remote isolated function arrayValue() returns int[] => [1, 2, 3];

    remote isolated function personValue() returns Person => {name: "Alice", age: 30};

    remote isolated function nullableValue() returns string? => ();

    @mcpv2:Tool {structuredOutput: false}
    remote isolated function textOnlyValue() returns string => "text only";

    remote isolated function noReturnValue() {
    }

    remote isolated function errorOrNilValue() returns error? {
    }

    remote isolated function escapedPersonValue() returns Person =>
        {name: string `Al "the pal" \ O'Neil` + "\nsecond line", age: 40};
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "structured-generic", version: "1.0.0"}}
service mcpv2:StreamableHttpService /structuredGeneric on structuredListener {
    remote isolated function booleanValue() returns boolean => true;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "argument-headers", version: "1.0.0"}}
service mcpv2:StreamableHttpService /argumentHeaders on structuredListener {
    remote isolated function mirrorArguments(
            @mcpv2:Argument {headerName: "Region"} string region,
            @mcpv2:Argument {headerName: "Retry-Count"} int retries,
            @mcpv2:Argument {headerName: "Enabled"} boolean enabled) returns string {
        return string `${region}:${retries}:${enabled}`;
    }
}

@test:Config {}
function testCompilerGeneratedSchemasAndRawStructuredValues() returns error? {
    mcpv2:StreamableHttpClient httpClient = check new ("http://localhost:8789/structuredHttp",
            protocolMode = "modern");
    _ = check httpClient->connect();
    mcpv2:ListToolsResult listedTools = check httpClient->listTools();
    map<mcpv2:ToolDefinition> toolsByName = {};
    foreach mcpv2:ToolDefinition toolInfo in listedTools.tools {
        toolsByName[toolInfo.name] = toolInfo;
    }
    check assertSchemaType(check toolsByName["stringValue"].ensureType(), "string");
    check assertSchemaType(check toolsByName["arrayValue"].ensureType(), "array");
    check assertSchemaType(check toolsByName["personValue"].ensureType(), "object");
    mcpv2:ToolDefinition nullableTool = check toolsByName["nullableValue"].ensureType();
    mcpv2:OutputSchema nullableSchema = check nullableTool.outputSchema.ensureType();
    test:assertTrue(nullableSchema.hasKey("anyOf"));
    mcpv2:ToolDefinition textOnlyTool = check toolsByName["textOnlyValue"].ensureType();
    test:assertEquals(textOnlyTool.outputSchema, ());

    mcpv2:CallToolResult stringResult = check httpClient->callTool({name: "stringValue"});
    assertStructuredValue(stringResult, "hello");
    mcpv2:CallToolResult arrayResult = check httpClient->callTool({name: "arrayValue"});
    assertStructuredValue(arrayResult, <json>[1, 2, 3]);
    mcpv2:CallToolResult personResult = check httpClient->callTool({name: "personValue"});
    assertStructuredValue(personResult, <json>{name: "Alice", age: 30});
    mcpv2:CallToolResult nullableResult = check httpClient->callTool({name: "nullableValue"});
    test:assertTrue(nullableResult.hasKey("structuredContent"));
    test:assertEquals(nullableResult["structuredContent"], ());
    mcpv2:CallToolResult textOnlyResult = check httpClient->callTool({name: "textOnlyValue"});
    test:assertFalse(textOnlyResult.hasKey("structuredContent"));
    check httpClient->close();

    mcpv2:StreamableHttpClient legacyClient = check new ("http://localhost:8789/structuredHttp",
            protocolMode = "legacy");
    _ = check legacyClient->connect();
    mcpv2:ListToolsResult legacyTools = check legacyClient->listTools();
    foreach mcpv2:ToolDefinition toolInfo in legacyTools.tools {
        test:assertEquals(toolInfo.outputSchema, ());
    }
    mcpv2:CallToolResult legacyResult = check legacyClient->callTool({name: "arrayValue"});
    test:assertFalse(legacyResult.hasKey("structuredContent"));
    check legacyClient->close();

    mcpv2:StreamableHttpClient genericClient = check new ("http://localhost:8789/structuredGeneric",
            protocolMode = "modern");
    _ = check genericClient->connect();
    mcpv2:CallToolResult booleanResult = check genericClient->callTool({name: "booleanValue"});
    assertStructuredValue(booleanResult, true);
    check genericClient->close();
}

@test:Config {}
function testNilOnlyReturnsAreUnstructured() returns error? {
    mcpv2:StreamableHttpClient httpClient = check new ("http://localhost:8789/structuredHttp",
            protocolMode = "modern");
    _ = check httpClient->connect();
    mcpv2:ListToolsResult listedTools = check httpClient->listTools();
    foreach mcpv2:ToolDefinition toolInfo in listedTools.tools {
        if toolInfo.name == "noReturnValue" || toolInfo.name == "errorOrNilValue" {
            test:assertEquals(toolInfo.outputSchema, (), toolInfo.name);
        }
    }

    foreach string toolName in ["noReturnValue", "errorOrNilValue"] {
        mcpv2:CallToolResult result = check httpClient->callTool({name: toolName});
        test:assertFalse(result.hasKey("structuredContent"), toolName);
        test:assertEquals(result.isError, (), toolName);
    }
    check httpClient->close();
}

@test:Config {}
function testNilResultHasNoTextContent() returns error? {
    foreach mcpv2:ProtocolMode mode in PROTOCOL_MODES {
        mcpv2:StreamableHttpClient httpClient = check new ("http://localhost:8789/structuredHttp",
                protocolMode = mode);
        _ = check httpClient->connect();
        foreach string toolName in ["nullableValue", "noReturnValue"] {
            mcpv2:CallToolResult result = check httpClient->callTool({name: toolName});
            test:assertEquals(result.content.length(), 0, string `${mode} ${toolName}`);
        }
        check httpClient->close();
    }
}

@test:Config {}
function testStructuredTextContentIsJson() returns error? {
    json expected = {name: string `Al "the pal" \ O'Neil` + "\nsecond line", age: 40};
    foreach mcpv2:ProtocolMode mode in PROTOCOL_MODES {
        mcpv2:StreamableHttpClient httpClient = check new ("http://localhost:8789/structuredHttp",
                protocolMode = mode);
        _ = check httpClient->connect();
        mcpv2:CallToolResult result = check httpClient->callTool({name: "escapedPersonValue"});
        test:assertEquals(result.content.length(), 1);
        mcpv2:TextContent textContent = check result.content[0].ensureType();
        test:assertEquals(check textContent.text.fromJsonString(), expected, mode);
        if mode == "modern" {
            assertStructuredValue(result, expected);
        }
        check httpClient->close();
    }
}

@test:Config {}
function testMcpArgumentHeadersFromGeneratedSchema() returns error? {
    mcpv2:StreamableHttpClient argumentClient = check new ("http://localhost:8789/argumentHeaders",
            protocolMode = "modern");
    _ = check argumentClient->connect();
    mcpv2:ListToolsResult listedTools = check argumentClient->listTools();
    mcpv2:ToolDefinition mirrorTool = check listedTools.tools[0].ensureType();
    map<json> properties = check mirrorTool.inputSchema.properties.ensureType();
    map<json> expectedHeaders = {
        "region": "Region",
        "retries": "Retry-Count",
        "enabled": "Enabled"
    };
    foreach string parameterName in expectedHeaders.keys() {
        map<json> propertySchema = check properties[parameterName].cloneWithType();
        test:assertEquals(propertySchema["x-mcp-header"], expectedHeaders[parameterName]);
    }

    mcpv2:CallToolResult result = check argumentClient->callTool({
        name: "mirrorArguments",
        arguments: {
            "region": "世界",
            "retries": 3,
            "enabled": true
        }
    });
    test:assertEquals(result.isError, ());
    check argumentClient->close();
}

function assertSchemaType(mcpv2:ToolDefinition toolInfo, string expectedType) returns error? {
    mcpv2:OutputSchema outputSchema = check toolInfo.outputSchema.ensureType();
    test:assertEquals(outputSchema["type"], expectedType);
}

function assertStructuredValue(mcpv2:CallToolResult resultValue, json expectedValue) {
    test:assertEquals(resultValue["structuredContent"], expectedValue);
}

@test:Config {}
function testStructuredOutputPolicySurvivesConfigurationSpreads() returns error? {
    mcpv2:StreamableHttpClient policyClient = check new ("http://localhost:8789/structuredHttp",
        protocolMode = "modern");
    _ = check policyClient->connect();
    error? verificationError = trap assertSpreadPolicyResults(policyClient);
    check policyClient->close();
    return verificationError;
}

function assertSpreadPolicyResults(mcpv2:StreamableHttpClient policyClient) returns error? {
    mcpv2:ListToolsResult toolList = check policyClient->listTools();
    int matchedTools = 0;
    foreach mcpv2:ToolDefinition toolInfo in toolList.tools {
        if toolInfo.name == "spreadAutomaticValue" {
            test:assertEquals(toolInfo.description, "Automatic policy");
            test:assertTrue(toolInfo.outputSchema is mcpv2:OutputSchema);
            matchedTools += 1;
        } else if toolInfo.name == "spreadDisabledValue" {
            test:assertEquals(toolInfo.description, "Disabled policy");
            test:assertEquals(toolInfo.outputSchema, ());
            matchedTools += 1;
        }
    }
    test:assertEquals(matchedTools, 2);
    mcpv2:CallToolResult automaticResult = check policyClient->callTool({name: "spreadAutomaticValue"});
    test:assertEquals(automaticResult["structuredContent"], 42);
    mcpv2:CallToolResult disabledResult = check policyClient->callTool({name: "spreadDisabledValue"});
    test:assertFalse(disabledResult.hasKey("structuredContent"));
}

@mcpv2:StreamableHttpServiceConfig {
    info: {name: "runtime-legacy", version: "1"}, protocolMode: runtimeLegacyMode
}
service mcpv2:StreamableHttpService /policyLegacy on structuredListener {
    @mcpv2:Tool {structuredOutput: true}
    remote isolated function anyValue() returns any => 42;
}

@test:Config {}
function testStructuredOutputPolicyAcrossFieldForms() returns error? {
    mcpv2:StreamableHttpClient policyClient = check new (serverUrl = "http://localhost:8789/structuredHttp",
        protocolMode = "modern");
    _ = check policyClient->connect();
    error? verificationError = trap assertFieldPolicyResults(policyClient);
    check policyClient->close();
    return verificationError;
}

function assertFieldPolicyResults(mcpv2:StreamableHttpClient policyClient) returns error? {
    mcpv2:ListToolsResult toolList = check policyClient->listTools();
    int disabledTools = 0;
    foreach mcpv2:ToolDefinition toolInfo in toolList.tools {
        if toolInfo.name == "constantDisabledValue" || toolInfo.name == "shorthandDisabledValue" ||
                toolInfo.name == "runtimeDisabledValue" {
            disabledTools += 1;
            test:assertEquals(actual = toolInfo.outputSchema, expected = ());
            mcpv2:CallToolResult disabledResult = check policyClient->callTool(params = {name: toolInfo.name});
            test:assertFalse(condition = disabledResult.hasKey("structuredContent"));
        }
    }
    test:assertEquals(actual = disabledTools, expected = 3);
    mcpv2:CallToolResult automaticResult = check policyClient->callTool(params = {name: "nilPolicyValue"});
    test:assertEquals(actual = automaticResult["structuredContent"], expected = 13);
}

@test:Config {}
function testRuntimeLegacyModeIgnoresUnusedRequiredOutput() returns error? {
    mcpv2:StreamableHttpClient policyClient = check new (serverUrl = "http://localhost:8789/policyLegacy",
        protocolMode = "legacy");
    _ = check policyClient->connect();
    mcpv2:CallToolResult legacyResult = check policyClient->callTool(params = {name: "anyValue"});
    test:assertFalse(condition = legacyResult.hasKey("structuredContent"));
    check policyClient->close();
}


final mcpv2:OutputSchema? optionalPolicySchema = selectOptionalPolicySchema();
final mcpv2:McpToolConfig optionalSchemaConfig = {structuredOutput: true, outputSchema: optionalPolicySchema};

function selectOptionalPolicySchema() returns mcpv2:OutputSchema? => ();

service mcpv2:StreamableHttpService /optionalPolicy on structuredListener {
    @mcpv2:Tool {structuredOutput: true, outputSchema: optionalPolicySchema}
    remote isolated function inlineValue() returns int => 21;

    @mcpv2:Tool {...optionalSchemaConfig}
    remote isolated function spreadValue() returns int => 21;
}

@test:Config {}
function testOptionalOutputSchemaFallsBackToGeneratedSchema() returns error? {
    mcpv2:StreamableHttpClient policyClient = check new (serverUrl = "http://localhost:8789/optionalPolicy",
        protocolMode = "modern");
    _ = check policyClient->connect();
    foreach string toolName in ["inlineValue", "spreadValue"] {
        mcpv2:CallToolResult toolResult = check policyClient->callTool(params = {name: toolName});
        test:assertEquals(actual = toolResult["structuredContent"], expected = 21);
    }
    check policyClient->close();
}
