# Change Log
This file contains all the notable changes done to the Ballerina MCP package through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Support for MCP protocol version `2025-11-25`, with backward compatibility for `2025-06-18`
- Task management support: tool calls can be augmented with task execution, and clients can query task status via `tasks/list`, `tasks/get`, `tasks/result`, and `tasks/cancel`
- Updated types to align with the MCP `2025-11-25` specification

### Changed
- Extended `CallToolResult` with richer content blocks (audio, resource links, embedded resources) and optional structured content
- Fixed native-image compatibility for `ContentBlock` array element type handling in `McpServiceMethodHelper`
