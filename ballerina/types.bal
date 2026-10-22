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

import ballerina/http;

# Refers to any valid JSON-RPC object that can be decoded off the wire, or encoded to be sent.
public type JsonRpcMessage JsonRpcRequest|JsonRpcNotification|JsonRpcError|JsonRpcResponse;

public const LATEST_PROTOCOL_VERSION = "2025-11-25";
public const SUPPORTED_PROTOCOL_VERSIONS = [
    LATEST_PROTOCOL_VERSION,
    "2025-06-18",
    "2025-03-26",
    "2024-11-05",
    "2024-10-07"
];

public const JSONRPC_VERSION = "2.0";

# Standard JSON-RPC request methods supported by the MCP protocol
public enum RequestMethod {
    # Initialize request to start a new MCP session
    REQUEST_INITIALIZE = "initialize",
    # Request to list all available tools from the server
    REQUEST_LIST_TOOLS = "tools/list",
    # Request to execute a specific tool with given parameters
    REQUEST_CALL_TOOL = "tools/call"
};

# Selects protocol behavior independently of legacy HTTP session management.
public type ProtocolMode "legacy"|"auto"|"modern";

# Represents the session management modes supported by the MCP server transport.
public enum SessionMode {
    # Stateful mode - sessions are managed by the transport
    STATEFUL = "stateful",
    # Stateless mode - no session management
    STATELESS = "stateless",
    # Automatic mode - determined based on client initialization
    AUTO = "auto"
};

# JSON-RPC notification methods used for one-way communication in MCP
public enum NotificationMethod {
    # Notification sent by client to indicate successful initialization
    NOTIFICATION_INITIALIZED = "notifications/initialized"
};

# A progress token, used to associate progress notifications with the original request.
public type ProgressToken string|int;

# An opaque token used to represent a cursor for pagination.
public type Cursor string;

# Optional metadata for requests
public type Meta record {
    # If specified, the caller is requesting out-of-band progress notifications for this request (as represented by notifications/progress).
    # The value of this parameter is an opaque token that will be attached to any subsequent notifications. The receiver is not obligated to provide these notifications.
    ProgressToken progressToken?;
};

# Parameters for the request
public type RequestParams record {
    # Optional metadata for the request
    Meta _meta?;
};

# Represents a generic request in the protocol
public type Request record {|
    # The method name for the request
    string method;
    # Optional parameters for the request
    RequestParams params?;
|};

# Represents a notification.
public type Notification record {|
    # The method name of the notification
    string method;
    # Additional parameters for the notification
    record {
        record {} _meta?;
    } params?;
|};

# Application-facing metadata attached to a result.
public type ResultMeta record {
    # Server implementation that produced the response.
    Implementation serverInfo?;
};

# Fields shared by result records.
type ResultFields record {
    # Metadata attached to the result.
    ResultMeta _meta?;
};

# Result discriminator. Known core results narrow this to a string singleton.
public type ResultType string;

# Base result type with common fields.
public type Result record {
    # This result property is reserved by the protocol to allow clients and servers
    # to attach additional metadata to their responses.
    record {} _meta?;
};

// Results as the modern dispatcher and the Client handle them, with typed metadata and a discriminator.
type WireResult record {
    *ResultFields;
    ResultType resultType?;
};

# A uniquely identifying ID for a request in JSON-RPC.
public type RequestId string|int;

# A request that expects a response.
public type JsonRpcRequest record {|
    *Request;
    # The JSON-RPC protocol version
    JSONRPC_VERSION jsonrpc;
    # Identifier established by the client that should be returned in the response
    RequestId id;
|};

# A notification which does not expect a response.
public type JsonRpcNotification record {|
    *Notification;
    # The JSON-RPC protocol version
    JSONRPC_VERSION jsonrpc;
|};

# A successful (non-error) response to a request.
public type JsonRpcResponse record {|
    # The JSON-RPC protocol version
    JSONRPC_VERSION jsonrpc;
    # Identifier of the request
    RequestId id;
    # The result of the request
    ServerResult result;
|};

// Standard JSON-RPC error codes
# Standard JSON-RPC 2.0 error code indicating that the JSON sent is not a valid JSON object.
public const PARSE_ERROR = -32700;
# Standard JSON-RPC 2.0 error code indicating that the JSON sent is not a valid request object.
public const INVALID_REQUEST = -32600;
# Standard JSON-RPC 2.0 error code indicating that the method does not exist or is not available.
public const METHOD_NOT_FOUND = -32601;
# Standard JSON-RPC 2.0 error code indicating that invalid method parameters were provided.
public const INVALID_PARAMS = -32602;
# Standard JSON-RPC 2.0 error code indicating that an internal error occurred on the server.
public const INTERNAL_ERROR = -32603;

