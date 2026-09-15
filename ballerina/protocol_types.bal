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

# A general JSON Schema value represented until native language support is available.
public type JsonSchema map<json>;

# JSON Schema output definition. Output schemas may describe any JSON value.
public type OutputSchema record {|
    # JSON Schema dialect, defaulting to JSON Schema 2020-12.
    string \$schema?;
    json...;
|};

# Server discovery response. Identity is carried in _meta.
public type DiscoverResult record {
    *Result;
    # Protocol revisions accepted by this service.
    string[] supportedVersions;
    # Implemented server features.
    ServerCapabilities capabilities;
    # Optional guidance for using this server.
    string instructions?;
    # Freshness hint in milliseconds; zero disables caching.
    int ttlMs = 0;
    # Whether a response may be shared between callers.
    "public"|"private" cacheScope = "private";
};

# Embedded server input request. Only declared client capabilities may be requested.
public type InputRequest record {|
    # The requested input operation.
    "elicitation/create"|"sampling/createMessage"|"roots/list" method;
    # Parameters describing the requested input.
    RequestParams params?;
|};

# Additional input required before the original operation can complete.
public type InputRequiredResult record {
    *Result;
    # Identifies an interim result requiring a continuation.
    "input_required" resultType = "input_required";
    # Input requests keyed by server-assigned identifiers.
    map<InputRequest> inputRequests?;
    # Opaque server state that clients must echo without modification.
    string requestState?;
};

# An input result supplied by the application, for example an elicitation response.
public type InputResponse record {
};

# Callback for gathering input requested by a server. It is invoked outside client locks.
public type InputHandler isolated function (InputRequest inputRequest) returns InputResponse|ClientError;

// Wire responses are decoded before conversion to application-facing result records.
type WireResponse record {|
    JSONRPC_VERSION jsonrpc;
    RequestId id;
    Result result;
|};

// Modern HTTP errors may omit an ID when the request could not be identified.
type WireError record {|
    JSONRPC_VERSION jsonrpc;
    RequestId? id?;
    record {
        int code;
        string message;
        anydata data?;
    } 'error;
|};

type WireMessage WireResponse|WireError|JsonRpcRequest|JsonRpcNotification;

type ModernRequestMeta record {
    string io\.modelcontextprotocol\/protocolVersion;
    ClientCapabilities io\.modelcontextprotocol\/clientCapabilities;
    Implementation io\.modelcontextprotocol\/clientInfo?;
};
