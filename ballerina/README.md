## Overview

This package provides APIs for building MCP (Model Context Protocol) clients and servers in Ballerina, enabling standardized integration between LLMs and external data sources, tools, and services via JSON-RPC 2.0 over HTTP. It contains two modules:

| Module | Import | Protocol |
| --- | --- | --- |
| `ballerina/mcp.v2`, the v2 module | `import ballerina/mcp.v2 as mcp;` | MCP `2026-07-28`, which can still communicate with servers and clients using the initialize-based protocol through `2025-11-25` |
| `ballerina/mcp`, the 1.x API | `import ballerina/mcp;` | The initialize-based protocol through `2025-11-25` |

Use the v2 module for new code. The 1.x API keeps working unchanged, but its client and its transport-agnostic services are deprecated in favour of the v2 module.

## The v2 module

Import the v2 module with the `mcp` prefix, so that its documentation and examples apply as written:

```ballerina
import ballerina/mcp.v2 as mcp;
```

### Key Features

- MCP client and server implementation for LLM tool integration, with automatic selection between the modern and the legacy protocol
- Automatic tool discovery and type-safe input and output schema generation
- Input-required results with form and URL elicitation
- OAuth for clients, and OAuth protected resource support for services
- Streamable HTTP transport with Server-Sent Events (SSE)

### Server

A basic service exposes each remote method as a tool. The compiler derives its input and output schemas from the method signature.

```ballerina
import ballerina/mcp.v2 as mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);

@mcp:StreamableHttpServiceConfig {
    info: {
        name: "calculator",
        version: "1.0.0"
    }
}
service mcp:StreamableHttpService /mcp on mcpListener {
    # Add two numbers.
    remote isolated function add(int left, int right) returns int {
        return left + right;
    }
}
```

### Client

```ballerina
import ballerina/io;
import ballerina/mcp.v2 as mcp;

public function main() returns error? {
    final mcp:StreamableHttpClient mcpClient = check new ("http://localhost:9090/mcp");
    _ = check mcpClient->connect({name: "example-client", version: "1.0.0"});

    mcp:CallToolResult result = check mcpClient->callTool({
        name: "add",
        arguments: {"left": 2, "right": 3}
    });
    io:println(result?.structuredContent);
    check mcpClient->close();
}
```

See the `mcp.v2` module documentation for protocol modes, sessions, advanced services, elicitation, authorization, caching, and how to migrate from the 1.x API.

### Examples

The [examples directory](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/) uses the v2 module:

1. [Weather MCP Server](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-weather-server) and [client](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/clients/mcp-weather-client) - A basic service with AUTO session mode
2. [Crypto MCP Server](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-crypto-server) and [client](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/clients/mcp-crypto-client) - An advanced service with STATELESS session mode
3. [Shopping Cart Server](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-shopping-server) and [client](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/clients/mcp-shopping-client) - STATEFUL session mode, and a [modern-protocol variant](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-shopping-server-modern)
4. [Calendar Connect Server](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-calendar-connect-server) and [client](https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/clients/mcp-calendar-connect-client) - URL elicitation for an out-of-band connection step

## The 1.x API

The root module, `ballerina/mcp`, is the API of the 1.x releases. Its behaviour, wire format and compiler diagnostics are unchanged in this release.

### Key Features

- MCP Client and Server implementation for LLM tool integration
- Automatic tool discovery and type-safe schema generation
- Flexible session management (STATEFUL, STATELESS, AUTO modes)
- Streamable HTTP transport with Server-Sent Events (SSE)

### Deprecations

These 1.x symbols are deprecated in favour of the v2 module:

| Deprecated | Replacement in the v2 module |
| --- | --- |
| `mcp:StreamableHttpClient` | `mcp.v2:StreamableHttpClient` |
| `mcp:Service` | `mcp.v2:StreamableHttpService` on an `mcp.v2:StreamableHttpListener` |
| `mcp:AdvancedService` | `mcp.v2:StreamableHttpAdvancedService` on an `mcp.v2:StreamableHttpListener` |
| `@mcp:ServiceConfig` | `@mcp.v2:StreamableHttpServiceConfig` |
| `mcp:Listener` | `mcp:StreamableHttpListener`, or `mcp.v2:StreamableHttpListener` |