// Library-defined error codes
# MCP library-defined error code indicating that the request is not acceptable.
public const NOT_ACCEPTABLE = -32001;
# MCP library-defined error code indicating that the media type is not supported.
public const UNSUPPORTED_MEDIA_TYPE = -32002;

# A response to a request that indicates an error occurred.
public type JsonRpcError record {|
    # The JSON-RPC protocol version
    JSONRPC_VERSION jsonrpc;
    # Identifier of the request
    RequestId? id;
    # The error information
    record {
        # The error type that occurred
        int code;
        # A short description of the error. The message SHOULD be limited to a concise single sentence.
        string message;
        # Additional information about the error. The value of this member is defined by the sender (e.g. detailed error information, nested errors etc.).
        anydata data?;
    } 'error;
|};

# This request is sent from the client to the server when it first connects, asking it to begin initialization.
type InitializeRequest record {|
    *Request;
    # Method name for the request
    REQUEST_INITIALIZE method = REQUEST_INITIALIZE;
    # Parameters for the initialize request
    record {
        *RequestParams;
        # The latest version of the Model Context Protocol that the client supports. 
        # The client MAY decide to support older versions as well.
        string protocolVersion;
        # Capabilities supported by the client
        ClientCapabilities capabilities;
        # Information about the client implementation
        Implementation clientInfo;
    } params;
|};

# After receiving an initialize request from the client, the server sends this response.
public type InitializeResult record {
    *Result;
    # The version of the Model Context Protocol that the server wants to use.
    # This may not match the version that the client requested.
    # If the client cannot support this version, it MUST disconnect.
    string protocolVersion;
    # The capabilities of the server.
    ServerCapabilities capabilities;
    # Information about the server implementation
    Implementation serverInfo;
    # Instructions describing how to use the server and its features.
    # This can be used by clients to improve the LLM's understanding of available tools, resources, etc.
    # It can be thought of like a "hint" to the model.
    # For example, this information MAY be added to the system prompt.
    string instructions?;
};

# This notification is sent from the client to the server after initialization has finished.
public type InitializedNotification record {|
    *Notification;
    # The method identifier for the notification, must be "notifications/initialized"
    NOTIFICATION_INITIALIZED method = NOTIFICATION_INITIALIZED;
|};

# Capabilities a client may support. Known capabilities are defined here, in this schema,
# but this is not a closed set: any client can define its own, additional capabilities.
public type ClientCapabilities record {
    # Optional protocol extensions supported by this implementation.
    map<record {}> extensions?;
    # Experimental, non-standard capabilities that the client supports.
    map<anydata> experimental?;
    # Present if the client supports listing roots.
    record {
        # Whether the client supports notifications for changes to the roots list.
        boolean listChanged?;
    } roots?;
    # Present if the client supports sampling from an LLM.
    record {
        # Whether the client supports context inclusion via includeContext parameter.
        # If not declared, servers SHOULD only use `includeContext: "none"` (or omit it).
        map<anydata> context?;
        # Whether the client supports tool use via tools and toolChoice parameters.
        map<anydata> tools?;
    } sampling?;
    # Present if the client supports elicitation from the server.
    record {
        map<anydata> form?;
        map<anydata> url?;
    } elicitation?;
    # Present if the client supports task-augmented requests.
    record {
        # Whether this client supports tasks/list.
        map<anydata> list?;
        # Whether this client supports tasks/cancel.
        map<anydata> cancel?;
        # Specifies which request types can be augmented with tasks.
        record {
            # Task support for sampling-related requests.
            record {
                # Whether the client supports task-augmented sampling/createMessage requests.
                map<anydata> createMessage?;
            } sampling?;
            # Task support for elicitation-related requests.
            record {
                # Whether the client supports task-augmented elicitation/create requests.
                map<anydata> create?;
            } elicitation?;
        } requests?;
    } tasks?;
};

