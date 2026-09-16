# Change Log
This file contains all the notable changes done to the Ballerina MCP package through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
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
- [Service methods are dropped when a service shares a document with an MCP tool](https://github.com/ballerina-platform/ballerina-library/issues/8971)

## [1.1.0] - 2026-07-02

### Added
- Partial support for MCP protocol version `2025-11-25`, with backward compatibility for `2025-06-18`, `2025-03-26`, and `2024-11-05`. Task-augmented requests introduced in `2025-11-25` are not yet supported.
- [Support for passing `mcp:Meta` to tool functions](https://github.com/ballerina-platform/module-ballerina-mcp/pull/36)
