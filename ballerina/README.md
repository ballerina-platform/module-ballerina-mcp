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

Create an MCP service using the Basic Service pattern with automatic tool discovery. Server information and session management can be configured using the `@mcp:ServiceConfig` annotation. If not provided, default values are used:

```ballerina
@mcp:ServiceConfig {
    info: {
        name: "MCP Weather Server",
        version: "1.0.0"
    },
    // Optional: Configure session management mode
    sessionMode: mcp:AUTO  // STATEFUL, STATELESS, or AUTO (default)
}
service mcp:Service /mcp on mcpListener {

    @mcp:Tool {
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
    remote function getWeatherForecast(string location, int days) returns WeatherForecast|error {
        // Implementation logic
        return {
            location: location,
            forecast: []
        };
    }
}
```

**Session Management Modes:**

MCP services support three session management modes:

- **`STATEFUL`**: Sessions are managed by the transport. Clients must initialize and maintain session IDs. Use this for services that need to track client state.
- **`STATELESS`**: No session management. Each request is independent. Ideal for simple, stateless services.
- **`AUTO`** (default): Automatically determined based on client initialization behavior. Recommended for most use cases.

**Stateless Example:**
```ballerina
@mcp:ServiceConfig {
    info: {
        name: "Calculator Service",
        version: "1.0.0"
    },
    sessionMode: mcp:STATELESS
}
service mcp:Service /mcp on mcpListener {
    @mcp:Tool
    remote function add(int a, int b) returns int {
        return a + b;
    }
}
```

**Advanced Configuration Example:**
```ballerina
@mcp:ServiceConfig {
    info: {
        name: "Advanced MCP Server",
        version: "1.0.0"
    },
    sessionMode: mcp:STATEFUL,
    // Optional HTTP configuration
    httpConfig: {
        cors: {
            allowOrigins: ["http://localhost:3000"],
            allowCredentials: true
        }
    },
    options: {
        instructions: "This server provides advanced mathematical operations with session support."
    }
}
service mcp:Service /mcp on mcpListener {
    // Service implementation...
}
```

**Constraints for defining MCP tools:**

1. Parameters should be a subtype of `anydata` (exception: first parameter can be `mcp:Session` for stateful services).
2. The tool should return a subtype of `anydata|error`.
3. The `@mcp:Tool` annotation is not required unless you want fine-grained control. If the annotation is not provided, the documentation string will be considered as the description.
4. For session-enabled tools, the `mcp:Session` parameter must be the first parameter if present.

#### Step 4: Advanced Service Implementation (Optional)

For more control over tool management, use the Advanced Service pattern:

```ballerina
service mcp:AdvancedService /mcp on mcpListener {
    
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
                            'type: "text",
                            text: "Weather data here"
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
final mcp:StreamableHttpClient mcpClient = check new ("http://localhost:3000/mcp");
```

#### Step 3: Initialize Connection and Discover Tools

Initialize the connection with client information and discover available tools:

```ballerina
public function main() returns error? {
    // Initialize the client with implementation info
    check mcpClient->initialize({
        name: "My MCP Client",
        version: "1.0.0"
    });

    // List available tools
    mcp:ListToolsResult toolsResult = check mcpClient->listTools();
    foreach mcp:ToolDefinition tool in toolsResult.tools {
        io:println(string `Available tool: ${tool.name} - ${tool.description ?: ""}`);
    }
}
```

#### Step 4: Invoke Tools

Call specific tools with parameters and optional custom headers:

```ballerina
public function main() returns error? {
    // Call a specific tool with optional custom headers
    mcp:CallToolResult result = check mcpClient->callTool({
        name: "getCurrentWeather",
        arguments: {
            city: "London",
            country: "UK"
        }
    }, {
        "X-Request-ID": "req-12345",
        "Authorization": "Bearer token123"
    });

    io:println("Tool result: " + result.toString());

    // Close connection
    check mcpClient->close();
}
```

#### Step 5: Handle Client Configuration (Optional)

Configure the client with additional capabilities and custom headers:

```ballerina
// Create client with custom configuration
mcp:StreamableHttpClientTransportConfig config = {
    timeout: 30,
    followRedirects: {enabled: true}
};
final mcp:StreamableHttpClient mcpClient = check new ("http://localhost:3000/mcp", config);

public function main() returns error? {
    // Initialize with client info, capabilities, and optional custom headers
    check mcpClient->initialize(
        {
            name: "Advanced MCP Client",
            version: "1.0.0"
        },
        {
            roots: {
                listChanged: true
            }
        },
        {
            "X-Custom-Header": "custom-value"
        }
    );
}
```

## Examples

The `mcp` module provides practical examples illustrating usage in various scenarios. Explore these examples in the [examples directory](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/), covering the following use cases:

### Server Examples
1. [Weather MCP Server](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-weather-server) - Demonstrates the Basic Service pattern with AUTO session mode for weather-related tools
2. [Crypto MCP Server](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-crypto-server) - Shows the Advanced Service pattern with STATELESS session mode for cryptographic operations
3. [Shopping Cart Server](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-shopping-server) - Demonstrates STATEFUL session mode with persistent shopping cart functionality across session interactions

### Client Examples
1. [Weather Client Demo](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/clients/mcp-weather-client-demo) - Shows how to build an MCP client that discovers and invokes weather tools
2. [Crypto Client Demo](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/clients/mcp-crypto-client-demo) - Demonstrates client interaction with cryptographic MCP services
3. [Shopping Client Demo](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/clients/mcp-shopping-client-demo) - Shows session-based client usage with parallel session execution for stateful services