# Capabilities that a server may support. Known capabilities are defined here, in this schema,
# but this is not a closed set: any server can define its own, additional capabilities.
public type ServerCapabilities record {
    # Optional protocol extensions supported by this implementation.
    map<record {}> extensions?;
    # Experimental, non-standard capabilities that the server supports.
    map<anydata> experimental?;
    # Present if the server supports sending log messages to the client.
    map<anydata> logging?;
    # Present if the server supports argument autocompletion suggestions.
    map<anydata> completions?;
    # Present if the server offers any prompt templates.
    record {
        # Whether this server supports notifications for changes to the prompt list.
        boolean listChanged?;
    } prompts?;
    # Present if the server offers any resources to read.
    record {
        # Whether this server supports subscribing to resource updates.
        boolean subscribe?;
        # Whether this server supports notifications for changes to the resource list.
        boolean listChanged?;
    } resources?;
    # Present if the server offers any tools to call.
    record {
        # Whether this server supports notifications for changes to the tool list.
        boolean listChanged?;
    } tools?;
    # Present if the server supports task-augmented requests.
    record {
        # Whether this server supports tasks/list.
        map<anydata> list?;
        # Whether this server supports tasks/cancel.
        map<anydata> cancel?;
        # Specifies which request types can be augmented with tasks.
        record {
            # Task support for tool-related requests.
            record {
                # Whether the server supports task-augmented tools/call requests.
                map<anydata> call?;
            } tools?;
        } requests?;
    } tasks?;
};

# Base metadata with name (identifier) and title (display name) properties.
public type BaseMetadata record {|
    # Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present).
    string name;
    # Intended for UI and end-user contexts — optimized to be human-readable and easily understood,
    # even by those unfamiliar with domain-specific terminology.
    string title?;
|};

# Represents a sized icon that can be displayed in a user interface.
# Icons were introduced in MCP protocol version `2025-11-25`.
# See https://modelcontextprotocol.io/specification/2025-11-25/basic#icons
public type Icon record {
    # A standard URI pointing to an icon resource. May be an HTTP/HTTPS URL or a
    # `data:` URI with base64-encoded image data. Required by the MCP specification, but kept
    # optional for backward compatibility with the deprecated `data` field.
    string src?;
    # The MIME type of the icon (e.g. image/png, image/jpeg, image/svg+xml, image/webp)
    string mimeType?;
    # Optional array of sizes the icon supports, in WxH format (e.g. "48x48", "96x96") or "any"
    # for scalable formats such as SVG
    string[] sizes?;
    # Optional theme this icon is designed for. `light` indicates the icon is designed to be used
    # with a light background, and `dark` indicates it is designed to be used with a dark background.
    "light"|"dark" theme?;
    # The URL or base64-encoded data of the icon
    # # Deprecated
    # This field is not part of the MCP specification. Use `src` instead.
    @deprecated
    string data?;
    # The size of the icon (e.g. 16, 32, 64, 128, 256)
    # # Deprecated
    # This field is not part of the MCP specification. Use `sizes` instead.
    @deprecated
    int size?;
};

# Optional set of sized icons that the client can display in a user interface.
public type Icons record {
    # Optional set of sized icons that the client can display in a user interface.
    # Supported MIME types: image/png, image/jpeg, image/svg+xml, image/webp
    Icon[] icons?;
};

# Describes the name and version of an MCP implementation.
public type Implementation record {
    *BaseMetadata;
    *Icons;
    # The version of the implementation
    string version;
    # An optional human-readable description of what this implementation does.
    string description?;
    # An optional URL of the website for this implementation.
    string websiteUrl?;
};

# Represents a paginated request with optional cursor-based pagination.
public type PaginatedRequest record {|
    # Optional pagination parameters
    RequestParams params?;
|};

# Result that supports pagination
public type PaginatedResult record {
    *Result;
    # An opaque token representing the pagination position after the last returned result.
    # If present, there may be more results available.
    Cursor nextCursor?;
};

# The contents of a specific resource or sub-resource.
public type ResourceContents record {
    # The URI of this resource.
    string uri;
    # The MIME type of this resource, if known.
    string mimeType?;
};

# Text resource contents
public type TextResourceContents record {
    *ResourceContents;
    # The text of the item. This must only be set if the item can actually be represented as text (not binary data).
    string text;
};

# Binary resource contents
public type BlobResourceContents record {
    *ResourceContents;
    # A base64-encoded string representing the binary data of the item.
    string blob;
};

# A known resource that the server is capable of reading.
public type Resource record {
    *BaseMetadata;
    *Icons;
    # The URI of this resource.
    string uri;
    # A description of what this resource represents.
    string description?;
    # The MIME type of this resource, if known.
    string mimeType?;
    # Optional annotations for the client.
    Annotations annotations?;
    # The size of the raw resource content, in bytes, if known.
    int size?;
};

