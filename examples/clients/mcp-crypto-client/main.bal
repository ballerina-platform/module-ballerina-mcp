// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.com).
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

import ballerina/io;
import ballerina/log;
import ballerina/mcp;
import ballerina/uuid;

final mcp:StreamableHttpClient mcpClient = check new ("http://localhost:9091/mcp");

public function main() returns mcp:ClientError? {
    log:printInfo("Starting MCP Crypto Client Demo");

    // Initialize the client with client information
    check mcpClient->initialize({
        name: "MCP Crypto Client Demo",
        version: "1.0.0"
    });

    // List all available tools from the crypto server
    check listTools();

    // Demonstrate hash text functionality
    check demonstrateHashText();

    // Demonstrate Base64 encoding/decoding
    check demonstrateBase64Operations();

    // Close the connection
    check mcpClient->close();
    log:printInfo("MCP client connection closed");
}

function listTools() returns mcp:ClientError? {
    log:printInfo("=== Listing Available Tools ===");

    mcp:ListToolsResult toolsResult = check mcpClient->listTools();

    foreach mcp:ToolDefinition tool in toolsResult.tools {
        io:println(string `Tool: ${tool.name}`);
        io:println(string `Description: ${tool.description ?: "No description available"}`);
        io:println("---");
    }

    io:println(string `Total tools available: ${toolsResult.tools.length()}`);
}

function demonstrateHashText() returns mcp:ClientError? {
    log:printInfo("=== Demonstrating Hash Text Tool ===");

    // Test with different hash algorithms
    string[] algorithms = ["sha256", "md5", "sha1", "sha384", "sha512"];
    string testText = "Hello, MCP World!";

    foreach string algorithm in algorithms {
        // Generate a trace ID to track this request
        string traceId = uuid:createType1AsString();

        mcp:CallToolResult result = check mcpClient->callTool({
            name: "hashText",
            arguments: {
                "text": testText,
                "algorithm": algorithm
            },
            _meta: {
                "traceId": traceId
            }
        });

        io:println(string `${algorithm.toUpperAscii()} Hash Result:`);
        io:println(result.toString());

        if result._meta is record {} {
            io:println("\nResponse Metadata:");
            record {} meta = <record {}>result._meta;
            foreach var [key, value] in meta.entries() {
                io:println(string `  ${key}: ${value.toString()}`);
            }
        }
        io:println("---");
    }

    // Test with default algorithm (sha256)
    mcp:CallToolResult defaultResult = check mcpClient->callTool({
        name: "hashText",
        arguments: {
            "text": "Testing default algorithm"
        }
    });

    io:println("Default Algorithm Hash Result:");
    io:println(defaultResult.toString());

    if defaultResult._meta is record {} {
        io:println("\nResponse Metadata:");
        record {} meta = <record {}>defaultResult._meta;
        foreach var [key, value] in meta.entries() {
            io:println(string `  ${key}: ${value.toString()}`);
        }
    }
    io:println("---");
}

function demonstrateBase64Operations() returns mcp:ClientError? {
    log:printInfo("=== Demonstrating Base64 Operations Tool ===");

    string originalText = "Ballerina MCP is awesome!";

    // Encode to Base64
    string traceId1 = uuid:createType1AsString();
    mcp:CallToolResult encodeResult = check mcpClient->callTool({
        name: "encodeBase64",
        arguments: {
            "text": originalText,
            "operation": "encode"
        },
        _meta: {
            "traceId": traceId1
        }
    });

    io:println("Base64 Encoding:");
    io:println(encodeResult.toString());


    if encodeResult._meta is record {} {
        io:println("\nResponse Metadata:");
        record {} meta = <record {}>encodeResult._meta;
        foreach var [key, value] in meta.entries() {
            io:println(string `  ${key}: ${value.toString()}`);
        }
    }
    io:println("---");

    // Test with default operation (encode)
    mcp:CallToolResult defaultEncodeResult = check mcpClient->callTool({
        name: "encodeBase64",
        arguments: {
            "text": "Default encode operation"
        }
    });

    io:println("Default Operation (Encode):");
    io:println(defaultEncodeResult.toString());

    if defaultEncodeResult._meta is record {} {
        io:println("\nResponse Metadata:");
        record {} meta = <record {}>defaultEncodeResult._meta;
        foreach var [key, value] in meta.entries() {
            io:println(string `  ${key}: ${value.toString()}`);
        }
    }
    io:println("---");

    // For demonstration, let's decode a known Base64 string
    string base64Text = "QmFsbGVyaW5hIE1DUCBpcyBhd2Vzb21lIQ==";
    string traceId2 = uuid:createType1AsString();

    mcp:CallToolResult decodeResult = check mcpClient->callTool({
        name: "encodeBase64",
        arguments: {
            "text": base64Text,
            "operation": "decode"
        },
        _meta: {
            "traceId": traceId2
        }
    });

    io:println("\nBase64 Decoding:");
    io:println(decodeResult.toString());

    if decodeResult._meta is record {} {
        io:println("\nResponse Metadata:");
        record {} meta = <record {}>decodeResult._meta;
        foreach var [key, value] in meta.entries() {
            io:println(string `  ${key}: ${value.toString()}`);
        }
    }
    io:println("---");
}
