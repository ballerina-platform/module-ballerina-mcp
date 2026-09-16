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

public const LATEST_PROTOCOL_VERSION = "2026-07-28";
public const SUPPORTED_PROTOCOL_VERSIONS = [
    LATEST_PROTOCOL_VERSION,
    LATEST_LEGACY_PROTOCOL_VERSION,
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
public enum HttpSessionMode {
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

# Application-facing metadata for requests.
public type RequestMetaObject record {
    # If specified, the caller is requesting out-of-band progress notifications for this request (as represented by notifications/progress).
    # The value of this parameter is an opaque token that will be attached to any subsequent notifications. The receiver is not obligated to provide these notifications.
    ProgressToken progressToken?;
};

# Parameters for the request
public type RequestParams record {
    # Optional metadata for the request
    RequestMetaObject _meta?;
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
        NotificationMetaObject _meta?;
    } params?;
|};

# Application-facing metadata attached to a result.
public type ResultMetaObject record {
    # Server implementation that produced the response.
    Implementation serverInfo?;
};

# Application-facing metadata attached to a notification.
public type NotificationMetaObject record {
    # Request identifier of the subscription that delivered the notification.
    RequestId subscriptionId?;
};

# Fields shared by result records.
type ResultFields record {
    # Metadata attached to the result.
    ResultMetaObject _meta?;
};

# Result discriminator. Known core results narrow this to a string singleton.
public type ResultType string;

# Base result type with common fields.
public type Result record {
    *ResultFields;
    # Modern results carry a discriminator. It is absent on legacy wire responses.
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

# Represents an optionally sized icon that can be displayed in a user interface.
public type Icon record {
    # URI pointing to an icon resource, including HTTP(S) and data URIs.
    string src;
    # Optional MIME type override when the source type is unavailable or generic.
    string mimeType?;
    # Supported sizes in WxH form, or `any` for scalable formats.
    string[] sizes?;
    # Theme for which the icon was designed.
    "dark"|"light" theme?;
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
    # Freshness hint in milliseconds. Modern servers default this to zero.
    int ttlMs?;
    # Whether a modern response may be shared between callers.
    "public"|"private" cacheScope?;
};

# A content block that can be text, image, audio, resource link, or embedded resource.
public type ContentBlock TextContent|ImageContent|AudioContent|ResourceLink|EmbeddedResource;

# The server's response to a tool call.
public type CallToolResult record {
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
    # Responses to embedded input requests on a continuation.
    map<InputResponse> inputResponses?;
    # Opaque state echoed exactly from an input-required result.
    string requestState?;
    # Optional arguments to pass to the tool
    record {} arguments?;
    # If present, this is a task-augmented request (MCP 2025-11-25 TaskAugmentedRequestParams).
    # Currently disallowed — no server advertises `tasks.requests.tools.call` yet.
    record {|
        # Optional time-to-live in milliseconds for the task.
        int ttl?;
    |} task?;
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

# Definition for a tool the client can call.
public type ToolDefinition record {
    *BaseMetadata;
    *Icons;
    # A human-readable description of the tool.
    string description?;
    # A JSON Schema object defining the expected parameters for the tool.
    InputSchema inputSchema;
    # Execution-related properties for this tool.
    ToolExecution execution?;
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
    InputSchema schema?;
    # The JSON schema generated from, or explicitly assigned for, the successful return value.
    # It is advertised only to clients using the modern protocol.
    OutputSchema outputSchema?;
    # Whether modern requests should receive structured output for this tool.
    boolean structuredOutput = true;
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

# Configuration for an MCP service exposed over the Streamable HTTP transport.
public type StreamableHttpConfiguration record {|
    # Server implementation information
    Implementation info;
    # Protocol selection. Auto preserves legacy requests and accepts modern requests when the service supports them.
    ProtocolMode protocolMode = "auto";
    # Optional server configuration options
    ServerOptions options?;
    # HTTP service configuration for the underlying transport
    http:HttpServiceConfig httpConfig = {};
    # Controls the session management mode for the transport.
    # - STATEFUL → Sessions are managed by the transport with session IDs
    # - STATELESS → No session management, each request is independent
    # - AUTO → Automatically determined based on client initialization behavior (default)
    HttpSessionMode sessionMode = AUTO;
|};

# Annotation to provide configuration to Streamable HTTP MCP services.
# Annotation to configure an MCP service exposed over Streamable HTTP.
public annotation StreamableHttpConfiguration StreamableHttpConfig on service;

# Defines a basic MCP service interface exposed over the Streamable HTTP transport. Tool
# `remote` functions may additionally bind HTTP request information (e.g. `@http:Header`
# parameters, an `http:Headers` parameter, or an `http:Request` parameter).
public type StreamableHttpService distinct service object {

};

# Defines an MCP service interface exposed over the Streamable HTTP transport with manual control
# over tool listing and invocation. Handlers return `ListToolsResult` and
# `CallToolResult|InputRequiredResult`. An optional `onSubscribe` method publishes modern change
# notifications. In addition to protocol parameters, handlers may bind transport-specific request
# information via `@http:Header`, `http:Headers`, or `http:Request`. The compiler plugin validates
# the method shapes.
public type StreamableHttpAdvancedService distinct service object {
};

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

# Embedded server input request. Only declared client capabilities may be requested.
public type InputRequest record {|
    # The requested input operation.
    "elicitation/create"|"sampling/createMessage"|"roots/list" method;
    # Parameters describing the requested input.
    RequestParams params?;
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

# An input result supplied by the application, for example an elicitation response.
public type InputResponse record {
};

# Callback for gathering input requested by a server. It is invoked outside client locks.
public type InputHandler isolated function (InputRequest inputRequest) returns InputResponse|ClientError;

# Selects change notifications for a subscription.
public type SubscriptionFilter record {|
    # Subscribe to tool list changes.
    boolean toolsListChanged = false;
    # Subscribe to prompt list changes when supported by the peer.
    boolean promptsListChanged = false;
    # Subscribe to resource list changes when supported by the peer.
    boolean resourcesListChanged = false;
    # Resource URIs whose changes should be observed.
    string[] resourceSubscriptions = [];
|};