# The sender or recipient of messages and data in a conversation.
public type Role "user"|"assistant";

# A resource that the server is capable of reading, included in a prompt or tool call result.
public type ResourceLink record {
    *Resource;
    # The type of content
    "resource_link" 'type;
};

# The contents of a resource, embedded into a prompt or tool call result.
public type EmbeddedResource record {
    # The type of content
    "resource" 'type;
    # The resource content
    TextResourceContents|BlobResourceContents 'resource;
    # Optional annotations for the client
    Annotations annotations?;
};

# Sent from the client to request a list of tools the server has.
public type ListToolsRequest record {|
    *PaginatedRequest;
    # The method identifier for this request
    REQUEST_LIST_TOOLS method = REQUEST_LIST_TOOLS;
|};

# The server's response to a tools/list request from the client.
public type ListToolsResult record {
    *PaginatedResult;
    # A list of tools available on the server.
    ToolDefinition[] tools;
};

# A page of tools, as `mcp:StreamableHttpClient2` returns it on both protocol generations. Unlike
# `ListToolsResult`, its tools may carry output schemas with any root.
public type ToolPage record {
    *WireResult;
    # An opaque token representing the pagination position after the last returned result.
    # If present, there may be more results available.
    Cursor nextCursor?;
    # A list of tools available on the server.
    ToolInfo[] tools;
    # Freshness hint in milliseconds. Modern servers default this to zero.
    int ttlMs?;
    # Whether a modern response may be shared between callers.
    CacheScope cacheScope?;
};

# A content block that can be text, image, audio, resource link, or embedded resource.
public type ContentBlock TextContent|ImageContent|AudioContent|ResourceLink|EmbeddedResource;

# The server's response to a tool call.
public type CallToolResult record {
    *Result;
    # A list of content objects that represent the unstructured result of the tool call.
    ContentBlock[] content;
    # An optional JSON object that represents the structured result of the tool call.
    map<anydata> structuredContent?;
    # Whether the tool call ended in an error.
    # If not set, this is assumed to be false (the call was successful).
    boolean isError?;
};

# The result of a tool call, as `mcp:StreamableHttpClient2` returns it on both protocol generations.
# Unlike `CallToolResult`, its structured content may be any JSON value.
public type ToolResult record {
    *ResultFields;
    # Identifies a completed modern result when disambiguating it from InputRequiredResult.
    "complete" resultType?;
    # A list of content objects that represent the unstructured result of the tool call.
    ContentBlock[] content;
    # An optional JSON value that represents the structured result of the tool call.
    json structuredContent?;
    # Whether the tool call ended in an error.
    # If not set, this is assumed to be false (the call was successful).
    boolean isError?;
};

# Used by the client to invoke a tool provided by the server.
public type CallToolRequest record {|
    # The JSON-RPC method name
    REQUEST_CALL_TOOL method = REQUEST_CALL_TOOL;
    # The parameters for the tool call
    CallToolParams params;
|};

# Parameters for the tools/call request
public type CallToolParams record {|
    *RequestParams;
    # The name of the tool to invoke
    string name;
    # Optional arguments to pass to the tool
    record {} arguments?;
    # If present, this is a task-augmented request (MCP 2025-11-25 TaskAugmentedRequestParams).
    # Servers ignore it, since none supports task-augmented tool calls.
    record {|
        # Optional time-to-live in milliseconds for the task.
        int ttl?;
    |} task?;
    # Responses to embedded input requests on a continuation.
    map<InputResponse> inputResponses?;
    # Opaque state echoed exactly from an input-required result.
    string requestState?;
|};

# Additional properties describing a Tool to clients.
# NOTE: all properties in ToolAnnotations are **hints**.
public type ToolAnnotations record {
    # A human-readable title for the tool.
    string title?;
    # If true, the tool does not modify its environment.
    # Default: false
    boolean readOnlyHint?;
    # If true, the tool may perform destructive updates to its environment.
    # If false, the tool performs only additive updates.
    # (This property is meaningful only when `readOnlyHint == false`)
    # Default: true
    boolean destructiveHint?;
    # If true, calling the tool repeatedly with the same arguments
    # will have no additional effect on the its environment.
    # (This property is meaningful only when `readOnlyHint == false`)
    # Default: false
    boolean idempotentHint?;
    # If true, this tool may interact with an "open world" of external
    # entities. If false, the tool's domain of interaction is closed.
    # For example, the world of a web search tool is open, whereas that
    # of a memory tool is not.
    # Default: true
    boolean openWorldHint?;
};

