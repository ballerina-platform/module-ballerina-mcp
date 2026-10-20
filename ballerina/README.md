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

Set `protocolMode` on the client or in `@mcp:StreamableHttpServiceConfig`.

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

@mcp:StreamableHttpServiceConfig {
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
            mcp:RequestMeta? meta) returns int {
        return left + right;
    }
}
```

The annotation has one `httpConfig` field for Ballerina HTTP service settings. Its CORS origin list is also used for
the MCP transport's required inbound `Origin` validation, on modern and legacy requests and before authentication. A
request without an `Origin` header is accepted; one whose origin is not listed, or matched by `*`, gets `403 Forbidden`.

```ballerina
@mcp:StreamableHttpServiceConfig {
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

- `mcp:HttpSession` or `mcp:HttpSession?`, at any position, for legacy HTTP session state.
- `mcp:RequestMeta?`, at any position, for the request's `_meta` value.
- `@http:Header` parameters, `http:Headers`, and `http:Request` for Streamable HTTP request data.

Runtime parameters do not appear in the generated tool input schema. Request metadata must be nilable because clients
may omit it.

### Structured tool output

Basic tools may return records, scalars, arrays, or other `anydata` values. The library builds the text content from
the return value: a `string` is used as is, `()` produces no content block, and any other value becomes its JSON
serialization. For a modern request it also:

- advertises a generated `outputSchema`;
- preserves the raw return value in `structuredContent`;
- accepts object, scalar, array, and nil JSON roots.

For a legacy request, basic tools keep the 1.x wire shape: `tools/list` advertises no `outputSchema`, and results
carry only the text content block, without `structuredContent`. Results from an advanced service are kept within the
legacy schema: an `outputSchema` or `structuredContent` whose root is not an object is removed.

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

Set `structuredOutput: false` in `@mcp:Tool` to make a tool's output unstructured on both protocols: the compiler
generates no `outputSchema`, and results carry only the text content. It cannot be combined with an explicit
`outputSchema`. A tool with no return type, or one that can only return `()` apart from `error`, such as `error?`, is
unstructured in the same way.

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

This produces a `region` property containing `"x-mcp-header": "Region"`. `@mcp:Argument` applies to a non-nilable
`string`, `int` or `boolean` argument. Header names are compared case-insensitively, and the client rejects a call whose
`int` argument header is outside ±(2<sup>53</sup>−1) with a `ToolCallError`. Use `@http:Header` when a value comes
only from an HTTP header and must not be part of the MCP tool arguments.

## Sessions

Legacy requests support three `HttpSessionMode` values:

- `mcp:STATEFUL`: require and maintain an MCP session ID.
- `mcp:STATELESS`: process every request independently.
- `mcp:AUTO`: select behavior from the request lifecycle.

```ballerina
@mcp:StreamableHttpServiceConfig {
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
`stream<mcp:JsonRpcNotification, error?>|mcp:ServerError` for change notifications. All three handlers can bind the
same HTTP request values as basic tools (`http:Headers`, `http:Request`, `@http:Header` and `mcp:AuthContext`);
`onSubscribe` binds them from the `subscriptions/listen` request, so a service whose tool list varies by caller can
scope its notifications to that caller. `onCallTool` reads request metadata from `CallToolParams._meta`.

While a subscription is open, the listener sends an SSE comment every 15 seconds, so idle timeouts do not close a
quiet connection. When the client disconnects, the listener closes the stream `onSubscribe` returned within one
such interval, and it may call `close()` while a `next()` call on that stream is still pending. `gracefulStop()`
ends every open subscription with its final result, waiting at most 5 seconds; `immediateStop()` does not.

`onListTools` may declare an `mcp:Cursor?` parameter to return its tools in pages. It receives the request's cursor,
or `()` for the first page, and sets `nextCursor` on every page but the last. A basic service always returns all of
its tools in one page.

```ballerina
remote isolated function onListTools(mcp:Cursor? cursor) returns mcp:ListToolsResult|mcp:ServerError {
    if cursor is () {
        return {tools: firstPage, nextCursor: "page-2"};
    }
    return {tools: secondPage};
}
```

## Server authorization

Set `httpConfig.auth` on `@mcp:StreamableHttpServiceConfig` to an `mcp:OAuthProtectedResourceConfig` to protect a service as an OAuth
protected resource (RFC 9728), as the MCP authorization specification requires. The service then:

- publishes protected resource metadata at `<origin>/.well-known/oauth-protected-resource<path>`,
- answers requests without a valid bearer token with `401` and a `WWW-Authenticate` challenge that points to
  the metadata,
- accepts only tokens issued for it (their audience), and
- answers callers that lack a required scope with `403` and `error="insufficient_scope"`, so that clients can
  obtain a token with more scopes and retry.

```ballerina
@mcp:StreamableHttpServiceConfig {
    info: {name: "files", version: "1.0.0"},
    httpConfig: {
        cors: {allowOrigins: ["https://app.example.com"]},
        auth: {
            'resource: "https://mcp.example.com/files",
            authorizationServers: [
                {
                    issuer: "https://login.example.com",
                    validator: {
                        jwtValidatorConfig: {
                            signatureConfig: {jwksConfig: {url: "https://login.example.com/oauth2/jwks"}}
                        }
                    }
                },
                {
                    issuer: "https://partner-idp.example.com",
                    audience: "api://files",
                    validator: {
                        oauth2IntrospectionConfig: {url: "https://partner-idp.example.com/oauth2/introspect"}
                    }
                }
            ],
            requiredScopes: ["files:read"]
        }
    }
}
service mcp:StreamableHttpService /files on mcpListener {
    @mcp:Tool {scopes: ["files:write"]}
    remote isolated function deleteFile(mcp:AuthContext auth, string path) returns string|error {
        // auth.subject, auth.issuer, auth.scopes, auth.claims and auth.token describe the authenticated caller.
        return "deleted " + path;
    }
}
```

- `resource` is the canonical URI clients use to reach the service. Set it explicitly behind a proxy.
- Protected services may use `httpConfig.host`. Each configured virtual host publishes its own protected resource
  metadata service, so the same resource path can be used on different hosts. The OAuth `resource` remains the public
  URI clients use and need not have the same host as the internal HTTP virtual host.
- Each authorization server pairs its `issuer` with how its tokens are validated: as JWTs (`jwtValidatorConfig`)
  or through an introspection endpoint (`oauth2IntrospectionConfig`). The issuers are advertised in the metadata.
- A token is only sent to the one authorization server that could have issued it. A JWT is validated by the server
  named in its `iss`, and a JWT naming another issuer, or none, is rejected. An opaque token names no issuer, so at
  most one authorization server can use introspection; use JWT access tokens, or a separate service, for more.
- A token must be issued for `resource`. When an authorization server uses its own identifier for the API, set it
  as that server's `audience`. Set the issuer and audience on the authorization server, not in
  `jwtValidatorConfig`.
- `requiredScopes` is local authorization policy applied to every request; it is not an OPRM field.
  `scopesSupported` controls the informational `scopes_supported` field in protected resource metadata and defaults
  to `requiredScopes`. `scopes` on `@mcp:Tool` are enforced by the server, are never sent to clients in `tools/list`,
  and are requested through `403` challenges.
- When the authorization server issues hierarchical scopes, declare them in `scopeHierarchy`, keyed by the broader
  scope. A token granted a broader scope then satisfies every scope it implies, transitively; challenges still name the
  exact scopes an operation needs, and `mcp:AuthContext.scopes` holds the implied scopes too.

  ```ballerina
  scopeHierarchy: {
      "files:admin": ["files:write", "files:delete"],
      "files:write": ["files:read"]
  }
  ```
- `offline_access` cannot be used in `requiredScopes`, `scopesSupported`, or tool `scopes`. It asks the authorization
  server for a refresh token rather than granting access to this server, so clients request it themselves.
- Declare an `mcp:AuthContext` parameter on a tool, or on a handler of an advanced service, to
  receive the authenticated caller. Declare it as `mcp:AuthContext?` on services without an `mcp:OAuthProtectedResourceConfig`.
- A tool or an advanced handler that decides at runtime that more scopes are needed returns
  `error mcp:InsufficientScopeError("...", scopes = ["admin"])`; the server answers with the `403` challenge.
- Scopes must be valid OAuth scope tokens: printable ASCII without spaces, `"` or `\`.
- When the introspection endpoint cannot be reached, requests are answered with `503` rather than `invalid_token`, so
  clients keep their token and retry.
- A legacy session belongs to the issuer, client and subject of the token that created it, and cannot be used with a
  token that differs in any of them, including a token issued to another client for the same user. A token that names
  neither a subject nor a client gets no session.

`httpConfig.auth` still accepts `http:ListenerAuthConfig[]`, HTTP listener authentication without discovery, exactly
as in 1.x. Failures are answered with `401` or `403` without a challenge, and tool scopes and `mcp:AuthContext` are
not available.

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

### Enterprise-managed authorization with ID-JAG

Use `IdentityAssertionGrant` when an enterprise OpenID Provider authorizes the signed-in user to access an MCP
server. The application owns the OpenID Connect login and session. The MCP client calls `assertionProvider` only when
it needs a Resource Authorization Server access token, after discovery has resolved the exact audience, resource,
Resource-AS client ID, and scopes.

```ballerina
import ballerina/mcp;

configurable string resourceAsClientSecret = ?;
configurable string idpClientSecret = ?;

isolated function currentIdToken() returns string|error {
    // Read or renew the ID token from the application's OpenID Connect session.
    return "...";
}

isolated function provideIdJag(mcp:IdentityAssertionContext context)
        returns string|error {
    return mcp:exchangeIdTokenForIdJag(check currentIdToken(), context, {
        issuer: "https://idp.example.com",
        clientId: "mcp-host-at-idp",
        clientAuth: {
            clientSecret: idpClientSecret,
            authMethod: mcp:CLIENT_SECRET_POST
        }
    });
}

final mcp:StreamableHttpClient client = check new (
    "https://tools.example.com/mcp",
    httpConfig = {
        auth: {
            grant: {
                clientConfig: {
                    clientId: "mcp-host-at-resource-as",
                    issuer: "https://resource-auth.example.com",
                    clientAuth: {clientSecret: resourceAsClientSecret}
                },
                assertionProvider: provideIdJag
            },
            scopes: ["tools:read"]
        }
    }
);
```

`clientConfig` accepts the same client registrations as the authorization code grant: a pre-registered client, whose
`issuer` must be listed in the MCP server's protected resource metadata, or a Client ID Metadata Document, whose
Resource AS is taken from that metadata. `clientAuth` is optional in both, so a public client is also supported. The
OpenID Provider only issues an ID-JAG for a Resource AS its administrator has configured, so the metadata cannot
direct the assertion to an unknown authorization server. The OpenID Provider client registration is independent and belongs
to `IdentityProviderConfig` (or to custom code inside `assertionProvider`). The module never caches the ID-JAG and
ignores a refresh token returned by the Resource Authorization Server; it caches only the final MCP access token.

`assertionProvider` runs while the client holds its authorization lock, so other requests on the same client wait
until it returns, and it must not call the same client.

A rejected token request is reported as an `mcp:OAuthTokenError` in the cause chain of the returned error. Its
`detail()` carries the endpoint's OAuth error response. For example, `insufficient_user_authentication` from the
OpenID Provider, with `maxAge`, means the user must sign in again:

```ballerina
function needsReauthentication(error err) returns boolean {
    error? current = err;
    while current is error {
        if current is mcp:OAuthTokenError {
            return current.detail()?.code == "insufficient_user_authentication";
        }
        current = current.cause();
    }
    return false;
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
    httpConfig: {timeout: 30}
};
final mcp:StreamableHttpClient client = check new ("http://localhost:9090/mcp", config);
```

HTTP settings go under `httpConfig`, an `mcp:HttpClientConfig` with the fields and defaults of
`http:ClientConfiguration`, except that `auth` also accepts `mcp:OAuthConfig`. With `mcp:OAuthConfig`, redirects are
not followed and `init` returns an error if `followRedirects` enables them; the metadata and token endpoint requests
reuse `secureSocket` and `proxy`.

Use `callToolOnce()` when the application needs to handle each continuation itself. It returns
`CallToolResult|InputRequiredResult` after one logical request. On a legacy connection it delegates to
`callTool()`, because legacy MCP has no input-required continuation result.

The lower-level lifecycle methods are available for applications that manage discovery themselves:

- `discover()` fetches modern discovery data without connecting the client.
- `adoptDiscovery()` connects from a previously obtained `DiscoverResult`.
- `initializeLegacy()` explicitly performs the older initialize handshake.
- `listen()` opens modern subscriptions or the legacy GET event stream according to the negotiated connection.

## Caching

Modern `server/discover` and `tools/list` results carry caching hints: `ttlMs`, how long a client may treat the
result as fresh, and `cacheScope`, whether the result may be shared between callers (`public`) or only reused for
the same authorization context (`private`). Services default to `ttlMs: 0` and `cacheScope: "private"`, which
disables reuse. Set hints per method in `@mcp:StreamableHttpServiceConfig`:

```ballerina
@mcp:StreamableHttpServiceConfig {
    info: {name: "weather", version: "1.0.0"},
    cacheHints: {
        discover: {ttlMs: 300000, cacheScope: "public"},
        listTools: {ttlMs: 60000, cacheScope: "public"}
    }
}
service mcp:StreamableHttpService /mcp on mcpListener {
    // ...
}
```

An advanced service may also set `ttlMs` or `cacheScope` on the `ListToolsResult` returned by `onListTools`; each
field set there takes precedence over the configured hint. A negative configured `ttlMs` fails `attach`, while a
negative `ttlMs` from `onListTools` is sent as `0` and logged as an error. Hints are only sent to modern clients.

The client reuses a `tools/list` result while it is fresh, caching each page by its cursor. Each client keeps its own
cache and represents a single authorization context: configure credentials through `httpConfig.auth`, and use a
separate client for each user rather than passing different credentials as per-call headers. A call that passes its own
`Authorization` header bypasses the cache. Cached results are dropped when:

- the application reads `notifications/tools/list_changed` from `listen()`,
- the server rejects a cursor with `INVALID_PARAMS` (all pages are dropped),
- a call fails with `HEADER_MISMATCH`,
- a `401` or `insufficient_scope` challenge yields a different token, since a step-up can change the tool list, or
- the client is closed with `close()`.

A token refreshed on expiry keeps the cache. A negative `ttlMs` from a server is treated as `0`. Pass
`cacheMode = "refresh"` to `listTools()` to fetch and re-cache the list, or `cacheMode = "bypass"` to fetch without
touching the cache. Set `resultCache = ()` in the client configuration to disable reuse, or adjust `maxTtlMs` and
`maxEntries` in `resultCache` to bound it.

## Migrating from 1.x

Version 2.0 removes the transport-neutral listener, service types and annotation, and gives Streamable HTTP concepts
explicit names.

| 1.x API | 2.0 API |
| --- | --- |
| `mcp:Listener` | `mcp:StreamableHttpListener` |
| `mcp:Service` | `mcp:StreamableHttpService` |
| `mcp:AdvancedService` | `mcp:StreamableHttpAdvancedService` |
| `@mcp:ServiceConfig` | `@mcp:StreamableHttpServiceConfig` |
| `mcp:Session`, `mcp:SessionEntry` | `mcp:HttpSession`, `mcp:HttpSessionEntry` |
| `mcp:SessionMode` | `mcp:HttpSessionMode` |
| `mcp:Meta` | `mcp:RequestMeta` |
| `mcp:StreamableHttpClientTransportConfig` | `mcp:StreamableHttpClientConfig` |
| `http:ClientConfiguration` fields at the top level of the client configuration | The same fields under `httpConfig`, an `mcp:HttpClientConfig` |
| An `http:HttpServiceConfig` value for `httpConfig` | `mcp:HttpServiceConfig`: the same fields, with `auth` also accepting `mcp:OAuthProtectedResourceConfig` |
| `initialize()` | `connect()` or `initializeLegacy()` |
| `subscribeToServerMessages()` | `listen()` |

1.x did not validate `Origin`. A 2.0 service rejects browser requests from origins that are not listed in
`httpConfig.cors.allowOrigins`, which is empty by default.

The client must now call `connect()`, or `initializeLegacy()`, before other operations; 1.x did not enforce
`initialize()`.

A legacy client keeps receiving the legacy wire shapes from a 2.0 server. The text content of a tool that returns a
structured value is now its JSON serialization.

The `2025-11-25` task fields are removed: `CallToolParams.task`, `ToolDefinition.execution` and the `tasks` client and
server capabilities. A client still connects to a server that advertises tasks.

The public error hierarchy is `mcp:Error`, `mcp:ClientError`, `mcp:TransportError`, `mcp:ProtocolError`,
`mcp:ToolCallError`, `mcp:StreamError`, and `mcp:ServerError`; transport and decoder implementation errors are
internal.
