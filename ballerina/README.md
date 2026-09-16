## Overview

The `ballerina/mcp` module builds MCP clients and servers over Streamable HTTP. Version 2.0 supports MCP
`2026-07-28` and can still communicate with servers and clients using the initialize-based protocol through
`2025-11-25`.

### Key Features

- MCP client and server implementation for LLM tool integration
- Automatic tool discovery and type-safe schema generation
- Flexible session management (STATEFUL, STATELESS, AUTO modes) for the legacy protocol
- Streamable HTTP transport with Server-Sent Events (SSE)

## Protocol modes

Set `protocolMode` on the client or in `@mcp:StreamableHttpConfig`.

| Mode | Client behavior | Server behavior |
| --- | --- | --- |
| `"auto"` | Try modern discovery, then fall back to the legacy initialize handshake only when the response indicates an older server | Accept modern requests and legacy initialize-based requests |
| `"modern"` | Require MCP `2026-07-28` | Accept modern requests only |
| `"legacy"` | Use the initialize handshake | Accept initialize-based requests only |

`"auto"` is the default. Existing MCP clients can continue to connect to an auto-mode Ballerina server. The server
recognizes the request form and follows the corresponding lifecycle.

Modern MCP requests are sessionless. A service that requires an `mcp:HttpSession` parameter can serve legacy requests
in `"auto"` or `"legacy"` mode. It cannot serve modern tool calls. The compiler reports this combination. A nilable
`mcp:HttpSession?` is permitted and receives `()` for a modern request; the compiler warns so that application code
can handle that case deliberately.

## Basic server

A basic service exposes each remote method as a tool. The compiler derives its input and output schemas from the method
signature.

```ballerina
import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);

@mcp:StreamableHttpConfig {
    info: {
        name: "calculator",
        version: "2.0.0"
    },
    protocolMode: "auto",
    sessionMode: mcp:AUTO
}
service mcp:StreamableHttpService /mcp on mcpListener {
    # Add two numbers.
    remote isolated function add(int left, int right,
            mcp:RequestMetaObject? meta) returns int {
        return left + right;
    }
}
```

The annotation has one `httpConfig` field for Ballerina HTTP service settings. Its CORS origin list is also used for
the MCP transport's required inbound `Origin` validation.

```ballerina
@mcp:StreamableHttpConfig {
    info: {name: "calculator", version: "2.0.0"},
    httpConfig: {
        cors: {
            allowOrigins: ["https://example.com"],
            allowCredentials: true
        }
    }
}
service mcp:StreamableHttpService /mcp on mcpListener {
    // Tools
}
```

A tool may bind these runtime values in addition to ordinary `anydata` arguments:

- `mcp:HttpSession` or `mcp:HttpSession?`, placed first, for legacy HTTP session state.
- `mcp:RequestMetaObject?`, at any position, for the request's `_meta` value.
- `@http:Header` parameters, `http:Headers`, and `http:Request` for Streamable HTTP request data.

Runtime parameters do not appear in the generated tool input schema. Request metadata must be nilable because clients
may omit it.

### Structured tool output

Basic tools may return records, scalars, arrays, or other `anydata` values. The library always creates a text content
block. For a modern request it also:

- advertises a generated `outputSchema`;
- preserves the raw return value in `structuredContent`;
- accepts object, scalar, array, and nil JSON roots.

For a legacy request, the adapter preserves the older wire shape. Object-root structured content remains available
where the legacy schema permits it; scalar and array structured values remain represented by the text content block.

Use `@mcp:Tool` to override generated metadata:

```ballerina
@mcp:Tool {
    description: "Return account balances",
    schema: {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        'type: "object",
        properties: {accountId: {type: "string"}},
        required: ["accountId"]
    },
    outputSchema: {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        type: "array",
        items: {type: "number"}
    }
}
remote isolated function balances(string accountId) returns decimal[] {
    return [12.50d, 30.00d];
}
```

`InputSchema` enforces an object root. `OutputSchema` allows any JSON Schema root. Both are open records and accept
JSON Schema keywords that the module does not declare. Until Ballerina provides native JSON Schema evaluation, these
documents are carried as metadata; Ballerina type binding remains responsible for ordinary tool arguments.

To mirror a regular-service tool argument into the modern MCP parameter header, annotate the argument with
`@mcp:Argument`. The argument remains in `tools/call.params.arguments`; the generated input schema carries the
standard `x-mcp-header` extension used by interoperable clients and servers.

```ballerina
remote isolated function weather(
        @mcp:Argument {headerName: "Region"} string region) returns Weather|error {
    // ...
}
```

This produces a `region` property containing `"x-mcp-header": "Region"`. Use `@http:Header` when a value comes only
from an HTTP header and must not be part of the MCP tool arguments.

## Sessions

Legacy requests support three `HttpSessionMode` values:

- `mcp:STATEFUL`: require and maintain an MCP session ID.
- `mcp:STATELESS`: process every request independently.
- `mcp:AUTO`: select behavior from the request lifecycle.

