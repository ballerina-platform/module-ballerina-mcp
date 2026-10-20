# Change Log
This file contains all the notable changes done to the Ballerina MCP package through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Mutual TLS client authentication (`tls_client_auth` and `self_signed_tls_client_auth`, RFC 8705) for client OAuth, including Client ID Metadata Document clients. The token endpoint alias in `mtls_endpoint_aliases` is used when published.
- Result caching for MCP `2026-07-28`. Services set `ttlMs` and `cacheScope` hints for `server/discover` and `tools/list` through the `cacheHints` field of `@mcp:StreamableHttpConfig`, and the client reuses fresh `tools/list` results by default. Use the `resultCache` client configuration and the `cacheMode` parameter of `listTools()` to control reuse.
- Server-side authorization as an OAuth protected resource with an `mcp:OAuthProtectedResourceConfig` in `httpConfig.auth` of `@mcp:StreamableHttpConfig`: protected resource metadata (RFC 9728), `WWW-Authenticate` challenges, audience-bound validation of JWT and introspected bearer tokens from one or more authorization servers, per-tool `scopes` on `@mcp:Tool`, scope hierarchies (`scopeHierarchy`), `mcp:InsufficientScopeError` for step-up, and the `mcp:AuthContext` parameter for the authenticated caller.

### Changed
- Migrated to Ballerina Swan Lake Update 14 (`2201.14.0`), Java 25, and `ballerina/http` `2.18.0`. This fixes the `KeyNotFound` panic (`field 'http2MaxActiveStreams' not found in record type 'mcp:ListenerConfiguration'`) raised when initializing an `mcp:StreamableHttpListener` or `mcp:Listener` on Ballerina `2201.14.0`.
- [[#9132] Updated Keywords and Reformat README for Connector Store Discoverability](https://github.com/ballerina-platform/ballerina-library/issues/9132)
- `httpConfig` of `@mcp:StreamableHttpConfig` is now an `mcp:HttpServiceConfig`, which has the fields of `http:HttpServiceConfig` and whose `auth` also accepts `mcp:OAuthProtectedResourceConfig`. Existing `httpConfig` settings, including `auth: [...]`, are unchanged.

### Fixed
- [Defaultable tool parameter cannot be omitted in a tools/call request](https://github.com/ballerina-platform/ballerina-library/issues/9143)
- Client OAuth failures are returned as `mcp:AuthorizationError` with the underlying reason in the message, instead of a generic transport error.
- A `server/discover` result without `resultType`, `ttlMs`, or `cacheScope` is treated as `complete`, `0`, and `private`, so the `auto` protocol mode no longer falls back to `initialize` for a modern server that omits them.

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
