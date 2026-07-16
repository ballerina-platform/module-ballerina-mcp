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

import ballerina/io;
import ballerina/log;
import ballerina/mcp;

// The page fetched through the MCP server's `fetch` tool.
const string TARGET_URL = "https://ballerina.io";

public function main() returns error? {
    log:printInfo("Starting MCP Stdio Client Demo");

    // Launch the `mcp-server-fetch` reference server as a subprocess (requires uvx).
    // This mirrors the common `mcpServers` JSON configuration:
    //   { "mcpServers": { "fetch": { "command": "uvx", "args": ["mcp-server-fetch"] } } }
    mcp:StdioClient mcpClient = check new (command = "uvx", args = ["mcp-server-fetch"]);

    // Initialize the client with client information.
    check mcpClient->initialize({
        name: "MCP Stdio Client Demo",
        version: "1.0.0"
    });
    log:printInfo("MCP connection initialized over stdio");

    // List all available tools from the fetch server.
    mcp:ListToolsResult toolsResult = check mcpClient->listTools();
    foreach mcp:ToolDefinition tool in toolsResult.tools {
        log:printInfo("Available tool", name = tool.name);
    }

    // Fetch a web page through the server's `fetch` tool.
    mcp:CallToolResult fetchResult = check mcpClient->callTool({
        name: "fetch",
        arguments: {"url": TARGET_URL, "max_length": 1000}
    });
    foreach mcp:ContentBlock contentBlock in fetchResult.content {
        if contentBlock is mcp:TextContent {
            io:println(contentBlock.text);
        }
    }

    // Terminate the server subprocess.
    check mcpClient->close();
    log:printInfo("MCP server subprocess terminated");
}
