## Overview

This module offers APIs for developing MCP (Model Context Protocol) clients and servers in Ballerina.

MCP is an open standard that enables seamless integration between Large Language Models (LLMs) and external data sources, tools, and services. It facilitates structured communication through JSON-RPC 2.0 over HTTP transport, allowing AI applications to access and interact with external capabilities in a standardized way. This module provides both client-side APIs for consuming MCP services and server-side APIs for exposing tools and capabilities to AI applications.

## Quickstart

To use the `mcp` module in your Ballerina application, update the `.bal` file as follows:

### MCP Server Implementation

#### Step 1: Import the module

Import the `mcp` module.

```ballerina
import ballerina/mcp;
```

#### Step 2: Initialize the MCP Listener

Create an MCP listener to expose tools to AI applications:

```ballerina
listener mcp:Listener mcpListener = check new (9090);
```

#### Step 3: Create the MCP Service

Create an MCP service using the Basic Service pattern with automatic tool discovery. Server information can be configured using the `@mcp:ServiceConfig` annotation. If not provided, default values are used:

```ballerina
@mcp:ServiceConfig {
    info: {
        name: "MCP Weather Server",
        version: "1.0.0"
    }
}
isolated service mcp:Service /mcp on mcpListener {
    
    @mcp:McpTool {
        description: "Get current weather conditions for a location"
    }
    remote function getCurrentWeather(string city) returns Weather|error {
        return {
            location: city,
            temperature: 22.5,
            condition: "Sunny"
        };
    }
    
    
    # Get weather forecast for multiple days
    #
    # + location - The location for which to retrieve the weather forecast
    # + days - Number of days to include in the forecast
    # + return - Weather forecast data for the specified location and duration, or an error if the request fails
    remote function getWeatherForecast(string location, int days) returns Weather|error {
        // Implementation logic
        return [];
    }
}
```

Constraints for defining MCP tools:

1. The function must be marked `isolated`.
2. Parameters should be a subtype of `anydata`.
3. The tool should return a subtype of `anydata|error`.
4. The `@mcp:McpTool` annotation is not required unless you want fine-grained control. If the annotation is not provided, the documentation string will be considered as the description.

#### Step 4: Advanced Service Implementation (Optional)

For more control over tool management, use the Advanced Service pattern:

```ballerina
isolated service mcp:AdvancedService /mcp on mcpListener {
    
    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {
            tools: [
                {
                    name: "getCurrentWeather",
                    description: "Get current weather conditions",
                    inputSchema: {
                        "type": "object",
                        "properties": {
                            "city": {"type": "string"},
                            "country": {"type": "string"}
                        },
                        "required": ["city"]
                    }
                }
            ]
        };
    }
    
    remote isolated function onCallTool(mcp:CallToolParams params) returns mcp:CallToolResult|mcp:ServerError {
        match params.name {
            "getCurrentWeather" => {
                return {
                    content: [
                        {
                            "type": "text",
                            "text": "Weather data here"
                        }
                    ]
                };
            }
            _ => {
                return error mcp:ServerError(string `Unknown tool: ${params.name}`);
            }
        }
    }
}
```

### MCP Client Implementation

#### Step 1: Import the module

Import the `mcp` module.

```ballerina
import ballerina/mcp;
```

#### Step 2: Initialize the MCP Client

Create an MCP client to connect to an external MCP server:

```ballerina
mcp:Client mcpClient = new ("http://localhost:3000/mcp",
    info = {
        "name": "My MCP Client",
        "version": "1.0.0"
    }
);
```

#### Step 3: Initialize Connection and Discover Tools

Initialize the connection and discover available tools:

```ballerina
public function main() returns error? {
    // Initialize connection
    check mcpClient->initialize();
    
    // List available tools
    mcp:ListToolsResult toolsResult = check mcpClient->listTools();
    foreach mcp:Tool tool in toolsResult.tools {
        io:println(string `Available tool: ${tool.name} - ${tool.description ?: ""}`);
    }
}
```

#### Step 4: Invoke Tools

Call specific tools with parameters:

```ballerina
public function main() returns error? {
    check mcpClient->initialize();
    
    // Call a specific tool
    mcp:CallToolResult result = check mcpClient->callTool({
        name: "getCurrentWeather",
        arguments: {
            "city": "London",
            "country": "UK"
        }
    });
    
    io:println("Tool result: " + result.toString());
    
    // Close connection
    check mcpClient->close();
}
```

#### Step 5: Handle Client Configuration (Optional)

Configure the client with additional capabilities:

```ballerina
mcp:Client mcpClient = new ("http://localhost:3000/mcp",
    info = {
        "name": "Advanced MCP Client",
        "version": "1.0.0"
    },
    capabilityConfig = {
        capabilities: {
            roots: {
                listChanged: true
            }
        }
    }
);
```

## Examples

The `mcp` module provides practical examples illustrating usage in various scenarios. Explore these examples in the [examples directory](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/), covering the following use cases:

1. [Weather MCP Server](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-weather-server) - Demonstrates how to implement an MCP server that exposes weather-related tools
2. [Weather Client Demo](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/clients/mcp-weather-client-demo) - Shows how to build an MCP client that discovers and invokes tools from MCP servers