# An object-root JSON Schema describing tool arguments.
public type InputSchema record {|
    # JSON Schema dialect, defaulting to JSON Schema 2020-12.
    string \$schema?;
    # Tool input schemas always have an object root.
    "object" 'type;
    # Schemas for tool arguments.
    map<json> properties?;
    # Required argument names.
    string[] required?;
    json...;
|};

# Indicates whether a tool supports task-augmented execution.
public enum TaskSupport {
    # Task-augmented execution is not allowed for this tool.
    TASK_SUPPORT_FORBIDDEN = "forbidden",
    # Task-augmented execution is allowed but not required for this tool.
    TASK_SUPPORT_OPTIONAL = "optional",
    # Task-augmented execution is required for this tool.
    TASK_SUPPORT_REQUIRED = "required"
}

# Execution-related properties for a tool.
public type ToolExecution record {|
    # Indicates whether this tool supports task-augmented execution.
    TaskSupport taskSupport = TASK_SUPPORT_FORBIDDEN;
|};

# A JSON Schema object describing the parameters or output of a tool.
public type JsonSchema record {
    # The JSON Schema version
    string \$schema?;
    # The type of the schema
    "object" 'type;
    # The properties of the schema
    map<anydata> properties?;
    # The required properties of the schema
    string[] required?;
};

# Definition for a tool the client can call.
public type ToolDefinition record {
    *BaseMetadata;
    *Icons;
    # A human-readable description of the tool.
    string description?;
    # A JSON Schema object defining the expected parameters for the tool.
    JsonSchema inputSchema;
    # Execution-related properties for this tool.
    ToolExecution execution?;
    # An optional JSON Schema object defining the structure of the tool's output.
    JsonSchema outputSchema?;
    # Optional additional tool information.
    ToolAnnotations annotations?;
};

# A tool definition, as `mcp:StreamableHttpClient2` returns it. Unlike `ToolDefinition`, its output
# schema may have any root.
public type ToolInfo record {
    *BaseMetadata;
    *Icons;
    # A human-readable description of the tool.
    string description?;
    # A JSON Schema object defining the expected parameters for the tool.
    InputSchema inputSchema;
    # An optional general JSON Schema object defining the tool's structured output.
    OutputSchema outputSchema?;
    # Optional additional tool information.
    ToolAnnotations annotations?;
};

# Optional annotations for the client. The client can use annotations to inform how objects are used or displayed
public type Annotations record {|
    # Describes who the intended audience of this object or data is.
    # This can include multiple entries to indicate content useful for multiple audiences (e.g., `["user", "assistant"]`).
    Role[] audience?;
    # Describes how important this data is for operating the server.
    # A value of 1 means "most important," and indicates that the data is effectively required,
    # while 0 means "least important," and indicates that the data is entirely optional.
    decimal priority?;
    # The moment the resource was last modified, as an ISO 8601 formatted string.
    string lastModified?;
|};

# Text provided to or from an LLM.
public type TextContent record {
    # The type of content
    "text" 'type;
    # The text content of the message
    string text;
    # Optional annotations for the client
    Annotations annotations?;
};

# An image provided to or from an LLM.
public type ImageContent record {
    # The type of content
    "image" 'type;
    # The base64-encoded image data
    string data;
    # The MIME type of the image. Different providers may support different image types.
    string mimeType;
    # Optional annotations for the client
    Annotations annotations?;
};

# Audio provided to or from an LLM.
public type AudioContent record {
    # The type of content
    "audio" 'type;
    # The base64-encoded audio data
    string data;
    # The MIME type of the audio. Different providers may support different audio types.
    string mimeType;
    # Optional annotations for the client
    Annotations annotations?;
};

# Represents a result sent from the server to the client.
public type ServerResult InitializeResult|CallToolResult|ListToolsResult;

# Represents a tool configuration that can be used to define tools available in the MCP service.
public type McpToolConfig record {|
    # The description of the tool.
    string description?;
    # The JSON schema for the tool's parameters.
    map<json> schema?;
    # The JSON schema generated from, or explicitly assigned for, the successful return value.
    # It is advertised only to clients using the modern protocol.
    OutputSchema outputSchema?;
    # Whether modern requests should receive structured output for this tool.
    boolean structuredOutput = true;
    # Scopes the caller's access token must grant to call this tool, in addition to the
    # `requiredScopes` of the service's `mcp:OAuthProtectedResourceConfig`. They are enforced by the server
    # and never sent to clients; a caller without them receives a `403` challenge.
    string[] scopes?;
|};

