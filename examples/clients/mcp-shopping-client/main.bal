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
import ballerina/mcp.v2 as mcpv2;

public function main() returns mcpv2:ClientError? {
    log:printInfo("=== MCP Shopping Cart Demo - Two Sessions ===");
    log:printInfo("This demo shows how different clients maintain separate shopping sessions");

    // Run two separate client sessions in parallel to demonstrate session isolation
    check demonstrateTwoSessions();

    log:printInfo("=== Demo Completed: Both sessions maintained separate carts ===");
}

function demonstrateTwoSessions() returns mcpv2:ClientError? {
    log:printInfo("\n--- Starting Two Independent Shopping Sessions in Parallel ---");

    // Run both sessions in parallel using workers
    worker AliceWorker returns mcpv2:ClientError? {
        return runClientSession("Alice", [
            {name: "Laptop", price: 999.99},
            {name: "Mouse", price: 25.50}
        ]);
    }

    worker BobWorker returns mcpv2:ClientError? {
        return runClientSession("Bob", [
            {name: "Keyboard", price: 75.00},
            {name: "Monitor", price: 299.99},
            {name: "Headphones", price: 150.00}
        ]);
    }

    // Wait for both workers to complete
    mcpv2:ClientError? aliceResult = wait AliceWorker;
    mcpv2:ClientError? bobResult = wait BobWorker;

    // Check results
    if aliceResult is mcpv2:ClientError {
        log:printError(string `Alice's session failed: ${aliceResult.message()}`);
    }
    if bobResult is mcpv2:ClientError {
        log:printError(string `Bob's session failed: ${bobResult.message()}`);
    }

    log:printInfo("\n--- Both parallel sessions completed ---");
}

function runClientSession(string customerName, record {|string name; decimal price;|}[] items) returns mcpv2:ClientError? {
    log:printInfo(string `\n=== ${customerName}'s Shopping Session ===`);

    // Create a new client (each client gets its own session)
    mcpv2:StreamableHttpClientConfig config = {
        httpConfig: {
            auth: {
                username: "ballerina",
                issuer: "wso2",
                audience: ["ballerina", "ballerina.org", "ballerina.io"],
                keyId: "5a0b754-895f-4279-8843-b745e11a57e9",
                jwtId: "JlbmMiOiJBMTI4Q0JDLUhTMjU2In",
                expTime: 3600,
                signatureConfig: {
                    config: {
                        keyFile: "./resource/private.key"
                    }
                }
            }
        }
    };
    mcpv2:StreamableHttpClient mcpClient = check new ("http://localhost:9092/mcp", config);

    // Initialize client
    _ = check mcpClient->connect({
        name: string `${customerName}'s Shopping Client`,
        version: "1.0.0"
    });

    log:printInfo(string `${customerName}: Client initialized`);

    // Add items to cart
    foreach var item in items {
        mcpv2:CallToolResult result = check mcpClient->callTool({
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
    mcpv2:CallToolResult cartResult = check mcpClient->callTool({
        name: "viewCart",
        arguments: {}
    });

    if cartResult.content.length() > 0 && cartResult.content[0] is mcpv2:TextContent {
        mcpv2:TextContent textContent = <mcpv2:TextContent>cartResult.content[0];
        io:println(string `${customerName}'s Cart: ${textContent.text}`);
    }

    // Close client
    check mcpClient->close();
    log:printInfo(string `${customerName}: Session closed`);

    return;
}

function getTextContent(mcpv2:CallToolResult result) returns string {
    if result.content.length() > 0 && result.content[0] is mcpv2:TextContent {
        mcpv2:TextContent textContent = <mcpv2:TextContent>result.content[0];
        return textContent.text;
    }
    return "No text content available";
}
