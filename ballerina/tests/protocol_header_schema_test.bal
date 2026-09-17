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

isolated function assertSchemaRejected(InputSchema toolSchema, record {} toolArguments, string expectedMessage) {
    map<string>|Error headerValues = toolParameterHeaders(toolSchema, toolArguments);
    test:assertTrue(headerValues is Error, string `expected '${expectedMessage}' to be rejected`);
    if headerValues is Error {
        test:assertTrue(headerValues.message().includes(expectedMessage),
                string `unexpected message '${headerValues.message()}'`);
    }
}

@test:Config {}
function testMirroredHeadersAreEncodedByType() returns error? {
    InputSchema toolSchema = {
        'type: "object",
        properties: {
            region: {"type": "string", "x-mcp-header": "Region"},
            count: {"type": "integer", "x-mcp-header": "Count"},
            ratio: {"type": "number", "x-mcp-header": "Ratio"},
            debug: {"type": "boolean", "x-mcp-header": "Debug"}
        }
    };
    map<string> headerValues = check toolParameterHeaders(toolSchema,
            {"region": "north", "count": 7, "ratio": 1.5, "debug": true});
    test:assertEquals(headerValues.length(), 4);
    test:assertEquals(check decodeProtocolHeader(headerValues.get("mcp-param-region")), "north");
    test:assertEquals(check decodeProtocolHeader(headerValues.get("mcp-param-count")), "7");
    test:assertEquals(check decodeProtocolHeader(headerValues.get("mcp-param-ratio")), "1.5");
    test:assertEquals(check decodeProtocolHeader(headerValues.get("mcp-param-debug")), "true");

    // Declared but unsupplied arguments simply do not produce a header.
    map<string> declaredOnly = check toolParameterHeaders(toolSchema, {});
    test:assertEquals(declaredOnly.length(), 0);
}

@test:Config {}
function testMirroredHeaderRejectsInvalidArgumentValues() {
    InputSchema countSchema = {
        'type: "object",
        properties: {count: {"type": "integer", "x-mcp-header": "Count"}}
    };
    assertSchemaRejected(countSchema, {"count": "seven"}, "Invalid argument for mirrored header");
    // Integers beyond the JSON-safe range cannot round-trip through a header.
    assertSchemaRejected(countSchema, {"count": 9007199254740992}, "Invalid argument for mirrored header");

    assertSchemaRejected({
        'type: "object",
        properties: {debug: {"type": "boolean", "x-mcp-header": "Debug"}}
    }, {"debug": "yes"}, "Invalid argument for mirrored header");
}

@test:Config {}
function testMirroredHeaderRejectsUnusableAnnotations() {
    // A header name must be a valid HTTP token.
    assertSchemaRejected({
        'type: "object",
        properties: {region: {"type": "string", "x-mcp-header": "bad header"}}
    }, {}, "Invalid or unreachable x-mcp-header annotation");

    // The annotation is only meaningful on a reachable property schema.
    assertSchemaRejected({'type: "object", "x-mcp-header": "Region"}, {},
            "Invalid or unreachable x-mcp-header annotation");
    assertSchemaRejected({
        'type: "object",
        "$defs": {shared: {"type": "string", "x-mcp-header": "Region"}}
    }, {}, "Invalid or unreachable x-mcp-header annotation");
    assertSchemaRejected({
        'type: "object",
        "properties": {wrapper: {"type": "array", "items": {"type": "string", "x-mcp-header": "Region"}}}
    }, {}, "Invalid or unreachable x-mcp-header annotation");
    assertSchemaRejected({
        'type: "object",
        "properties": {wrapper: {"type": "array", "prefixItems": [{"type": "string", "x-mcp-header": "Region"}]}}
    }, {}, "Invalid or unreachable x-mcp-header annotation");

    // Only scalar JSON types can be mirrored onto a header.
    assertSchemaRejected({
        'type: "object",
        properties: {payload: {"type": "object", "x-mcp-header": "Payload"}}
    }, {}, "x-mcp-header requires string, integer, number or boolean type");
}

@test:Config {}
function testMirroredHeaderTraversalIsBounded() {
    json nestedSchema = {"type": "string"};
    foreach int _ in 0 ..< 70 {
        nestedSchema = {"type": "array", "items": nestedSchema};
    }
    assertSchemaRejected({'type: "object", properties: {deep: nestedSchema}}, {},
            "Tool schema exceeds traversal limits");
}

@test:Config {}
function testNestedSchemaKeywordsAreTraversedWithoutMirroring() returns error? {
    InputSchema toolSchema = {
        'type: "object",
        properties: {
            region: {"type": "string", "x-mcp-header": "Region"},
            choice: {"anyOf": [{"type": "string"}, {"type": "integer"}]},
            listing: {"type": "array", "items": {"type": "string"}}
        },
        "patternProperties": {"^x-": {"type": "string"}},
        "$defs": {shared: {"type": "string"}}
    };
    map<string> headerValues = check toolParameterHeaders(toolSchema, {"region": "north"});
    test:assertEquals(headerValues.length(), 1);
}
