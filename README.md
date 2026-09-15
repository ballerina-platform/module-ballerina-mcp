# Ballerina MCP Library

[![Build](https://github.com/ballerina-platform/module-ballerina-mcp/workflows/CI/badge.svg)](https://github.com/ballerina-platform/module-ballerina-mcp/actions?query=workflow%3ACI)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ballerina-platform/module-ballerina-mcp.svg)](https://github.com/ballerina-platform/module-ballerina-mcp/commits/main)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Overview

This module provides APIs for building MCP (Model Context Protocol) clients and servers in Ballerina.

MCP is an open standard that enables seamless integration between Large Language Models (LLMs) and external data sources, tools, and services. It facilitates structured communication through JSON-RPC 2.0 over HTTP transport, allowing AI applications to access and interact with external capabilities in a standardized way.

The Ballerina MCP library implements both client and server-side functionality, supporting automatic tool discovery, type-safe schema generation, flexible session management (STATEFUL, STATELESS, AUTO modes), and streamable HTTP transport with Server-Sent Events (SSE) for bidirectional communication.

## MCP 2026-07-28

Version 2.0.0 adds automatic modern/legacy protocol selection, modern discovery, per-request metadata and headers,
automatic output schemas and raw structured results for regular services, modern tool-result APIs, bounded
input-required continuations, and POST-based subscriptions. Existing session-dependent services remain on the legacy
path in auto mode. See the [protocol compatibility and migration guide](ballerina/README.md#protocol-versions-and-compatibility).
General JSON Schema evaluation is deferred until Ballerina language support is available; existing type binding remains.

### Interoperability checks

After `./gradlew build -x commitTomlFiles`, use `target/ballerina-runtime/bin/bal` to clean and build the
`ballerina-tests/interop-server` and `ballerina-tests/interop-client` packages. Cleaning matters when testing multiple
checkpoints with the same development version. The fixtures use FastMCP 4.0.0b5, Python SDK 2.2.0, and TypeScript SDK 2.0.0.
Install the Node fixtures with `npm ci --prefix ballerina-tests/interop` and use the pinned Python requirements in that directory.

Start the Ballerina fixture with:

```sh
java -jar ballerina-tests/interop-server/target/bin/interop_server.jar -CinteropPort=3210
```

Then run `python_client.py` and `typescript_client.mjs` from `ballerina-tests/interop`, passing
`http://127.0.0.1:3210`. They check legacy/auto/modern operation, required-session fallback, and scalar results.
For the reverse direction, start `python_server.py fastmcp 3211`, `python_server.py sdk 3212`, and
`node typescript_server.mjs 3213`. Run the Ballerina interop client JAR with
`-CinteropUrl=http://127.0.0.1:PORT/mcp` for each port. These checks exercise JSON/SSE responses and Unicode mirrored headers.
Stop all fixture processes when finished. These are optional interoperability checks; the regular Gradle suites need no
Python or Node SDK installation.

The standard HTTP-header conformance scenario can be run against the Ballerina fixture with:

```sh
npx --yes @modelcontextprotocol/conformance@0.2.0-alpha.11 server --url http://127.0.0.1:3210/mcp --scenario http-header-validation --spec-version 2026-07-28
```

This scenario passed all 14 checks during the upgrade. The broader caching scenario passed tool-list caching and wire
validation, but also requires prompt/resource fixtures outside this module's implemented feature set; it is not a
complete conformance gate for this tools-focused library.

## Issues and projects

Issues and Projects tabs are disabled for this repository as this is part of the Ballerina Library. To report bugs, request new features, start new discussions, view project boards, etc., go to the [Ballerina Library parent repository](https://github.com/ballerina-platform/ballerina-standard-library).
This repository only contains the source code for the module.

## Build from the source

### Prerequisites

1. Download and install Java SE Development Kit (JDK) version 21 (from one of the following locations).

   - [Oracle](https://www.oracle.com/java/technologies/downloads/)
   - [OpenJDK](https://adoptium.net/)

     > **Note:** Set the JAVA_HOME environment variable to the path name of the directory into which you installed JDK.

2. Generate a GitHub access token with read package permissions, then set the following `env` variables:

   ```shell
   export packageUser=<Your GitHub Username>
   export packagePAT=<GitHub Personal Access Token>
   ```

### Build options

Execute the commands below to build from the source.

1. To build the package:

   ```bash
   ./gradlew clean build
   ```

2. To run the tests:

   ```bash
   ./gradlew clean test
   ```

3. To run a group of tests

   ```bash
   ./gradlew clean test -Pgroups=<test_group_names>
   ```

4. To build the without the tests:

   ```bash
   ./gradlew clean build -x test
   ```

5. To debug the package with a remote debugger:

   ```bash
   ./gradlew clean build -Pdebug=<port>
   ```

6. To debug with Ballerina language:

   ```bash
   ./gradlew clean build -PbalJavaDebug=<port>
   ```

7. Publish the generated artifacts to the local Ballerina central repository:

   ```bash
   ./gradlew clean build -PpublishToLocalCentral=true
   ```

8. Publish the generated artifacts to the Ballerina central repository:

   ```bash
   ./gradlew clean build -PpublishToCentral=true
   ```

## Contribute to Ballerina

As an open-source project, Ballerina welcomes contributions from the community.

For more information, go to the [contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of conduct

All the contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).

## Useful links

- For more information go to the [`mcp` library](https://lib.ballerina.io/ballerina/mcp/latest).
- Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
- Post all technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
