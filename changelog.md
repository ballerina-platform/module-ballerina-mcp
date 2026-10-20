# Change Log
This file contains all the notable changes done to the Ballerina MCP package through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Support for MCP protocol version `2026-07-28`, which negotiates the protocol on each request instead of through the `initialize` handshake. The initialize-based revisions from `2024-10-07` to `2025-11-25` remain supported. Set `protocolMode` to `"auto"` (the default), `"modern"`, or `"legacy"` on the client or in `@mcp:StreamableHttpServiceConfig`. In `"auto"` mode a service accepts both kinds of request, and the client falls back to `initialize` only when the server's response indicates an older server. The revisions are listed in `mcp:MODERN_PROTOCOL_VERSIONS` and `mcp:LEGACY_PROTOCOL_VERSIONS`, and `mcp:SUPPORTED_PROTOCOL_VERSIONS` is their union.
- Client connection methods. `connect()` selects the protocol, using the newest modern revision that `server/discover` lists, and returns an `mcp:ConnectionInfo`; concurrent first calls share one handshake. `discover()`, `adoptDiscovery()`, and `initializeLegacy()` let applications manage discovery themselves. A `server/discover` result without `resultType`, `ttlMs`, or `cacheScope` is treated as `complete`, `0`, and `private`.
- Input-required continuations for modern tool calls. `callTool()` passes each `mcp:InputRequest` to the configured `inputHandler`, for at most `maxInputRounds` rounds, and `callToolOnce()` returns an `mcp:InputRequiredResult` to the application instead. `onCallTool` of an advanced service may return `mcp:InputRequiredResult` to a modern request.
- Structured output for basic services on modern requests. The compiler generates an `outputSchema` from the return type, and `structuredContent` carries the return value with any JSON root. Set `outputSchema` on `@mcp:Tool` to override the schema, or `structuredOutput: false` to make a tool's output unstructured on both protocols.
- The `@mcp:Argument` annotation, which mirrors a `string`, `int`, or `boolean` tool argument into an `Mcp-Param-*` request header through the `x-mcp-header` schema extension. The client sends the headers and rejects an `int` argument outside ±(2<sup>53</sup>−1) with an `mcp:ToolCallError`, and the service answers a header that does not match its argument with `mcp:HEADER_MISMATCH`. Header names are compared case-insensitively.
- Change notification subscriptions for modern connections. The client's `listen()` takes an `mcp:SubscriptionFilter`, and an advanced service may implement `onSubscribe` to return a stream of `mcp:JsonRpcNotification` values. `onSubscribe` binds `http:Headers`, `http:Request`, `@http:Header` parameters, and `mcp:AuthContext` from the `subscriptions/listen` request. While a subscription is open, the service sends an SSE keep-alive comment every 15 seconds. When the client disconnects, the stream returned by `onSubscribe` is closed, and `gracefulStop()` ends every open subscription with its `complete` result, waiting at most 5 seconds.
- Paginated tool lists for advanced services. `onListTools` may declare an `mcp:Cursor?` parameter and return its tools in pages through `nextCursor`, on both protocols. A modern `tools/call` follows the pages to find the called tool.
- Client OAuth through an `mcp:OAuthConfig` in `httpConfig.auth`: the authorization code (`mcp:AuthorizationCodeGrant`), client credentials (`mcp:ClientCredentialsGrant`), and enterprise-managed identity assertion (`mcp:IdentityAssertionGrant`, with `mcp:exchangeIdTokenForIdJag`) grants, for pre-registered clients and Client ID Metadata Documents. Clients authenticate with a client secret, a private key JWT, or mutual TLS (`tls_client_auth` and `self_signed_tls_client_auth`, RFC 8705), using the token endpoint alias in `mtls_endpoint_aliases` when published. OAuth failures are returned as `mcp:AuthorizationError` with the underlying reason in the message, and a rejected token request is reported as an `mcp:OAuthTokenError` in the cause chain.
- Result caching for MCP `2026-07-28`. Services set `ttlMs` and `cacheScope` hints for `server/discover` and `tools/list` through the `cacheHints` field of `@mcp:StreamableHttpServiceConfig`, and the client reuses fresh `tools/list` results by default. Use the `resultCache` client configuration and the `cacheMode` parameter of `listTools()` to control reuse. A `ListToolsResult` from `onListTools` with a negative `ttlMs` is sent with `0`, and the error is logged.
- Server-side authorization as an OAuth protected resource with an `mcp:OAuthProtectedResourceConfig` in `httpConfig.auth` of `@mcp:StreamableHttpServiceConfig`: protected resource metadata (RFC 9728), `WWW-Authenticate` challenges, audience-bound validation of JWT and introspected bearer tokens from one or more authorization servers, per-tool `scopes` on `@mcp:Tool`, scope hierarchies (`scopeHierarchy`), `mcp:InsufficientScopeError` for step-up, and the `mcp:AuthContext` parameter for the authenticated caller.
- `Origin` validation. A service checks the `Origin` header of every request, on both protocols and before authentication, against `httpConfig.cors.allowOrigins`, and answers an origin that is not listed with `403 Forbidden`. A request without an `Origin` header is accepted.

