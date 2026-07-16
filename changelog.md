# Change Log
This file contains all the notable changes done to the Ballerina MCP package through the releases.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Partial support for MCP protocol version `2025-11-25`, with backward compatibility for `2025-06-18`, `2025-03-26`, and `2024-11-05`. Task-augmented requests introduced in `2025-11-25` are not yet supported.
- Add stdio client transport support: a new `mcp:StdioClient` launches an MCP server as a subprocess and communicates over newline-delimited JSON-RPC on stdin/stdout, per the MCP stdio transport specification. Supports `command`/`args`/`env`/`cwd` configuration, read timeouts, stderr handling modes, and a spec-compliant shutdown sequence that also terminates descendant processes of launcher commands such as `uvx`/`npx`.