# Annotation to mark a function as an MCP tool configuration.
public annotation McpToolConfig Tool on object function;

# Configuration for an MCP tool argument.
public type ArgumentConfig record {|
    # Mirrors the argument into the corresponding `Mcp-Param-*` request header. The argument
    # remains present in `tools/call.params.arguments`.
    string headerName;
|};

# Configures an argument of a tool remote function.
public const annotation ArgumentConfig Argument on parameter;

# Represents the options for configuring an MCP server.
public type ServerOptions record {|
    # Capabilities to advertise as being supported by this server.
    ServerCapabilities capabilities?;
    # Optional instructions describing how to use the server and its features.
    string instructions?;
    # Whether to enforce strict capabilities compliance.
    boolean enforceStrictCapabilities?;
|};

# Who may reuse a cached result. `public` results may be shared between callers, while `private`
# results may only be reused for the same authorization context.
public type CacheScope "public"|"private";

# Caching hint for a cacheable result. Unset fields fall back to `ttlMs = 0` and `cacheScope = "private"`.
public type CacheHint record {|
    # How long, in milliseconds, a client may treat the result as fresh. Must be non-negative.
    int ttlMs?;
    # Who may reuse the cached result.
    CacheScope cacheScope?;
|};

# Caching hints for the cacheable results of a modern MCP service.
public type CacheHints record {|
    # Hint for `server/discover` results.
    CacheHint discover?;
    # Hint for `tools/list` results. Fields set on the `ToolPage` returned by `onListTools` take precedence.
    CacheHint listTools?;
|};

# Configuration for an MCP service exposed over the Streamable HTTP transport.
public type StreamableHttpServiceConfiguration record {|
    # Server implementation information
    Implementation info;
    # Protocol selection. Auto preserves legacy requests and accepts modern requests when the service supports them.
    ProtocolMode protocolMode = "auto";
    # Optional server configuration options
    ServerOptions options?;
    # HTTP service configuration for the underlying transport, including authentication
    HttpServiceConfig httpConfig = {};
    # Controls the session management mode for the transport.
    # - STATEFUL → Sessions are managed by the transport with session IDs
    # - STATELESS → No session management, each request is independent
    # - AUTO → Automatically determined based on client initialization behavior (default)
    SessionMode sessionMode = AUTO;
    # Caching hints sent to modern clients on cacheable results
    CacheHints cacheHints = {};
    # Signing of the request state returned in input-required results
    RequestStateConfig requestState = {};
|};

# How the request state of input-required results is signed. Request state is signed, not
# encrypted: clients can read it, so it must not hold anything they should not see.
public type RequestStateConfig record {|
    # Signing secrets, each at least 32 bytes. The first signs and all verify, so a key can be rotated
    # by putting its replacement first. Without keys, each service generates a random key of its own when
    # it is attached, so replicas that share continuations must configure the same keys.
    string[] keys = [];
    # Seconds a request state stays valid, renewed on every round. Must be positive.
    decimal ttl = 600;
|};

# HTTP settings of the service that serves an MCP endpoint. These are the settings of
# `http:HttpServiceConfig`, with `auth` also accepting an `mcp:OAuthProtectedResourceConfig`.
#
# The fields mirror `http:HttpServiceConfig` and must be kept in step with it when the HTTP
# module adds or changes a setting.
public type HttpServiceConfig record {|
    # Domain name of the service
    string host = DEFAULT_HTTP_SERVICE_HOST;
    # The status of compression
    http:CompressionConfig compression = {};
    # Configures the chunking behaviour for the service
    http:Chunking chunking = http:CHUNKING_AUTO;
    # The cross origin resource sharing configurations for the service
    http:CorsConfig cors = {};
    # How callers are authenticated.
    # - `mcp:OAuthProtectedResourceConfig`: OAuth protected resource authorization (RFC 9728), as the MCP
    #   authorization specification requires. The service publishes protected resource metadata,
    #   challenges unauthenticated requests, accepts only tokens issued for it, enforces tool scopes,
    #   and provides `mcp:AuthContext` to tools.
    # - `http:ListenerAuthConfig[]`: HTTP listener authentication, without discovery.
    OAuthProtectedResourceConfig|http:ListenerAuthConfig[] auth?;
    # Service specific media-type subtype prefix
    string mediaTypeSubtypePrefix?;
    # Treat Nilable parameters as optional
    boolean treatNilableAsOptional = true;
    # The generated OpenAPI definition for the HTTP service. This is auto-generated at compile-time if
    # OpenAPI doc auto generation is enabled
    byte[] openApiDefinition = [];
    # Enables the inbound payload validation functionality which provided by the constraint package.
    # Enabled by default
    boolean validation = true;
    # The service object type which defines the service contract. This is auto-generated at compile-time
    typedesc<http:ServiceContract> serviceType?;
    # Base path to be used with the service implementation. This is only allowed on service contract types
    string basePath?;
    # Enables or disables relaxed data binding on the service side. Disabled by default.
    # When enabled, the JSON data will be projected to the Ballerina record type and during the projection,
    # nil values will be considered as optional fields and absent fields will be considered for nilable types
    boolean laxDataBinding = false;
|};

