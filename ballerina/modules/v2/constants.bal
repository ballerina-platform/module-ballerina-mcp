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

# Revisions that use per-request negotiation, newest first.
public const MODERN_PROTOCOL_VERSIONS = ["2026-07-28"];
# Revisions that use the `initialize` handshake, newest first.
public const LEGACY_PROTOCOL_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"];
# The union of the modern and legacy revisions.
public const SUPPORTED_PROTOCOL_VERSIONS = [...MODERN_PROTOCOL_VERSIONS, ...LEGACY_PROTOCOL_VERSIONS];
# The newest modern revision, sent by the client.
public const LATEST_PROTOCOL_VERSION = "2026-07-28";
# The newest legacy revision, offered in `initialize`.
public const LATEST_LEGACY_PROTOCOL_VERSION = "2025-11-25";

const PROTOCOL_META_KEY = "io.modelcontextprotocol/protocolVersion";
const CAPABILITIES_META_KEY = "io.modelcontextprotocol/clientCapabilities";
const CLIENT_INFO_META_KEY = "io.modelcontextprotocol/clientInfo";
const SERVER_INFO_META_KEY = "io.modelcontextprotocol/serverInfo";
const LOG_LEVEL_META_KEY = "io.modelcontextprotocol/logLevel";
const METHOD_HEADER = "mcp-method";
// Pages read to find a tool by name, so a service that keeps offering pages cannot stall a call.
const MAX_TOOL_LIST_PAGES = 100;
const NAME_HEADER = "mcp-name";

# HTTP header validation failed before dispatch.
public const HEADER_MISMATCH = -32020;
# The request requires client capabilities that were not declared.
public const MISSING_REQUIRED_CLIENT_CAPABILITY = -32021;
# The requested protocol version is not supported.
public const UNSUPPORTED_PROTOCOL_VERSION = -32022;

const AUTHORIZATION_HEADER = "Authorization";
const WWW_AUTHENTICATE_HEADER = "WWW-Authenticate";
// Default `host` of an HTTP service, which binds it to no particular virtual host.
const DEFAULT_HTTP_SERVICE_HOST = "b7a.default";
const INSUFFICIENT_SCOPE = "insufficient_scope";
const OAUTH_CLIENT_CREDENTIALS_EXTENSION = "io.modelcontextprotocol/oauth-client-credentials";
const ENTERPRISE_MANAGED_AUTHORIZATION_EXTENSION = "io.modelcontextprotocol/enterprise-managed-authorization";
const INPUT_REQUIRED_ON_LEGACY = "Input-required tool calls require modern MCP";
// Seconds to wait before retrying a state-only input-required round, doubling up to the cap.
const decimal STATE_ONLY_RETRY_DELAY = 0.05;
const decimal STATE_ONLY_RETRY_MAX_DELAY = 0.25;

# The HTTP method of an outbound transport request.
enum OutboundMethod {
    POST,
    DELETE
}
