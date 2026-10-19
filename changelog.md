# Change Log
This file contains all the notable changes done to the Ballerina MCP package through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- [[#9132] Updated Keywords and Reformat README for Connector Store Discoverability](https://github.com/ballerina-platform/ballerina-library/issues/9132)

### Added
- [Transport-specific MCP service types with access to HTTP headers and the raw request](https://github.com/ballerina-platform/ballerina-library/issues/8808)
- Mutual TLS client authentication (`tls_client_auth` and `self_signed_tls_client_auth`, RFC 8705) for client OAuth, including Client ID Metadata Document clients. The token endpoint alias in `mtls_endpoint_aliases` is used when published.
- Result caching for MCP `2026-07-28`. Services set `ttlMs` and `cacheScope` hints for `server/discover` and `tools/list` through the `cacheHints` field of `@mcp:StreamableHttpConfig`, and the client reuses fresh `tools/list` results by default. Use the `resultCache` client configuration and the `cacheMode` parameter of `listTools()` to control reuse.
- Server-side authorization as an OAuth protected resource with an `mcp:OAuthProtectedResourceConfig` in `httpConfig.auth` of `@mcp:StreamableHttpConfig`: protected resource metadata (RFC 9728), `WWW-Authenticate` challenges, audience-bound validation of JWT and introspected bearer tokens from one or more authorization servers, per-tool `scopes` on `@mcp:Tool`, scope hierarchies (`scopeHierarchy`), `mcp:InsufficientScopeError` for step-up, and the `mcp:AuthContext` parameter for the authenticated caller.
- Typed form elicitation for MCP `2026-07-28` input-required results. `mcp:InputRequest` carries `mcp:FormElicitationParams` with an `mcp:FormSchema`, or `mcp:UrlElicitationParams`, and the service rejects empty input-required results and malformed form or URL elicitations with JSON-RPC `-32603`. The client removes content from URL-mode, decline and cancel answers before a continuation.
- Elicitation from basic services. A tool returns `T|mcp:InputRequiredResult`, builds elicitations with `mcp:elicitForm` and `mcp:elicitUrl`, and reads the answers on the continuation through an injected `mcp:Context` (`acceptedContent`, `elicitResult` and `requestState`). Legacy calls receive an empty context.

### Changed
- [Relaxed the requirement for the `mcp:Meta?` parameter of a tool function to be declared last](https://github.com/ballerina-platform/ballerina-library/issues/8972)
- `httpConfig` of `@mcp:StreamableHttpConfig` is now an `mcp:HttpServiceConfig`, which has the fields of `http:HttpServiceConfig` and whose `auth` also accepts `mcp:OAuthProtectedResourceConfig`. Existing `httpConfig` settings, including `auth: [...]`, are unchanged.
- The client's `inputHandler` is replaced by a typed `elicitationHandler` (`mcp:ElicitationHandler`), which also advertises the `elicitation` capability with form and URL modes. `mcp:InputRequest` and `mcp:InputResponse` now model elicitation only; sampling and roots input requests are removed.
- `maxInputRounds` of the client now defaults to 10 instead of 8. `callTool` continuations leave out `inputResponses` when nothing was asked, and retry state-only rounds after a backoff of 50 ms doubling to 250 ms.

### Deprecated
- The `mcp:Listener` class, in favour of `mcp:StreamableHttpListener`.
- The `httpConfig` and `sessionMode` fields of the `@mcp:ServiceConfig` annotation, in favour of the corresponding fields of `@mcp:StreamableHttpServiceConfig`.

### Fixed
- [Service methods are dropped when a service shares a document with an MCP tool](https://github.com/ballerina-platform/ballerina-library/issues/8971)
- Client OAuth failures are returned as `mcp:AuthorizationError` with the underlying reason in the message, instead of a generic transport error.
- A `server/discover` result without `resultType`, `ttlMs`, or `cacheScope` is treated as `complete`, `0`, and `private`, so the `auto` protocol mode no longer falls back to `initialize` for a modern server that omits them.

## [1.1.0] - 2026-07-02

### Added
- Partial support for MCP protocol version `2025-11-25`, with backward compatibility for `2025-06-18`, `2025-03-26`, and `2024-11-05`. Task-augmented requests introduced in `2025-11-25` are not yet supported.
