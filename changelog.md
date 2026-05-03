# Change Log
This file contains all the notable changes done to the Ballerina MCP package through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Support for MCP protocol version `2025-11-25`, with backward compatibility for `2025-06-18`, `2025-03-26`, and `2024-11-05`
- Server-side async task execution for `tools/call` requests with `task` metadata, with support for `tasks/list`, `tasks/get`, `tasks/result`, and `tasks/cancel`