### Changed
- [[#9132] Updated Keywords and Reformat README for Connector Store Discoverability](https://github.com/ballerina-platform/ballerina-library/issues/9132)
- Renamed the public API after the Streamable HTTP transport: `mcp:Session` and `mcp:SessionEntry` to `mcp:HttpSession` and `mcp:HttpSessionEntry`, `mcp:SessionMode` to `mcp:HttpSessionMode`, `mcp:Meta` to `mcp:RequestMeta`, `mcp:StreamableHttpClientTransportConfig` to `mcp:StreamableHttpClientConfig`, `initialize()` to `connect()` or `initializeLegacy()`, and `subscribeToServerMessages()` to `listen()`.
- The client must call `connect()` or `initializeLegacy()` before `listTools()`, `callTool()`, or `listen()`. 1.x did not enforce `initialize()`.
- HTTP client settings move from the top level of the client configuration into `httpConfig`, an `mcp:HttpClientConfig` with the fields of `http:ClientConfiguration` whose `auth` also accepts `mcp:OAuthConfig`. For example, `timeout = 60` becomes `httpConfig = {timeout: 60}`. With `mcp:OAuthConfig`, redirects are not followed, and the authorization requests reuse `secureSocket` and `proxy`.
- `httpConfig` of `@mcp:StreamableHttpServiceConfig` is now an `mcp:HttpServiceConfig`, which has the fields of `http:HttpServiceConfig` and whose `auth` also accepts `mcp:OAuthProtectedResourceConfig`. Existing `httpConfig` settings, including `auth: [...]`, are unchanged.
- An `mcp:HttpSession` parameter may be declared at any position of a tool, and a second one is reported as a duplicate parameter. Since modern requests are sessionless, the compiler reports a required `mcp:HttpSession` parameter in `"modern"` mode and warns about it in `"auto"` mode, where the service serves it to legacy requests only.
- The text content of a tool result follows the return value: a `string` is used as is, `()` produces no content block, and any other value becomes its JSON serialization. Legacy requests otherwise keep the 1.x wire shape: basic tools advertise no `outputSchema` and return no `structuredContent`, and an advanced service's `outputSchema` or `structuredContent` whose root is not an object is removed.
- Tool failures are mapped the same way on both protocols. An HTTP request value that cannot be bound to a parameter is a JSON-RPC `INVALID_PARAMS` error. An advanced service method that returns an `mcp:ServerError` gets a JSON-RPC error with its message, and one that returns another error or panics gets an `INTERNAL_ERROR` with a generic message.
- The public error hierarchy is `mcp:Error`, `mcp:ClientError`, `mcp:TransportError`, `mcp:ProtocolError`, `mcp:ToolCallError`, `mcp:StreamError`, and `mcp:ServerError`, with `mcp:InsufficientScopeError`, `mcp:AuthorizationError`, and `mcp:OAuthTokenError` for authorization. The transport and decoder error types of 1.x, such as `mcp:ServerResponseError` and `mcp:MissingSseDataError`, are internal.

### Removed
- The transport-neutral `mcp:Listener`, `mcp:Service`, `mcp:AdvancedService`, and `@mcp:ServiceConfig`, in favour of `mcp:StreamableHttpListener`, `mcp:StreamableHttpService`, `mcp:StreamableHttpAdvancedService`, and `@mcp:StreamableHttpServiceConfig`.
- The `2025-11-25` task fields: `CallToolParams.task`, `ToolDefinition.execution` with the `mcp:ToolExecution` and `mcp:TaskSupport` types, and the `tasks` client and server capabilities. A service ignores a `task` field on `tools/call`, and a client still connects to a server that advertises tasks.

### Fixed
- [Defaultable tool parameter cannot be omitted in a tools/call request](https://github.com/ballerina-platform/ballerina-library/issues/9143)
- The client skips SSE events without data, such as keep-alive comments and priming events, instead of ending the stream with an error.

## [1.3.0] - 2026-09-07

### Added
- [Consolidate Service Endpoint Definitions into a Single `endpoints.yaml` File](https://github.com/ballerina-platform/ballerina-library/issues/8782)

### Changed
- JSON-RPC error responses are now sent with spec-compliant HTTP statuses: errors answering a request use `200 OK` so that clients parse the JSON-RPC envelope, malformed bodies use `400 Bad Request`, and an unknown or terminated session uses `404 Not Found` so that clients re-initialize.

### Fixed
- [Invalid tool arguments terminate the `ballerina/mcp` server process](https://github.com/ballerina-platform/ballerina-library/issues/9116)
- [`ballerina/mcp` does not report tool execution errors per the MCP specification](https://github.com/ballerina-platform/ballerina-library/issues/9117)

## [1.2.0] - 2026-07-31

### Added
- [Transport-specific MCP service types with access to HTTP headers and the raw request](https://github.com/ballerina-platform/ballerina-library/issues/8808)

### Changed
- [Relaxed the requirement for the `mcp:Meta?` parameter of a tool function to be declared last](https://github.com/ballerina-platform/ballerina-library/issues/8972)

### Deprecated
- The `mcp:Listener` class, in favour of `mcp:StreamableHttpListener`.
- The `httpConfig` and `sessionMode` fields of the `@mcp:ServiceConfig` annotation, in favour of the corresponding fields of `@mcp:StreamableHttpServiceConfig`.

### Fixed
- [Fix MCP client failing to decode `icons` that follow the MCP `2025-11-25` spec](https://github.com/wso2/product-integrator/issues/2659)
- [Service methods are dropped when a service shares a document with an MCP tool](https://github.com/ballerina-platform/ballerina-library/issues/8971)

## [1.1.0] - 2026-07-02

### Added
- Partial support for MCP protocol version `2025-11-25`, with backward compatibility for `2025-06-18`, `2025-03-26`, and `2024-11-05`. Task-augmented requests introduced in `2025-11-25` are not yet supported.
