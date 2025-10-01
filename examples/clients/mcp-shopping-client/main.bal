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

public function main() returns mcp:ClientError? {
    log:printInfo("=== MCP Shopping Cart Demo - Two Sessions ===");
    log:printInfo("This demo shows how different clients maintain separate shopping sessions");

    // Run two separate client sessions in parallel to demonstrate session isolation
    check demonstrateTwoSessions();

    log:printInfo("=== Demo Completed: Both sessions maintained separate carts ===");
}

function demonstrateTwoSessions() returns mcp:ClientError? {
    log:printInfo("\n--- Starting Two Independent Shopping Sessions in Parallel ---");

    // Run both sessions in parallel using workers
    worker AliceWorker returns mcp:ClientError? {
        return runClientSession("Alice", [
            {name: "Laptop", price: 999.99},
            {name: "Mouse", price: 25.50}
        ]);
    }

    worker BobWorker returns mcp:ClientError? {
        return runClientSession("Bob", [
            {name: "Keyboard", price: 75.00},
            {name: "Monitor", price: 299.99},
            {name: "Headphones", price: 150.00}
        ]);
    }

    // Wait for both workers to complete
    mcp:ClientError? aliceResult = wait AliceWorker;
    mcp:ClientError? bobResult = wait BobWorker;

    // Check results
    if aliceResult is mcp:ClientError {
        log:printError(string `Alice's session failed: ${aliceResult.message()}`);
    }
    if bobResult is mcp:ClientError {
        log:printError(string `Bob's session failed: ${bobResult.message()}`);
    }

    log:printInfo("\n--- Both parallel sessions completed ---");
}

function runClientSession(string customerName, record {|string name; decimal price;|}[] items) returns mcp:ClientError? {
    log:printInfo(string `\n=== ${customerName}'s Shopping Session ===`);

    // Create a new client (each client gets its own session)
    mcp:StreamableHttpClient mcpClient = check new ("http://localhost:9092/mcp");

    // Initialize client
    check mcpClient->initialize({
        name: string `${customerName}'s Shopping Client`,
        version: "1.0.0"
    });

    log:printInfo(string `${customerName}: Client initialized`);

    // Add items to cart
    foreach var item in items {
        mcp:CallToolResult result = check mcpClient->callTool({
            name: "addToCart",
            arguments: {
                "productName": item.name,
                "price": item.price
            }
        });
        string response = getTextContent(result);
        log:printInfo(string `${customerName}: ${response}`);
    }

    // View cart
    mcp:CallToolResult cartResult = check mcpClient->callTool({
        name: "viewCart",
        arguments: {}
    });

    if cartResult.content.length() > 0 && cartResult.content[0] is mcp:TextContent {
        mcp:TextContent textContent = <mcp:TextContent>cartResult.content[0];
        io:println(string `${customerName}'s Cart: ${textContent.text}`);
    }

    // Close client
    check mcpClient->close();
    log:printInfo(string `${customerName}: Session closed`);

    return;
}

function getTextContent(mcp:CallToolResult result) returns string {
    if result.content.length() > 0 && result.content[0] is mcp:TextContent {
        mcp:TextContent textContent = <mcp:TextContent>result.content[0];
        return textContent.text;
    }
    return "No text content available";
}
