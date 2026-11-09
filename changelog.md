# Change Log
This file contains all the notable changes done to the Ballerina MCP package through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-11-09

### Added
- The `ballerina/mcp.v2` module, which supports MCP protocol version `2026-07-28`. Import it with `import ballerina/mcp.v2 as mcpv2;`. The root module keeps the 1.x API unchanged, so both can be used in one package. The v2 module's compiler diagnostics use their own codes, `MCP_2xx` and `MCP_WARNING_2xx`. Its documentation describes how to migrate from the 1.x API. The v2 module provides:
  - Support for MCP protocol version `2026-07-28`, which negotiates the protocol on each request instead of through the `initialize` handshake. The initialize-based revisions from `2024-10-07` to `2025-11-25` remain supported. Set `protocolMode` to `"auto"` (the default), `"modern"`, or `"legacy"` on the client or in `@mcpv2:StreamableHttpServiceConfig`. In `"auto"` mode a service accepts both kinds of request, and the client falls back to `initialize` only when the server's response indicates an older server. The revisions are listed in `mcpv2:MODERN_PROTOCOL_VERSIONS` and `mcpv2:LEGACY_PROTOCOL_VERSIONS`, and `mcpv2:SUPPORTED_PROTOCOL_VERSIONS` is their union.
  - Client connection methods. `connect()` selects the protocol, using the newest modern revision that `server/discover` lists, and returns an `mcpv2:ConnectionInfo`; concurrent first calls share one handshake. In `"auto"` mode it falls back to `initialize` when the list holds only legacy revisions, and returns an error when it holds no supported revision. `discover()`, `adoptDiscovery()`, and `initializeLegacy()` let applications manage discovery themselves. A `server/discover` result without `resultType`, `ttlMs`, or `cacheScope` is treated as `complete`, `0`, and `private`.
  - The `legacyInitialize` parameter of `connect()`. Set it to `false` to connect to a legacy server without the `initialize` handshake, so that no HTTP session is created. Such a connection sends no `MCP-Protocol-Version` header and reports version `2025-03-26` with empty server capabilities. In `"legacy"` mode `connect()` then makes no network call; it has no effect when a modern revision is selected or a session ID is supplied.
  - `adoptDiscovery()` returns an `mcpv2:ClientInitializationError` on a client in `"legacy"` protocol mode, including one given a session ID, so a discovery result cannot switch it to the modern protocol.
  - Input-required continuations for modern tool calls. `callTool()` passes each elicitation (`mcpv2:ElicitRequest`) to the configured `elicitationHandler` (`mcpv2:ElicitationHandler`), which also advertises the `elicitation` capability with form and URL modes, for at most `maxInputRounds` rounds (10 by default), and `callToolOnce()` returns an `mcpv2:InputRequiredResult` to the application instead. Continuations leave out `inputResponses` when nothing was asked, and state-only rounds are retried after a backoff of 50 ms doubling to 250 ms. `onCallTool` of an advanced service may return `mcpv2:InputRequiredResult` to a modern request; a legacy request gets an error instead, and `onCallTool` receives no `inputResponses` or `requestState` from it.
  - Typed form elicitation for MCP `2026-07-28` input-required results. `mcpv2:ElicitRequest` carries `mcpv2:FormElicitationParams` with an `mcpv2:FormSchema`, or `mcpv2:UrlElicitationParams`, and the service rejects empty input-required results and malformed form or URL elicitations with JSON-RPC `-32603`. The client also accepts the legacy `enumNames` single-select shape from other servers, which services cannot send. The client removes content from URL-mode, decline and cancel answers before a continuation.
  - Elicitation from basic services. A tool returns `T|mcpv2:InputRequiredResult`, builds elicitations with `mcpv2:elicitForm` and `mcpv2:elicitUrl`, and reads the answers on the continuation through an injected `mcpv2:Context` (`acceptedContent`, `elicitResult` and `requestState`). Legacy calls receive an empty context.
  - Form schemas generated from record types. `mcpv2:elicitForm` accepts a record type, and the compiler plugin generates its form schema at compile time, with field descriptions from doc comments. Fields a form schema cannot express, and record types not known at compile time, are compile errors.
  - Bounded legacy sessions. A session unused for `idleTimeout` seconds is evicted, and `initialize` evicts the least recently used session once a caller holds `maxPerOwner` sessions or anonymous callers hold `maxAnonymous` together. Configure the limits with the `sessionLimits` field of `@mcpv2:StreamableHttpServiceConfig`. Sessions belong to the caller that created them under both `mcpv2:OAuthProtectedResourceConfig` and `http:ListenerAuthConfig` authentication, where the owner is the Basic user name or the issuer, client and subject of a JWT.
  - Signed request state. The service signs the request state of input-required results with HMAC-SHA256, binding it to the tool name, the arguments, the caller's auth context and an expiry, and rejects invalid state with JSON-RPC `-32602` (`invalid_request_state`) before the handler runs. Configure signing keys and the expiry with the `requestState` field of `@mcpv2:StreamableHttpServiceConfig`.
  - Structured output for basic services on modern requests. The compiler generates an `outputSchema` from the return type, and `structuredContent` carries the return value with any JSON root. Set `outputSchema` on `@mcpv2:Tool` to override the schema, or `structuredOutput: false` to make a tool's output unstructured on both protocols. A return type with no JSON Schema (an object, `any`, `http:Response`) leaves the tool unstructured, as in the 1.x API, unless `structuredOutput: true` is set explicitly, which is a compilation error.
  - The `@mcpv2:Argument` annotation, which mirrors a `string`, `int`, or `boolean` tool argument into an `Mcp-Param-*` request header through the `x-mcp-header` schema extension. The client sends the headers and rejects an `int` argument outside ±(2<sup>53</sup>−1) with an `mcpv2:ToolCallError`, and the service answers a header that does not match its argument with `mcpv2:HEADER_MISMATCH`. Header names are compared case-insensitively. Only `string`, `integer` and `boolean` properties may carry `x-mcp-header`; the client leaves tools with invalid header declarations out of `listTools()`.
  - Paginated tool lists for advanced services. `onListTools` may declare an `mcpv2:Cursor?` parameter and return its tools in pages through `nextCursor`, on both protocols. A modern `tools/call` follows at most 100 pages to find the called tool. A handler returns `mcpv2:InvalidParamsError` to reject a cursor or other parameters with a JSON-RPC `INVALID_PARAMS` error carrying its message.
  - Client OAuth through an `mcpv2:OAuth2DiscoveryConfig` in `httpConfig.auth`: the authorization code (`mcpv2:AuthorizationCodeGrant`), client credentials (`mcpv2:ClientCredentialsGrant`), and enterprise-managed identity assertion (`mcpv2:IdentityAssertionGrant`, with `mcpv2:exchangeIdTokenForIdJag`) grants, for pre-registered clients and Client ID Metadata Documents. Clients authenticate with a client secret, a private key JWT, or mutual TLS (`tls_client_auth` and `self_signed_tls_client_auth`, RFC 8705), using the token endpoint alias in `mtls_endpoint_aliases` when published. OAuth failures are returned as `mcpv2:AuthorizationError` with the underlying reason in the message, and a rejected token request is reported as an `mcpv2:OAuthTokenError` in the cause chain.
  - Result caching for MCP `2026-07-28`. Services set `ttlMs` and `cacheScope` hints for `server/discover` and `tools/list` through the `cacheHints` field of `@mcpv2:StreamableHttpServiceConfig`, and the client reuses fresh `tools/list` results by default. Use the `resultCache` client configuration and the `cacheMode` parameter of `listTools()` to control reuse. A `ListToolsResult` from `onListTools` with a negative `ttlMs` is sent with `0`, and the error is logged.
  - Server-side authorization as an OAuth protected resource with an `mcpv2:OAuthProtectedResourceConfig` in `httpConfig.auth` of `@mcpv2:StreamableHttpServiceConfig`: protected resource metadata (RFC 9728), `WWW-Authenticate` challenges, audience-bound validation of JWT and introspected bearer tokens from one or more authorization servers, per-tool `scopes` on `@mcpv2:Tool`, scope hierarchies (`scopeHierarchy`), `mcpv2:InsufficientScopeError` for step-up, and the `mcpv2:AuthContext` parameter for the authenticated caller.
  - `Origin` validation. A service checks the `Origin` header of every request, on both protocols and before authentication, against `httpConfig.cors.allowOrigins`, and answers an origin that is not listed with `403 Forbidden`. A request without an `Origin` header is accepted.
  - The client skips SSE events without data, such as keep-alive comments and priming events, instead of ending the stream with an error.
  - On the legacy protocol, the client ignores the `resultType`, `ttlMs`, and `cacheScope` result fields of MCP `2026-07-28`, so a server that sends them with values outside that schema no longer fails the request.
  - A call to an unknown tool is answered with a JSON-RPC `INVALID_PARAMS` error on both protocols, as the specification shows. The root module still returns a tool result with `isError` set.

