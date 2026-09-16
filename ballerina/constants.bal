// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

// Transport related constants (headers)
const SESSION_ID_HEADER = "mcp-session-id";
const PROTOCOL_VERSION_HEADER = "mcp-protocol-version";
const ACCEPT_HEADER = "accept";
const CONTENT_TYPE_HEADER = "content-type";
const CONTENT_TYPE_JSON = "application/json";
const CONTENT_TYPE_SSE = "text/event-stream";

# Latest protocol revision using per-request negotiation.
public const MODERN_PROTOCOL_VERSION = "2026-07-28";
# Latest revision supporting the initialize handshake.
public const LATEST_LEGACY_PROTOCOL_VERSION = "2025-11-25";

const PROTOCOL_META_KEY = "io.modelcontextprotocol/protocolVersion";
const CAPABILITIES_META_KEY = "io.modelcontextprotocol/clientCapabilities";
const CLIENT_INFO_META_KEY = "io.modelcontextprotocol/clientInfo";
const SERVER_INFO_META_KEY = "io.modelcontextprotocol/serverInfo";
const LOG_LEVEL_META_KEY = "io.modelcontextprotocol/logLevel";
const METHOD_HEADER = "mcp-method";
const NAME_HEADER = "mcp-name";

# HTTP header validation failed before dispatch.
public const HEADER_MISMATCH = -32020;
# The request requires client capabilities that were not declared.
public const MISSING_REQUIRED_CLIENT_CAPABILITY = -32021;
# The requested protocol version is not supported.
public const UNSUPPORTED_PROTOCOL_VERSION = -32022;
