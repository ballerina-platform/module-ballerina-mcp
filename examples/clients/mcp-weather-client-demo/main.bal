// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
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

final mcp:StreamableHttpClient mcpClient = check new ("http://localhost:9090/mcp");

public function main() returns mcp:ClientError? {
    log:printInfo("Starting MCP Weather Client Demo");

    // Initialize the client with client information
    check mcpClient->initialize({
        name: "MCP Weather Client Demo",
        version: "1.0.0"
    });

    // List all available tools from the weather server
    check listTools();

    // Demonstrate current weather functionality
    check demonstrateCurrentWeather();

    // Demonstrate weather forecast functionality
    check demonstrateWeatherForecast();

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

function demonstrateCurrentWeather() returns mcp:ClientError? {
    log:printInfo("=== Demonstrating Current Weather Tool ===");

    // Test with different cities
    string[] cities = ["London", "New York", "Tokyo", "Sydney"];

    foreach string city in cities {
        mcp:CallToolResult result = check mcpClient->callTool({
            name: "getCurrentWeather",
            arguments: {
                "city": city
            }
        });

        io:println(string `Current Weather for ${city}:`);
        io:println(result.toString());
        io:println("---");
    }
}

function demonstrateWeatherForecast() returns mcp:ClientError? {
    log:printInfo("=== Demonstrating Weather Forecast Tool ===");

    // Test with different forecast periods
    record {string location; int days;}[] testCases = [
        {location: "London", days: 3},
        {location: "Paris", days: 5},
        {location: "Berlin", days: 7}
    ];

    foreach var testCase in testCases {
        mcp:CallToolResult result = check mcpClient->callTool({
            name: "getWeatherForecast",
            arguments: {
                "location": testCase.location,
                "days": testCase.days
            }
        });

        io:println(string `${testCase.days}-Day Forecast for ${testCase.location}:`);
        io:println(result.toString());
        io:println("---");
    }

    // Test edge cases
    io:println("Testing edge cases:");

    // Minimum forecast days
    mcp:CallToolResult minResult = check mcpClient->callTool({
        name: "getWeatherForecast",
        arguments: {
            "location": "Amsterdam",
            "days": 1
        }
    });

    io:println("1-Day Forecast for Amsterdam:");
    io:println(minResult.toString());
    io:println("---");

    // Maximum forecast days
    mcp:CallToolResult maxResult = check mcpClient->callTool({
        name: "getWeatherForecast",
        arguments: {
            "location": "Rome",
            "days": 7
        }
    });

    io:println("7-Day Forecast for Rome:");
    io:println(maxResult.toString());
    io:println("---");
}