# Annotation to configure an MCP service exposed over Streamable HTTP.
public annotation StreamableHttpServiceConfiguration StreamableHttpServiceConfig on service;

# Defines a basic MCP service interface exposed over the Streamable HTTP transport. Tool
# `remote` functions may additionally bind HTTP request information (e.g. `@http:Header`
# parameters, an `http:Headers` parameter, or an `http:Request` parameter).
public type StreamableHttpService distinct service object {

};

# Defines an MCP service interface exposed over the Streamable HTTP transport with manual control
# over tool listing and invocation. Handlers return `ToolPage` and
# `ToolResult|InputRequiredResult`. In addition to protocol parameters, handlers may bind
# transport-specific request information via `@http:Header`, `http:Headers`, or `http:Request`. The
# compiler plugin validates the method shapes.
public type StreamableHttpAdvancedService distinct service object {
};

# JSON Schema output definition. Output schemas may describe any JSON value.
public type OutputSchema record {|
    # JSON Schema dialect, defaulting to JSON Schema 2020-12.
    string \$schema?;
    json...;
|};

# Server discovery response. Identity is carried in _meta.
public type DiscoverResult record {
    *WireResult;
    # Protocol revisions accepted by this service.
    string[] supportedVersions;
    # Implemented server features.
    ServerCapabilities capabilities;
    # Optional guidance for using this server.
    string instructions?;
    # Freshness hint in milliseconds; zero disables caching.
    int ttlMs = 0;
    # Whether a response may be shared between callers.
    CacheScope cacheScope = "private";
};

# Information established when a client connects to a server.
public type ConnectionInfo record {|
    # Effective protocol version selected for subsequent requests.
    string protocolVersion;
    # Server identity, when the peer supplied it.
    Implementation serverInfo?;
    # Capabilities advertised by the server.
    ServerCapabilities capabilities;
    # Optional guidance supplied by the server.
    string instructions?;
|};

# An input request a server embeds in an input-required result. Elicitation is the only kind supported.
public type InputRequest ElicitRequest;

# An elicitation the server embeds in an input-required result. Only declared elicitation modes may be requested.
public type ElicitRequest record {|
    # The elicitation method.
    "elicitation/create" method = "elicitation/create";
    # A form elicitation or a URL elicitation.
    FormElicitationParams|UrlElicitationParams params;
|};

# Asks the user to fill in a form the client renders.
public type FormElicitationParams record {|
    # The elicitation mode.
    "form" mode = "form";
    # The message to show the user.
    string message;
    # The form schema describing the fields to collect.
    FormSchema requestedSchema;
|};

# Asks the user to open a URL, for an out-of-band step.
public type UrlElicitationParams record {|
    # The elicitation mode.
    "url" mode;
    # The message to show the user.
    string message;
    # The absolute URL the user should open.
    string url;
|};

# A flat object of string, number, boolean and enum fields describing an elicitation form.
public type FormSchema record {|
    # JSON Schema dialect.
    string \$schema?;
    # Always an object.
    "object" 'type = "object";
    # Field schemas keyed by field name.
    map<FormFieldSchema> properties;
    # Names of the fields the user must fill in.
    string[] required?;
|};

# The schema of one form field.
public type FormFieldSchema StringFieldSchema|NumberFieldSchema|BooleanFieldSchema|EnumFieldSchema|
    TitledEnumFieldSchema|MultiSelectEnumFieldSchema|TitledMultiSelectEnumFieldSchema|LegacyTitledEnumFieldSchema;

