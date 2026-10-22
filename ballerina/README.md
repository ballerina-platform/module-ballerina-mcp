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
| `"auto"` | Try modern discovery, then fall back to the legacy initialize handshake only when the response indicates an older server or lists only legacy versions; return an error when it lists no supported version | Accept modern requests and legacy initialize-based requests |
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
- `mcp:Context`, at any position, for the input responses and request state of a continuation (see
  [Eliciting input from a basic service](#eliciting-input-from-a-basic-service)).

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
`int` argument header is outside ±(2<sup>53</sup>−1) with a `ToolCallError`. Only `string`, `integer` and `boolean`
schema properties may carry `x-mcp-header`, so the client leaves out of `listTools()` any tool whose header
declarations are invalid, such as one on a `number` property. Use `@http:Header` when a value comes only from an HTTP
header and must not be part of the MCP tool arguments.

### Eliciting input from a basic service

On the modern protocol, a tool can ask the user for input by returning an `mcp:InputRequiredResult` instead of its
result. Build its elicitations with `mcp:elicitForm(message, schema)` or `mcp:elicitUrl(message, url)`. The client
answers them and retries the call as a continuation. The tool then runs again from the top and reads the answers
through an `mcp:Context` parameter.

```ballerina
type Confirmation record {|
    boolean confirmed;
|};

remote isolated function deleteRepository(string name, mcp:Context context)
        returns string|mcp:InputRequiredResult {
    Confirmation? confirmation = context.acceptedContent("confirm");
    if confirmation is () {
        return {
            inputRequests: {
                "confirm": mcp:elicitForm(string `Delete ${name}?`, {
                    properties: {confirmed: {'type: "boolean", description: "Confirm deletion"}},
                    required: ["confirmed"]
                })
            }
        };
    }
    return confirmation.confirmed ? "Deleted" : "Kept";
}
```

The schema can also be a record type. Its form schema is generated at compile time: each field becomes a form
field, its doc comment becomes the field's description, and optional fields and fields with defaults are left out of
`required`. Read the answer back as the same type.

```ballerina
enum Seating {
    INDOOR = "indoor",
    PATIO = "patio"
}

type TableBooking record {|
    # Who the table is for
    string name;
    # How many people are coming
    int guests;
    # Where to sit
    Seating seating;
    # Anything the kitchen should know
    string notes?;
|};

remote isolated function bookTable(mcp:Context context) returns string|mcp:InputRequiredResult {
    TableBooking? booking = context.acceptedContent("booking");
    if booking is () {
        return {inputRequests: {"booking": mcp:elicitForm("Book a table", TableBooking)}};
    }
    return string `Booked for ${booking.name}`;
}
```

A field must be a `string`, `int`, `float`, `decimal` or `boolean`, which become text, integer, number and yes/no
fields; a union of string constants or an `enum`, which becomes a single-select field; or an array of those, which
becomes a multi-select field. Any other field type, such as a nested record, `json`, an array of records or a nilable
type, is a compile error. The record type must be named at the call site; a `typedesc` variable is a compile error.

`mcp:Context` is read-only and covers one round:

- `acceptedContent(key, T)` returns the submitted content as `T`. It returns `()` when the input request was not
  answered, was declined or cancelled, or its content does not convert to `T`, so treat `()` as "ask again".
- `elicitResult(key)` returns the raw `mcp:ElicitResult`, to tell a decline from a cancel or to read the answer to
  a URL elicitation (see [Completing a URL elicitation](#completing-a-url-elicitation)).
- `requestState()` returns the request state the tool returned in the previous round.

Neither `mcp:Context` nor `mcp:InputRequiredResult` appears in the generated tool schemas.

Because the tool runs again on every round, work done before it decides to ask is repeated. Keep that work safe to
repeat, and put anything expensive or non-repeatable after the ask or in the request state. The request state is
readable by the client, so do not put secrets in it; see [Request state](#request-state).

On a legacy call the context is empty, so a tool that does not need input works for older clients. A tool that
returns an input-required result on a legacy call gets a JSON-RPC error. The service checks input-required results
as described in [Eliciting input from an advanced service](#eliciting-input-from-an-advanced-service).

### Completing a URL elicitation

A URL elicitation sends the user to a page outside the MCP client, for example to connect a third-party account. An
`accept` answer only means the user agreed to open the URL, not that they finished there. The page reports
completion to the service out of band, so on each continuation the tool checks its own store and, until the step is
done, returns the URL elicitation again. A `decline` or `cancel` answer means the user will not open it.

```ballerina
remote isolated function listEvents(mcp:AuthContext auth, mcp:Context context)
        returns string[]|mcp:InputRequiredResult|error {
    string? subject = auth.subject;
    if subject is () {
        return error("The access token names no user");
    }
    if isConnected(subject) {
        return fetchEvents(subject);
    }
    mcp:ElicitResult? answer = context.elicitResult("connect");
    if answer is mcp:ElicitResult && answer.action != "accept" {
        return error("The calendar is not connected");
    }
    // Reuse the previous round's link, whose id the request state carries, or issue a new one.
    string connectionId = check issueConnectLink(context.requestState(), subject);
    return {
        inputRequests: {
            "connect": mcp:elicitUrl("Connect your calendar",
                    string `https://calendar.example.com/connect?id=${connectionId}`)
        },
        requestState: connectionId
    };
}
```

Anyone the URL is passed to can open it, so the page must check that the user who opened it is the user the
elicitation was issued to. Record the `mcp:AuthContext` subject when issuing the link, sign the user in on the page
through the same authorization server, and compare the subjects before accepting anything. Keep the URL free of
credentials and user identifiers, do not make it grant access by itself, and serve it over HTTPS outside development.
Store third-party tokens obtained on the page in the service; never return them to the client.

The service only checks that the URL is absolute (a scheme and a host); `http` URLs are allowed for development.
The connect page must also hold when the URL is altered: an unknown or expired id completes nothing, and a valid id
completes only for its own user. The [calendar connect example][calendar-connect-example] runs the whole flow,
including a connect page that rejects other users.

[calendar-connect-example]: https://github.com/ballerina-platform/module-ballerina-mcp/tree/main/examples/servers/mcp-calendar-connect-server

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
    remote isolated function onListTools() returns mcp:ToolPage|mcp:ServerError {
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
            returns mcp:ToolResult|mcp:InputRequiredResult|mcp:ServerError {
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
continuation. Both handlers can bind the same HTTP request values as basic tools (`http:Headers`, `http:Request`,
`@http:Header` and `mcp:AuthContext`). `onCallTool` reads request metadata from `CallToolParams._meta`.

A handler returns an `mcp:InvalidParamsError` to reject the request's parameters, such as an unknown cursor or a
missing argument. The service answers with a JSON-RPC `INVALID_PARAMS` error carrying the error's message, on both
protocols. Any other `mcp:ServerError` is answered with `INTERNAL_ERROR` and its message.

`onListTools` may declare an `mcp:Cursor?` parameter to return its tools in pages. It receives the request's cursor,
or `()` for the first page, and sets `nextCursor` on every page but the last. A basic service always returns all of
its tools in one page. A modern `tools/call` reads at most 100 pages to find the called tool.

```ballerina
remote isolated function onListTools(mcp:Cursor? cursor) returns mcp:ToolPage|mcp:ServerError {
    if cursor is () {
        return {tools: firstPage, nextCursor: "page-2"};
    }
    if cursor == "page-2" {
        return {tools: secondPage};
    }
    return error mcp:InvalidParamsError("Unknown cursor");
}
```

### Eliciting input from an advanced service

On the modern protocol, `onCallTool` can ask the user for input by returning an `InputRequiredResult` with
elicitations. The client answers them and retries the call as a continuation, which carries the answers in
`inputResponses` and echoes `requestState`. The handler runs again from the top, so work done before it decides
to ask is repeated on every round.

```ballerina
remote isolated function onCallTool(mcp:CallToolParams params)
        returns mcp:ToolResult|mcp:InputRequiredResult|mcp:ServerError {
    mcp:ElicitResult? answer = (params.inputResponses ?: {})["confirm"];
    if answer is () {
        return {
            inputRequests: {
                "confirm": {
                    params: {
                        message: "Delete the repository?",
                        requestedSchema: {
                            properties: {confirmed: {'type: "boolean", description: "Confirm deletion"}},
                            required: ["confirmed"]
                        }
                    }
                }
            }
        };
    }
    boolean confirmed = answer.action == "accept" && (answer.content ?: {})["confirmed"] == true;
    return {resultType: "complete", content: [{'type: "text", text: confirmed ? "Deleted" : "Kept"}]};
}
```

A form schema is a flat object whose fields are string, number or integer, boolean, single-select enum (`enum`,
or `oneOf` with titles) and multi-select enum (`items.enum`, or `items.anyOf` with titles) schemas. Elicitations
use form mode by default; set `mode: "url"` with a `url` to send the user to an out-of-band page. The
`mcp:elicitForm` and `mcp:elicitUrl` builders also work here. The older single-select shape with labels in
`enumNames` is rejected; use `oneOf` with titles instead. The client still accepts it from other servers.

Before sending an input-required result, the service checks it:

- A result with neither `inputRequests` nor `requestState` is rejected with JSON-RPC `-32603`.
- A form elicitation with a blank `message`, a `required` field missing from `properties`, inverted or negative
  bounds, an empty enum or a default outside the enum is rejected with `-32603`.
- A URL elicitation with a blank `message`, or a `url` that is not absolute (a scheme and a host), is rejected
  with `-32603`. `http` URLs are allowed.
- An elicitation in a mode the client did not declare is rejected with the missing-capability error, whose
  `requiredCapabilities` names the mode. A client that declares an empty `elicitation` capability supports form.

`inputRequests` and `inputResponses` hold `mcp:InputRequest` and `mcp:InputResponse` values. Elicitation is the only
kind of input request, so these are `mcp:ElicitRequest` and `mcp:ElicitResult`.

On a legacy call, `onCallTool` receives neither `inputResponses` nor `requestState`.

### Request state

The service signs every request state a handler returns (HMAC-SHA256) and verifies it on the continuation before
the handler runs, so handlers only ever see the plain text they returned. The signature binds the state to:

- the tool name and the arguments of the call, regardless of key order;
- the caller's `mcp:AuthContext` (its issuer, client and subject), or to having no auth context;
- an expiry, renewed on every round.

A continuation whose state is malformed, tampered with, expired, or issued for another call or caller is rejected
with JSON-RPC `-32602` "Invalid or expired requestState" and `data.reason` `invalid_request_state`. The specific
reason is logged at debug level on the server only.

Request state is signed, not encrypted: the client can read it, so do not put secrets in it.

Configure signing with `requestState` on `@mcp:StreamableHttpServiceConfig`:

```ballerina
configurable string requestStateKey = ?;
configurable string previousRequestStateKey = ?;

@mcp:StreamableHttpServiceConfig {
    info: {name: "files", version: "1.0.0"},
    requestState: {keys: [requestStateKey, previousRequestStateKey], ttl: 300}
}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9090) {
}
```

- `keys` are secrets of at least 32 bytes. The first signs and all verify, so rotate a key by putting its
  replacement first and removing the old key once its state has expired.
- `ttl` is how long, in seconds, a request state stays valid (default 600). It bounds the idle time of each round,
  not the length of a whole flow.

Services that share `keys` accept each other's request state for the same tool, arguments and caller, so give
unrelated services their own keys. Without `keys`, each service generates a random key of its own when it is
attached. Its state does not survive a restart and is not accepted by other services or replicas, so deployments with
more than one replica must configure the same `keys` on each.
Invalid keys or a non-positive `ttl` fail when the service is attached.

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
`listTools()` or `callTool()`.

```ballerina
import ballerina/io;
import ballerina/mcp;

public function main() returns error? {
    final mcp:StreamableHttpClient2 client = check new (
        "http://localhost:9090/mcp",
        protocolMode = "auto"
    );

    mcp:ConnectionInfo connection = check client->connect({name: "example-client", version: "2.0.0"});
    io:println("Using MCP ", connection.protocolVersion);

    mcp:ToolPage listed = check client->listTools();
    mcp:ToolResult result = check client->callTool({
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

final mcp:StreamableHttpClient2 client = check new (
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
`elicitationHandler` once for each input request, one at a time and in the order the server listed them. It then
echoes the opaque request state and continues until the call completes or `maxInputRounds` is reached.

```ballerina
mcp:StreamableHttpClientConfig config = {
    protocolMode: "auto",
    maxInputRounds: 4,
    elicitationHandler: isolated function (mcp:ElicitRequest request)
            returns mcp:ElicitResult|mcp:ClientError {
        mcp:FormElicitationParams|mcp:UrlElicitationParams params = request.params;
        if params is mcp:UrlElicitationParams {
            return {action: "decline"};
        }
        return {action: "accept", content: {confirmed: true}};
    },
    httpConfig: {timeout: 30}
};
final mcp:StreamableHttpClient2 client = check new ("http://localhost:9090/mcp", config);
```

HTTP settings go under `httpConfig`, an `mcp:HttpClientConfig` with the fields and defaults of
`http:ClientConfiguration`, except that `auth` also accepts `mcp:OAuth2DiscoveryConfig`. With
`mcp:OAuth2DiscoveryConfig`, redirects are not followed and `init` returns an error if `followRedirects` enables them;
the metadata and token endpoint requests reuse `secureSocket` and `proxy`.

Configuring `elicitationHandler` advertises the `elicitation` capability with form and URL modes on every modern
request, merged with the capabilities passed to `connect()`. The client does not validate answers against the
form schema; the handler is responsible for that. Before a continuation, it removes `content` from URL-mode answers
and from any decline or cancel answer, so only an accepted form sends what the user submitted.

The module never opens, fetches or follows the URL of a URL elicitation; the handler presents it. A handler should:

- show the full URL, with its domain highlighted, and warn about suspicious ones such as Punycode domains;
- open the URL only after the user explicitly agrees, and never fetch it beforehand;
- open it in the system browser or another context that the client and the model cannot inspect;
- return `accept` once the user agrees to open it, without waiting for them to finish. The server asks again until
  the out-of-band step is done, so return `cancel` when the user gives up.

Use `callToolOnce()` when the application needs to handle each continuation itself. It returns
`ToolResult|InputRequiredResult` after one logical request. On a legacy connection it delegates to
`callTool()`, because legacy MCP has no input-required continuation result.

The lower-level lifecycle methods are available for applications that manage discovery themselves:

- `discover()` fetches modern discovery data without connecting the client.
- `adoptDiscovery()` connects from a previously obtained `DiscoverResult`.
- `initializeLegacy()` explicitly performs the older initialize handshake.

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

An advanced service may also set `ttlMs` or `cacheScope` on the `ToolPage` returned by `onListTools`; each
field set there takes precedence over the configured hint. A negative configured `ttlMs` fails `attach`, while a
negative `ttlMs` from `onListTools` is sent as `0` and logged as an error. Hints are only sent to modern clients.

The client reuses a `tools/list` result while it is fresh, caching each page by its cursor. Each client keeps its own
cache and represents a single authorization context: configure credentials through `httpConfig.auth`, and use a
separate client for each user rather than passing different credentials as per-call headers. A call that passes its own
`Authorization` header bypasses the cache. Cached results are dropped when:

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
| `subscribeToServerMessages()` | Removed |

1.x did not validate `Origin`. A 2.0 service rejects browser requests from origins that are not listed in
`httpConfig.cors.allowOrigins`, which is empty by default.

The client must now call `connect()`, or `initializeLegacy()`, before other operations; 1.x did not enforce
`initialize()`.

2.0 does not support change notifications. `subscribeToServerMessages()` has no replacement, a modern service answers
`subscriptions/listen` with `METHOD_NOT_FOUND`, and `tools.listChanged` is advertised as `false`. Proper support for
change notification subscriptions is planned for a later release.

A legacy client keeps receiving the legacy wire shapes from a 2.0 server. The text content of a tool that returns a
structured value is now its JSON serialization.

The `2025-11-25` task fields are removed: `CallToolParams.task`, `ToolInfo.execution` and the `tasks` client and
server capabilities. A client still connects to a server that advertises tasks.

The public error hierarchy is `mcp:Error`, `mcp:ClientError`, `mcp:TransportError`, `mcp:ProtocolError`,
`mcp:ToolCallError`, `mcp:StreamError`, and `mcp:ServerError` with `mcp:InvalidParamsError`; transport and decoder
implementation errors are internal.
