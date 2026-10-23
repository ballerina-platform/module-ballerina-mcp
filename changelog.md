# Change Log
This file contains all the notable changes done to the Ballerina MCP package through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Support for MCP protocol version `2026-07-28`, which negotiates the protocol on each request instead of through the `initialize` handshake. The initialize-based revisions from `2024-10-07` to `2025-11-25` remain supported. Set `protocolMode` to `"auto"` (the default), `"modern"`, or `"legacy"` on `mcp:StreamableHttpClient2` or in `@mcp:StreamableHttpServiceConfig`. In `"auto"` mode a service accepts both kinds of request, so existing `mcp:StreamableHttpService` and `mcp:StreamableHttpAdvancedService` services answer modern clients without change, and the client falls back to `initialize` only when the server's response indicates an older server. The revisions are listed in `mcp:MODERN_PROTOCOL_VERSIONS` and `mcp:LEGACY_PROTOCOL_VERSIONS`, with `mcp:LATEST_MODERN_PROTOCOL_VERSION` and `mcp:LATEST_LEGACY_PROTOCOL_VERSION`; `mcp:LATEST_PROTOCOL_VERSION` and `mcp:SUPPORTED_PROTOCOL_VERSIONS` keep their 1.x values.
- `mcp:StreamableHttpClient2`, a client for both protocol generations, configured with `mcp:StreamableHttpClientConfig` (HTTP settings under `httpConfig`, an `mcp:HttpClientConfig`). `listTools()` returns `mcp:ToolPage` with `mcp:ToolInfo` entries and `callTool()` returns `mcp:ToolResult` on both protocols; these types can hold output schemas and structured content of any JSON root, which `mcp:ListToolsResult`, `mcp:ToolDefinition` and `mcp:CallToolResult` cannot. The client never sends `task`. `connect()` selects the protocol, using the newest modern revision that `server/discover` lists, and returns an `mcp:ConnectionInfo`; concurrent first calls share one handshake. In `"auto"` mode it falls back to `initialize` when the list holds only legacy revisions, and returns an error when it holds no supported revision. `discover()`, `adoptDiscovery()`, and `initializeLegacy()` let applications manage discovery themselves. A `server/discover` result without `resultType`, `ttlMs`, or `cacheScope` is treated as `complete`, `0`, and `private`.
- Input-required continuations for modern tool calls. `callTool()` passes each elicitation (`mcp:ElicitRequest`) to the configured `elicitationHandler` (`mcp:ElicitationHandler`), which also advertises the `elicitation` capability with form and URL modes, for at most `maxInputRounds` rounds (10 by default), and `callToolOnce()` returns an `mcp:InputRequiredResult` to the application instead. Continuations leave out `inputResponses` when nothing was asked, and state-only rounds are retried after a backoff of 50 ms doubling to 250 ms. `onCallTool` of an advanced service may return `mcp:InputRequiredResult` to a modern request; a legacy request gets an error instead, and `onCallTool` receives no `inputResponses` or `requestState` from it.
- Typed form elicitation for MCP `2026-07-28` input-required results. `mcp:ElicitRequest` carries `mcp:FormElicitationParams` with an `mcp:FormSchema`, or `mcp:UrlElicitationParams`, and the service rejects empty input-required results and malformed form or URL elicitations with JSON-RPC `-32603`. The client also accepts the legacy `enumNames` single-select shape from other servers, which services cannot send. The client removes content from URL-mode, decline and cancel answers before a continuation.
- Elicitation from basic services. A tool returns `T|mcp:InputRequiredResult`, builds elicitations with `mcp:elicitForm` and `mcp:elicitUrl`, and reads the answers on the continuation through an injected `mcp:Context` (`acceptedContent`, `elicitResult` and `requestState`). Legacy calls receive an empty context.
- Form schemas generated from record types. `mcp:elicitForm` accepts a record type, and the compiler plugin generates its form schema at compile time, with field descriptions from doc comments. Fields a form schema cannot express, and record types not known at compile time, are compile errors.
- Signed request state. The service signs the request state of input-required results with HMAC-SHA256, binding it to the tool name, the arguments, the caller's auth context and an expiry, and rejects invalid state with JSON-RPC `-32602` (`invalid_request_state`) before the handler runs. Configure signing keys and the expiry with the `requestState` field of `@mcp:StreamableHttpServiceConfig`.
- Structured output for basic services on modern requests. The compiler generates an `outputSchema` from the return type, and `structuredContent` carries the return value with any JSON root. Set `outputSchema` on `@mcp:Tool` to override the schema, or `structuredOutput: false` to make a tool's output unstructured on both protocols. A return type with no JSON Schema (an object, `any`, `http:Response`) leaves the tool unstructured, as in 1.4.0, unless `structuredOutput: true` is set explicitly, which is a compilation error.
- The `@mcp:Argument` annotation, which mirrors a `string`, `int`, or `boolean` tool argument into an `Mcp-Param-*` request header through the `x-mcp-header` schema extension. The client sends the headers and rejects an `int` argument outside ±(2<sup>53</sup>−1) with an `mcp:ToolCallError`, and the service answers a header that does not match its argument with `mcp:HEADER_MISMATCH`. Header names are compared case-insensitively. Only `string`, `integer` and `boolean` properties may carry `x-mcp-header`; the client leaves tools with invalid header declarations out of `listTools()`.
- Paginated tool lists for advanced services. `onListTools` may declare an `mcp:Cursor?` parameter and return its tools in pages through `nextCursor`, on both protocols. A modern `tools/call` follows at most 100 pages to find the called tool. A handler returns `mcp:InvalidParamsError` to reject a cursor or other parameters with a JSON-RPC `INVALID_PARAMS` error carrying its message.
- Client OAuth through an `mcp:OAuth2DiscoveryConfig` in `httpConfig.auth`: the authorization code (`mcp:AuthorizationCodeGrant`), client credentials (`mcp:ClientCredentialsGrant`), and enterprise-managed identity assertion (`mcp:IdentityAssertionGrant`, with `mcp:exchangeIdTokenForIdJag`) grants, for pre-registered clients and Client ID Metadata Documents. Clients authenticate with a client secret, a private key JWT, or mutual TLS (`tls_client_auth` and `self_signed_tls_client_auth`, RFC 8705), using the token endpoint alias in `mtls_endpoint_aliases` when published. OAuth failures are returned as `mcp:AuthorizationError` with the underlying reason in the message, and a rejected token request is reported as an `mcp:OAuthTokenError` in the cause chain.
- Result caching for MCP `2026-07-28`. Services set `ttlMs` and `cacheScope` hints for `server/discover` and `tools/list` through the `cacheHints` field of `@mcp:StreamableHttpServiceConfig`, and the client reuses fresh `tools/list` results by default. Use the `resultCache` client configuration and the `cacheMode` parameter of `listTools()` to control reuse. A `ToolPage` or `ListToolsResult` from `onListTools` with a negative `ttlMs` is sent with `0`, and the error is logged.
- Server-side authorization as an OAuth protected resource with an `mcp:OAuthProtectedResourceConfig` in `httpConfig.auth` of `@mcp:StreamableHttpServiceConfig`: protected resource metadata (RFC 9728), `WWW-Authenticate` challenges, audience-bound validation of JWT and introspected bearer tokens from one or more authorization servers, per-tool `scopes` on `@mcp:Tool`, scope hierarchies (`scopeHierarchy`), `mcp:InsufficientScopeError` for step-up, and the `mcp:AuthContext` parameter for the authenticated caller.
- Advanced services may return `mcp:ToolResult` and `mcp:InputRequiredResult` from `onCallTool` and `mcp:ToolPage` from `onListTools`, next to the 1.x `mcp:CallToolResult` and `mcp:ListToolsResult`, which legacy clients receive exactly as returned.
- `inputResponses` and `requestState` in `mcp:CallToolParams`, and `extensions` in `mcp:ClientCapabilities` and `mcp:ServerCapabilities`.
- `outputSchema`, `structuredOutput` and `scopes` in `@mcp:Tool`, and `protocolMode`, `cacheHints` and `requestState` in `@mcp:StreamableHttpServiceConfig`, whose `httpConfig` is now an `mcp:HttpServiceConfig`: the fields of `http:HttpServiceConfig`, with `auth` also accepting `mcp:OAuthProtectedResourceConfig`.
- `mcp:InvalidParamsError`, which an advanced service returns for a JSON-RPC `INVALID_PARAMS` error. `mcp:ParameterBindingError` is now one.
- `mcp:AuthorizationError`, `mcp:OAuthTokenError` and `mcp:InsufficientScopeError`.
- The compiler plugin recognises services, listeners and annotations of an aliased import (`import ballerina/mcp as m;`), and generates the `@Tool` annotation with that prefix.