```ballerina
@mcp:StreamableHttpConfig {
    info: {name: "cart", version: "2.0.0"},
    protocolMode: "auto",
    sessionMode: mcp:STATEFUL
}
service mcp:StreamableHttpService /mcp on mcpListener {
    remote isolated function addItem(mcp:HttpSession session, string item) returns string {
        string[] items = session.hasKey("items")
            ? checkpanic session.getWithType("items")
            : [];
        items.push(item);
        session.set("items", items);
        return "Item added";
    }
}
```

Prefer explicit application-level handles for state that modern clients must access.

## Advanced server

Use `mcp:StreamableHttpAdvancedService` when the application must define tool discovery and dispatch itself.

```ballerina
service mcp:StreamableHttpAdvancedService /mcp on mcpListener {
    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {
            tools: [{
                name: "echo",
                inputSchema: {
                    'type: "object",
                    properties: {value: {type: "string"}},
                    required: ["value"]
                },
                outputSchema: {type: "string"}
            }]
        };
    }

    remote isolated function onCallTool(mcp:CallToolParams params)
            returns mcp:CallToolResult|mcp:InputRequiredResult|mcp:ServerError {
        if params.name != "echo" {
            return error mcp:ServerError("Unknown tool");
        }
        json value = params.arguments?.value ?: "";
        return {
            content: [{type: "text", text: value.toJsonString()}],
            structuredContent: value
        };
    }
}
```

`onListTools` and `onCallTool` are required. `onCallTool` may return `InputRequiredResult` for a modern
continuation. An optional `onSubscribe(mcp:SubscriptionFilter)` method may return
`stream<mcp:JsonRpcNotification, error?>|mcp:ServerError` for change notifications. Advanced handlers can bind the
same HTTP request values as basic tools; `onCallTool` reads request metadata from `CallToolParams._meta`.

## Client

Creating a client configures its transport. `connect()` performs protocol selection and is required before
`listTools()`, `callTool()`, or `listen()`.

```ballerina
import ballerina/io;
import ballerina/mcp;

public function main() returns error? {
    final mcp:StreamableHttpClient client = check new (
        "http://localhost:9090/mcp",
        protocolMode = "auto"
    );

    mcp:ConnectionInfo connection = check client->connect(
        {name: "example-client", version: "2.0.0"},
        {elicitation: {form: {}}}
    );
    io:println("Using MCP ", connection.protocolVersion);

    mcp:ListToolsResult listed = check client->listTools();
    mcp:CallToolResult result = check client->callTool({
        name: "add",
        arguments: {left: 2, right: 3}
    });

    io:println(result.structuredContent);
    check client->close();
}
```

`callTool()` is the main API. When a modern server returns `InputRequiredResult`, it calls the configured
`inputHandler`, echoes the opaque request state, and continues until the call completes or `maxInputRounds` is
reached.

```ballerina
mcp:StreamableHttpClientConfig config = {
    protocolMode: "auto",
    maxInputRounds: 4,
    inputHandler: isolated function (mcp:InputRequest request)
            returns mcp:InputResponse|mcp:ClientError {
        return {action: "accept"};
    },
    timeout: 30
};
final mcp:StreamableHttpClient client = check new ("http://localhost:9090/mcp", config);
```

Use `callToolOnce()` when the application needs to handle each continuation itself. It returns
`CallToolResult|InputRequiredResult` after one logical request. On a legacy connection it delegates to
`callTool()`, because legacy MCP has no input-required continuation result.

The lower-level lifecycle methods are available for applications that manage discovery themselves:

- `discover()` fetches modern discovery data without connecting the client.
- `adoptDiscovery()` connects from a previously obtained `DiscoverResult`.
- `initializeLegacy()` explicitly performs the older initialize handshake.
- `listen()` opens modern subscriptions or the legacy GET event stream according to the negotiated connection.

## Migrating from 1.x

Version 2.0 removes deprecated transport-neutral aliases and gives Streamable HTTP concepts explicit names.

| 1.x API | 2.0 API |
| --- | --- |
| `mcp:Listener` | `mcp:StreamableHttpListener` |
| `mcp:Service` | `mcp:StreamableHttpService` |
| `mcp:AdvancedService` | `mcp:StreamableHttpAdvancedService` |
| `@mcp:ServiceConfig`, `@mcp:StreamableHttpServiceConfig` | `@mcp:StreamableHttpConfig` |
| `mcp:Session`, `mcp:SessionEntry` | `mcp:HttpSession`, `mcp:HttpSessionEntry` |
| `mcp:SessionMode` | `mcp:HttpSessionMode` |
| `mcp:Meta` | `mcp:RequestMetaObject` |
| `mcp:StreamableHttpClientTransportConfig` | `mcp:StreamableHttpClientConfig` |
| `initialize()` | `connect()` or `initializeLegacy()` |
| `callToolWithResult()` | `callToolOnce()` |
| `subscribeToServerMessages()` | `listen()` |

The client no longer connects implicitly. Call `connect()` before operations that depend on negotiated server state.
The public error hierarchy is `mcp:Error`, `mcp:ClientError`, `mcp:TransportError`, `mcp:ProtocolError`,
`mcp:ToolCallError`, `mcp:StreamError`, and `mcp:ServerError`; transport and decoder implementation errors are
internal.