### Quickstart

To use the 1.x API in your Ballerina application, update the `.bal` file as follows:

#### MCP Server Implementation

##### Step 1: Import the module

Import the `mcp` module.

```ballerina
import ballerina/mcp;
```

##### Step 2: Initialize the MCP Listener

Create a Streamable HTTP listener to expose tools to AI applications:

```ballerina
listener mcp:StreamableHttpListener mcpListener = check new (9090);
```

> **Note:** The `mcp:Listener` class is deprecated. Use `mcp:StreamableHttpListener` instead.

##### Step 3: Create the MCP Service

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

1. Parameters should be a subtype of `anydata`. The runtime-injected parameters are the exceptions: `mcp:Session` for stateful services, and `mcp:Meta?` for request metadata.
2. The tool should return a subtype of `anydata|error`.
3. The `@mcp:Tool` annotation is not required unless you want fine-grained control. If the annotation is not provided, the documentation string will be considered as the description.
4. For session-enabled tools, the `mcp:Session` parameter must be the first parameter if present.
5. A tool may accept an `mcp:Meta?` parameter to read the request metadata (`_meta`) the client attached to the call. It must be declared nilable -- a non-nilable `mcp:Meta` is a compile error -- and at most one is allowed per method. Unlike `mcp:Session`, its position in the signature is unconstrained. It is injected by the runtime and excluded from the generated tool input schema, so it is never a tool argument the client supplies. `mcp:Meta` is an open record, so keys the client sent are read through member access. Its one declared field, `progressToken`, is carried for spec conformance only: progress notifications are not implemented, so a server cannot act on it.
6. Tools in an `mcp:StreamableHttpService` can additionally bind HTTP request information, such as `@http:Header` parameters, an `http:Headers` parameter, or an `http:Request` parameter. These require importing the `ballerina/http` module, and `@http:Header` parameters are excluded from the generated tool input schema.

**Request Metadata Example:**
```ballerina
service mcp:StreamableHttpService /mcp on mcpListener {

    # Summarize a document
    #
    # + document - The text to summarize
    # + meta - The request metadata attached by the client
    # + return - The summary, or an error if the request fails
    remote function summarize(string document, mcp:Meta? meta) returns string|error {
        // `document` is the only argument in the tool's input schema; `meta` is injected
        // by the runtime and is nil when the client attached no metadata.
        // `mcp:Meta` is an open record, so any key the client sent is readable.
        anydata requestId = meta is mcp:Meta ? meta["requestId"] : ();
        if requestId is string {
            return summarizeTagged(document, requestId);
        }
        return summarizeQuietly(document);
    }
}
```

##### Step 4: Advanced Service Implementation (Optional)

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
2. `onCallTool` must accept exactly one `mcp:CallToolParams` parameter, and may accept an `mcp:Session?` parameter for stateful services. An `mcp:Meta?` parameter is not accepted here, unlike on the tools of a basic service; read the metadata from the `_meta` field of the `mcp:CallToolParams` value instead.
3. As with the tools of an `mcp:StreamableHttpService`, both methods can additionally bind HTTP request information, such as `@http:Header` parameters, an `http:Headers` parameter, or an `http:Request` parameter.

#### MCP Client Implementation

> **Note:** The 1.x client, `mcp:StreamableHttpClient`, is deprecated. Use the client of the v2 module instead.

##### Step 1: Import the module

Import the `mcp` module.

```ballerina
import ballerina/mcp;
```

##### Step 2: Initialize the MCP Client

Create an MCP client to connect to an external MCP server:

```ballerina
final mcp:StreamableHttpClient mcpClient = check new ("http://localhost:3000/mcp");
```

##### Step 3: Initialize Connection and Discover Tools

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

##### Step 4: Invoke Tools

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

##### Step 5: Handle Client Configuration (Optional)

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