### Changed
- An `mcp:Session` parameter may be declared at any position of a tool, and a second one is reported as a duplicate parameter (MCP_107); MCP_103 is no longer reported. Since modern requests are sessionless, the compiler reports a required `mcp:Session` in `"modern"` mode (MCP_114) and warns about it in `"auto"` mode (MCP_WARNING_102), where the service serves it to legacy requests only; an optional `mcp:Session?` is `()` on modern requests (MCP_WARNING_103, MCP_WARNING_104).
- Changes on the legacy wire, which otherwise answers as in 1.4.0:
  - `Origin` is validated on every request, before authentication. When `httpConfig.cors.allowOrigins` is empty, loopback origins (`http` or `https` with host `localhost`, `127.0.0.1` or `[::1]`, on any port) are accepted; when it is set, only the listed origins are. Any other origin gets `403 Forbidden`. A request without an `Origin` header is accepted.
  - A `task` field on `tools/call` is ignored instead of rejected with `-32600`.
  - A tool that returns `()` produces `content: []` instead of a text block with an empty string.
  - A tool that returns a non-string value gets its JSON serialization as text, so an xml value becomes a quoted JSON string.
  - A non-string `cursor` on `tools/list` gets `-32602 "Invalid cursor"`, and a wrongly typed `requestState` or `inputResponses` on `tools/call` gets `-32602`.
  - The `initialize` result includes `options.instructions` when the service configures it.
  - `DELETE` with a modern `MCP-Protocol-Version` header gets `405` from an `mcp:StreamableHttpService` or `mcp:StreamableHttpAdvancedService`.

### Deprecated
- `mcp:StreamableHttpClient`, which speaks only the legacy protocol. Use `mcp:StreamableHttpClient2`.
- The transport-neutral `mcp:Listener`, `mcp:Service`, `mcp:AdvancedService`, `mcp:ServiceConfiguration` and `@mcp:ServiceConfig`, which keep their 1.4.0 behaviour on the legacy protocol only. Use `mcp:StreamableHttpListener`, `mcp:StreamableHttpService`, `mcp:StreamableHttpAdvancedService` and `@mcp:StreamableHttpServiceConfig`. The compiler warns on services of the two transport-neutral types (MCP_WARNING_105).

### Fixed
- `mcp:StreamableHttpClient` skips SSE events without data, such as keep-alive comments and priming events, instead of ending the stream with an error.

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
