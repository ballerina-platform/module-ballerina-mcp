## Overview

This module offers APIs for developing MCP (Model Context Protocol) clients and servers in Ballerina.

MCP is an open standard that enables seamless integration between Large Language Models (LLMs) and external data sources, tools, and services. It facilitates structured communication through JSON-RPC 2.0 over HTTP transport, allowing AI applications to access and interact with external capabilities in a standardized way. This module provides both client-side APIs for consuming MCP services and server-side APIs for exposing tools and capabilities to AI applications.

## Protocol versions and compatibility

Version 1.4.0 adds MCP `2026-07-28` for tools over Streamable HTTP. Clients and services default to
`protocolMode: "auto"`. Protocol mode is independent of `sessionMode`, which controls legacy HTTP sessions.

| Protocol mode | Client behavior | Service behavior |
| --- | --- | --- |
| `"auto"` (default) | Probe `server/discover`; fall back to the legacy handshake when appropriate | Serve modern and legacy requests on the same endpoint |
| `"legacy"` | Use the existing `initialize` handshake | Keep the legacy protocol and session behavior |
| `"modern"` | Require `2026-07-28` | Accept modern, sessionless requests |

The supported legacy version identifiers remain `2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05`, and
`2024-10-07`. This retains existing version handling; it does not add the older HTTP+SSE or stdio transports.
Modern requests carry version and capabilities in `_meta`; they neither require initialization nor use protocol sessions.
The existing `initialize()` method remains available and selects the appropriate lifecycle. Supplying a saved
`sessionId` keeps a client on the legacy path; combining it with explicit modern mode is an error.

```ballerina
mcp:StreamableHttpClient compatibleClient = check new (serverUrl);
mcp:StreamableHttpClient legacyClient = check new (serverUrl, protocolMode = "legacy");
```

Modern discovery reports the service's available protocol versions, capabilities, identity, and instructions.
Only implemented capabilities are advertised. Resources, prompts, sampling/roots runtimes, logging, and the tasks
extension are not added by this release. Legacy task-related types remain available for source compatibility.
Extension capability settings and application metadata can still be carried as data.

### Session-dependent services

An auto-mode service with a required `mcp:Session` parameter remains legacy-only, with a compiler warning.
An explicitly modern service with such a parameter fails compilation and is also rejected during runtime attachment.
A nilable `mcp:Session?` parameter is allowed, but receives a warning in modern and auto modes: modern requests supply
nil. The compiler does not infer session requirements hidden inside arbitrary application code. Select legacy mode
explicitly when such code requires a protocol session.

For modern cross-call state, pass a server-created application handle as a normal tool argument. The original
shopping example retains its session behavior; the shopping example with explicit cart handles demonstrates the
sessionless alternative. Multi-instance deployments need shared application storage for these handles.

Traditional service handlers retain their application metadata view: automatically generated protocol version,
client identity, and capability fields are removed before binding `mcp:Meta` or traditional `CallToolParams`.
The newer `ProtocolService` receives the full request metadata. Existing client result methods retain readonly results and hide wire-only
result fields and server identity while retaining application response metadata.

### Modern tool results and continuations

`ProtocolService` exposes `onListTools()` returning `ProtocolListToolsResult`, and `onCallTool(CallToolParams)`
returning `ProtocolCallToolResult`, `InputRequiredResult`, or `ServerError`. Use `@mcp:StreamableHttpServiceConfig`
and `mcp:StreamableHttpListener` to expose it. Traditional service interfaces remain supported. When a handler returns a union of complete and input-required results,
include the appropriate `resultType` in the record constructor to disambiguate it.

Use `listToolsWithSchemas(headers, cursor)` to preserve general output schemas, and `callToolWithResult(params, headers)`
to preserve arbitrary JSON structured output, including arrays, scalars, and explicit null. Input schemas still have an
object root. Existing `listTools()` and `callTool()` keep their original return types; a modern result that cannot fit
those types produces an error directing the application to the new method. Explicit legacy mode retains the old wire
path when interoperating with a server that supports it.

`callToolWithResult()` performs one logical tool request and exposes an input-required result to the application.
To continue, provide `inputResponses` and echo `requestState` exactly in the next call. A fresh JSON-RPC ID is assigned
on every continuation. When using `callTool()`, an optional `inputHandler` callback can gather the requested input;
`maxInputRounds` bounds automatic continuation (default: 8). Declare matching client capabilities in `initialize()`.
Without a callback, a result requiring user input produces an actionable error; state-only continuations need no callback.

Servers must treat returned `requestState` as client-supplied input. Protect and verify any state that affects business
logic or authorization, and design side effects so continuation retries do not repeat them unintentionally.

### HTTP headers, caching hints, and subscriptions

Modern requests include matching `MCP-Protocol-Version`, `Mcp-Method`, and applicable `Mcp-Name` headers.
`x-mcp-header` annotations mirror supported primitive tool arguments into `Mcp-Param-*` headers; this is separate from
Ballerina's existing `@http:Header` injection. Invalid annotations are excluded by the client. Conflicting additional
protocol headers are rejected locally. A header-mismatch rejection triggers at most one schema refresh and corrected retry.
Tool-schema lookup follows pagination and is separated by the supplied request headers.

Discovery and tool lists include `ttlMs` and `cacheScope`, defaulting to `0` and `"private"`. The client does not introduce
a shared result cache or background polling. Modern requests with an Origin header must match the service's
`allowedOrigins` list; requests without Origin are accepted. Set that list explicitly for browser clients.

`SubscriptionService` extends `ProtocolService` with `onSubscribe(SubscriptionFilter)`, returning a notification stream.
Server-side subscriptions currently publish tool-list changes. The transport acknowledges the accepted filter first,
adds subscription IDs, filters events, and completes the request when the source ends. Event sources must release
resources when closed. `listen()` returns a client notification stream; closing it cancels the subscription, and closing
the client closes its open subscriptions. The client can also consume prompt/resource notifications from other servers.
`subscribeToServerMessages()` uses the new subscription path for modern peers and retains GET behavior for legacy peers.
Modern SSE streams are not resumed or automatically replayed after disconnection.

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

Legacy MCP requests support three session management modes. Modern requests are always sessionless:

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
2. `onCallTool` must accept exactly one `mcp:CallToolParams` parameter, and may accept an `mcp:Session?` parameter for stateful services. An `mcp:Meta?` parameter is not accepted here, unlike on the tools of a basic service; read the metadata from the `_meta` field of the `mcp:CallToolParams` value instead.
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

### Schema validation

The library retains Ballerina type binding for basic tool arguments and typed record decoding for protocol messages.
JSON Schema documents are carried as metadata; the library does not evaluate schema constraints or resolve `$ref`
references. Advanced service implementations are responsible for semantic validation of their arguments and results.
General JSON Schema evaluation is deferred until language support is available. Validation of `x-mcp-header`
annotations and their mirrored HTTP values remains part of the transport protocol.