### Changed
- In the v2 module, `McpToolConfig.structuredOutput` is now `boolean?` with default `()`: automatic, required (`true`), or disabled (`false`). Configuration records, shorthand and spreads preserve the same policy as inline fields. Known invalid configurations report `MCP_221` or `MCP_222`; runtime configurations are validated before service attachment. These checks apply in auto/modern protocol modes; legacy-only basic services keep text-only output.

### Deprecated
- The `mcp:StreamableHttpClient` client, in favour of `mcpv2:StreamableHttpClient`.
- The transport-agnostic `mcp:Service` and `mcp:AdvancedService` service types and the `@mcp:ServiceConfig` annotation, in favour of `mcp:StreamableHttpService`, `mcp:StreamableHttpAdvancedService` and `@mcp:StreamableHttpServiceConfig`, or their `mcpv2` counterparts.

## [1.4.0] - 2026-10-13

### Changed
- Migrated to Ballerina Swan Lake Update 14 (`2201.14.0`), Java 25, and `ballerina/http` `2.18.0`. This fixes the `KeyNotFound` panic (`field 'http2MaxActiveStreams' not found in record type 'mcp:ListenerConfiguration'`) raised when initializing an `mcp:StreamableHttpListener` or `mcp:Listener` on Ballerina `2201.14.0`.
- [[#9132] Updated Keywords and Reformat README for Connector Store Discoverability](https://github.com/ballerina-platform/ballerina-library/issues/9132)

### Fixed
- [Defaultable tool parameter cannot be omitted in a tools/call request](https://github.com/ballerina-platform/ballerina-library/issues/9143)

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
- [Support for passing `mcp:Meta` to tool functions](https://github.com/ballerina-platform/module-ballerina-mcp/pull/36)
