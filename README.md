# Ballerina MCP Library

[![Build](https://github.com/ballerina-platform/module-ballerina-mcp/workflows/CI/badge.svg)](https://github.com/ballerina-platform/module-ballerina-mcp/actions?query=workflow%3ACI)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ballerina-platform/module-ballerina-mcp.svg)](https://github.com/ballerina-platform/module-ballerina-mcp/commits/main)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Overview

This module provides APIs for building MCP (Model Context Protocol) clients and servers in Ballerina, enabling standardized integration between LLMs and external data sources, tools, and services via JSON-RPC 2.0 over HTTP. It supports automatic tool discovery, type-safe schema generation, flexible session management, and streamable HTTP transport with Server-Sent Events for bidirectional communication.

## Quickstart

To use the `mcp` module in your Ballerina application, update the `.bal` file as follows:

### MCP Server Implementation

#### Step 1: Import the module

Import the `mcp` module.

```ballerina
import ballerina/mcp;
```

#### Step 2: Initialize the MCP Listener

Create a Streamable HTTP listener to expose tools to AI applications:

```ballerina
listener mcp:StreamableHttpListener mcpListener = check new (9090);
```

> **Note:** The `mcp:Listener` class is deprecated. Use `mcp:StreamableHttpListener` instead.

#### Step 3: Create the MCP Service

Create an MCP service using the Basic Service pattern with automatic tool discovery. Server information and session management can be configured using the `@mcp:StreamableHttpServiceConfig` annotation. If not provided, default values are used:

```ballerina
@mcp:StreamableHttpServiceConfig {
    info: {
        name: "MCP Weather Server",
        version: "1.0.0"
    },
    // Optional: Configure session management mode
    sessionMode: mcp:AUTO  // STATEFUL, STATELESS, or AUTO (default)
}
service mcp:StreamableHttpService /mcp on mcpListener {

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

> **Note:** The `httpConfig` and `sessionMode` fields of the `@mcp:ServiceConfig` annotation are deprecated. Use the corresponding fields of the `@mcp:StreamableHttpServiceConfig` annotation instead.

> **Note:** The transport-agnostic `mcp:Service` and `mcp:AdvancedService` types are still supported and are not deprecated. Prefer `mcp:StreamableHttpService` and `mcp:StreamableHttpAdvancedService`, since only these can access HTTP request information.

**Session Management Modes:**

MCP services support three session management modes:

- **`STATEFUL`**: Sessions are managed by the transport. Clients must initialize and maintain session IDs. Use this for services that need to track client state.
- **`STATELESS`**: No session management. Each request is independent. Ideal for simple, stateless services.
- **`AUTO`** (default): Automatically determined based on client initialization behavior. Recommended for most use cases.

**Stateless Example:**
```ballerina
@mcp:StreamableHttpServiceConfig {
    info: {
        name: "Calculator Service",
        version: "1.0.0"
    },
    sessionMode: mcp:STATELESS
}
service mcp:StreamableHttpService /mcp on mcpListener {
    @mcp:Tool
    remote function add(int a, int b) returns int {
        return a + b;
    }
}
```

**Advanced Configuration Example:**
```ballerina
@mcp:StreamableHttpServiceConfig {
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
service mcp:StreamableHttpService /mcp on mcpListener {
    // Service implementation...
}
```

**Constraints for defining MCP tools:**

1. Parameters should be a subtype of `anydata` (exception: first parameter can be `mcp:Session` for stateful services).
2. The tool should return a subtype of `anydata|error`.
3. The `@mcp:Tool` annotation is not required unless you want fine-grained control. If the annotation is not provided, the documentation string will be considered as the description.
4. For session-enabled tools, the `mcp:Session` parameter must be the first parameter if present.
5. Tools in an `mcp:StreamableHttpService` can additionally bind HTTP request information, such as `@http:Header` parameters, an `http:Headers` parameter, or an `http:Request` parameter. These require importing the `ballerina/http` module, and `@http:Header` parameters are excluded from the generated tool input schema.

#### Step 4: Advanced Service Implementation (Optional)

For more control over tool management, use the Advanced Service pattern:

```ballerina
service mcp:StreamableHttpAdvancedService /mcp on mcpListener {
    
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

**Constraints for defining an `mcp:StreamableHttpAdvancedService`:**

1. Both the `onListTools` and the `onCallTool` `remote` methods must be declared, and no other `remote` methods are allowed.
2. `onCallTool` must accept exactly one `mcp:CallToolParams` parameter, and may accept an `mcp:Session?` parameter for stateful services.
3. As with the tools of an `mcp:StreamableHttpService`, both methods can additionally bind HTTP request information, such as `@http:Header` parameters, an `http:Headers` parameter, or an `http:Request` parameter.

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

## Issues and projects

Issues and Projects tabs are disabled for this repository as this is part of the Ballerina Library. To report bugs, request new features, start new discussions, view project boards, etc., go to the [Ballerina Library parent repository](https://github.com/ballerina-platform/ballerina-standard-library).
This repository only contains the source code for the module.

## Build from the source

### Prerequisites

1. Download and install Java SE Development Kit (JDK) version 21 (from one of the following locations).

   - [Oracle](https://www.oracle.com/java/technologies/downloads/)
   - [OpenJDK](https://adoptium.net/)

     > **Note:** Set the JAVA_HOME environment variable to the path name of the directory into which you installed JDK.

2. Generate a GitHub access token with read package permissions, then set the following `env` variables:

   ```shell
   export packageUser=<Your GitHub Username>
   export packagePAT=<GitHub Personal Access Token>
   ```

### Build options

Execute the commands below to build from the source.

1. To build the package:

   ```bash
   ./gradlew clean build
   ```

2. To run the tests:

   ```bash
   ./gradlew clean test
   ```

3. To run a group of tests

   ```bash
   ./gradlew clean test -Pgroups=<test_group_names>
   ```

4. To build the without the tests:

   ```bash
   ./gradlew clean build -x test
   ```

5. To debug the package with a remote debugger:

   ```bash
   ./gradlew clean build -Pdebug=<port>
   ```

6. To debug with Ballerina language:

   ```bash
   ./gradlew clean build -PbalJavaDebug=<port>
   ```

7. Publish the generated artifacts to the local Ballerina central repository:

   ```bash
   ./gradlew clean build -PpublishToLocalCentral=true
   ```

8. Publish the generated artifacts to the Ballerina central repository:

   ```bash
   ./gradlew clean build -PpublishToCentral=true
   ```

## Contribute to Ballerina

As an open-source project, Ballerina welcomes contributions from the community.

For more information, go to the [contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of conduct

All the contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).

## Useful links

- For more information go to the [`mcp` library](https://lib.ballerina.io/ballerina/mcp/latest).
- Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
- Post all technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