# A free-text form field.
public type StringFieldSchema record {|
    # The JSON type.
    "string" 'type;
    # A display label.
    string title?;
    # A description of the field.
    string description?;
    # The minimum length.
    int minLength?;
    # The maximum length.
    int maxLength?;
    # The expected string format.
    "email"|"uri"|"date"|"date-time" format?;
    # The initial value.
    string default?;
|};

# A numeric form field.
public type NumberFieldSchema record {|
    # The JSON type.
    "number"|"integer" 'type;
    # A display label.
    string title?;
    # A description of the field.
    string description?;
    # The minimum value.
    decimal minimum?;
    # The maximum value.
    decimal maximum?;
    # The initial value.
    decimal default?;
|};

# A yes/no form field.
public type BooleanFieldSchema record {|
    # The JSON type.
    "boolean" 'type;
    # A display label.
    string title?;
    # A description of the field.
    string description?;
    # The initial value.
    boolean default?;
|};

# A single-select field whose options are their own labels.
public type EnumFieldSchema record {|
    # The JSON type.
    "string" 'type;
    # A display label.
    string title?;
    # A description of the field.
    string description?;
    # The allowed values.
    string[] 'enum;
    # The initially selected value.
    string default?;
|};

# A single-select field whose labels are listed in `enumNames`, in the order of `enum`. MCP keeps this
# shape for older servers; the client accepts it, but a service cannot send it. Use `TitledEnumFieldSchema`.
public type LegacyTitledEnumFieldSchema record {|
    # The JSON type.
    "string" 'type;
    # A display label.
    string title?;
    # A description of the field.
    string description?;
    # The allowed values.
    string[] 'enum;
    # A display label for each allowed value.
    string[] enumNames;
    # The initially selected value.
    string default?;
|};

# A single-select field whose options carry display labels.
public type TitledEnumFieldSchema record {|
    # The JSON type.
    "string" 'type;
    # A display label.
    string title?;
    # A description of the field.
    string description?;
    # The allowed values with their labels.
    TitledOption[] oneOf;
    # The initially selected value.
    string default?;
|};

# A multi-select field whose options are their own labels.
public type MultiSelectEnumFieldSchema record {|
    # The JSON type.
    "array" 'type;
    # A display label.
    string title?;
    # A description of the field.
    string description?;
    # The minimum number of selections.
    int minItems?;
    # The maximum number of selections.
    int maxItems?;
    # The allowed values.
    record {|
        # The JSON type of each selection.
        "string" 'type = "string";
        # The allowed values.
        string[] 'enum;
    |} items;
    # The initially selected values.
    string[] default?;
|};

# A multi-select field whose options carry display labels.
public type TitledMultiSelectEnumFieldSchema record {|
    # The JSON type.
    "array" 'type;
    # A display label.
    string title?;
    # A description of the field.
    string description?;
    # The minimum number of selections.
    int minItems?;
    # The maximum number of selections.
    int maxItems?;
    # The allowed values with their labels.
    record {|
        # The allowed values with their labels.
        TitledOption[] anyOf;
    |} items;
    # The initially selected values.
    string[] default?;
|};

# An enum option with a display label.
public type TitledOption record {|
    # The value sent back when the option is chosen.
    string 'const;
    # The label shown to the user.
    string title;
|};

# Additional input required before the original operation can complete.
public type InputRequiredResult record {
    *ResultFields;
    # Identifies an interim result requiring a continuation.
    "input_required" resultType = "input_required";
    # Input requests keyed by server-assigned identifiers.
    map<InputRequest> inputRequests?;
    # Opaque server state that clients must echo without modification.
    string requestState?;
};

# The client's answer to an input request, sent back on the continuation.
public type InputResponse ElicitResult;

# The user's answer to an elicitation.
public type ElicitResult record {
    *ResultFields;
    # Whether the user submitted the form or opened the URL, declined, or dismissed the elicitation.
    "accept"|"decline"|"cancel" action;
    # The submitted form values, keyed by field name.
    map<ElicitationValue> content?;
};

# A value the user submitted for one form field.
public type ElicitationValue string|int|float|decimal|boolean|string[];

# Answers elicitations for the client. It is invoked once per input request, outside client locks.
# The client does not validate the answer against the form schema.
public type ElicitationHandler isolated function (ElicitRequest elicitRequest) returns ElicitResult|ClientError;
