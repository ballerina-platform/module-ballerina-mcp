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

# Refers to any valid JSON-RPC object that can be decoded off the wire, or encoded to be sent.
public type JsonRpcMessage JsonRpcRequest|JsonRpcNotification|JsonRpcResponse|JsonRpcError;

public const LATEST_PROTOCOL_VERSION = "2025-03-26";
public const SUPPORTED_PROTOCOL_VERSIONS = [
    LATEST_PROTOCOL_VERSION,
    "2024-11-05",
    "2024-10-07"
];

public const JSONRPC_VERSION = "2.0";

# A progress token, used to associate progress notifications with the original request.
public type ProgressToken string|int;

# An opaque token used to represent a cursor for pagination.
public type Cursor string;

# Represents a generic request in the protocol
#
# + method - The method name for the request
# + params - Optional parameters for the request
public type Request record {|
    string method;
    record {
        record {|
            # If specified, the caller is requesting out-of-band progress notifications for this request (as represented by notifications/progress).
            # The value of this parameter is an opaque token that will be attached to any subsequent notifications. The receiver is not obligated to provide these notifications.
            ProgressToken progressToken?;
        |} _meta?;
    } params?;
|};

# Represents a notification.
#
# + method - The method name of the notification
# + params - Additional parameters for the notification
public type Notification record {|
    string method;
    record {
        record {} _meta?;
    } params?;
|};

# Base result type with common fields.
#
# + _meta - This result property is reserved by the protocol to allow clients and servers
# to attach additional metadata to their responses.
public type Result record {
    record {} _meta?;
};

# A uniquely identifying ID for a request in JSON-RPC.
public type RequestId string|int;

# A request that expects a response.
#
# + jsonrpc - The JSON-RPC protocol version
# + id - Identifier established by the client that should be returned in the response
public type JsonRpcRequest record {
    *Request;
    JSONRPC_VERSION jsonrpc;
    RequestId id;
};

# A notification which does not expect a response.
#
# + jsonrpc - The JSON-RPC protocol version
public type JsonRpcNotification record {
    *Notification;
    JSONRPC_VERSION jsonrpc;
};

# A successful (non-error) response to a request.
#
# + jsonrpc - The JSON-RPC protocol version
# + id - Identifier of the request
# + result - The result of the request
public type JsonRpcResponse record {|
    JSONRPC_VERSION jsonrpc;
    RequestId id;
    ServerResult result;
|};

// Standard JSON-RPC error codes
public const PARSE_ERROR = -32700;
public const INVALID_REQUEST = -32600;
public const METHOD_NOT_FOUND = -32601;
public const INVALID_PARAMS = -32602;
public const INTERNAL_ERROR = -32603;

# A response to a request that indicates an error occurred.
#
# + jsonrpc - The JSON-RPC protocol version
# + id - Identifier of the request
# + error - The error information
public type JsonRpcError record {
    JSONRPC_VERSION jsonrpc;
    RequestId id;
    record {
        # The error type that occurred
        int code;
        # A short description of the error. The message SHOULD be limited to a concise single sentence.
        string message;
        # Additional information about the error. The value of this member is defined by the sender (e.g. detailed error information, nested errors etc.).
        anydata data?;
    } 'error;
};

# A response that indicates success but carries no data.
public type EmptyResult Result;

# This notification can be sent by either side to indicate that it is cancelling a previously-issued request.
#
# The request SHOULD still be in-flight, but due to communication latency, it is always possible that this notification 
# MAY arrive after the request has already finished.
#
# This notification indicates that the result will be unused, so any associated processing SHOULD cease.
#
# A client MUST NOT attempt to cancel its `initialize` request.
#
# + method - The method name for this notification
# + params - The parameters for the cancellation notification
public type CancelledNotification record {|
    *Notification;
    "notifications/cancelled" method;
    record {|
        # The ID of the request to cancel.
        #
        # This MUST correspond to the ID of a request previously issued in the same direction.
        RequestId requestId;
        # An optional string describing the reason for the cancellation. This MAY be logged or presented to the user.
        string? reason = ();
    |} params;
|};

# This request is sent from the client to the server when it first connects, asking it to begin initialization.
#
# + method - Method name for the request
# + params - Parameters for the initialize request
type InitializeRequest record {|
    *Request;
    "initialize" method;
    record {|
        # The latest version of the Model Context Protocol that the client supports. 
        # The client MAY decide to support older versions as well.
        string protocolVersion;
        # Capabilities supported by the client
        ClientCapabilities capabilities;
        # Information about the client implementation
        Implementation clientInfo;
    |} params;
|};

# After receiving an initialize request from the client, the server sends this response.
#
# + protocolVersion - The version of the Model Context Protocol that the server wants to use.
# This may not match the version that the client requested.
# If the client cannot support this version, it MUST disconnect.
# + capabilities - The capabilities of the server.
# + serverInfo - Information about the server implementation
# + instructions - Instructions describing how to use the server and its features.
# This can be used by clients to improve the LLM's understanding of available tools, resources, etc.
# It can be thought of like a "hint" to the model.
# For example, this information MAY be added to the system prompt.
public type InitializeResult record {|
    *Result;
    string protocolVersion;
    ServerCapabilities capabilities;
    Implementation serverInfo;
    string instructions?;
|};

# This notification is sent from the client to the server after initialization has finished.
#
# + method - The method identifier for the notification, must be "notifications/initialized"
public type InitializedNotification record {|
    *Notification;
    "notifications/initialized" method;
|};

# Capabilities a client may support. Known capabilities are defined here, in this schema,
# but this is not a closed set: any client can define its own, additional capabilities.
#
# + experimental - Experimental, non-standard capabilities that the client supports.
# + roots - Present if the client supports listing roots.
# + sampling - Present if the client supports sampling from an LLM. 
public type ClientCapabilities record {
    record {|record {}...;|} experimental?;
    record {|
        # Whether the client supports notifications for changes to the roots list.
        boolean listChanged?;
    |} roots?;
    record {} sampling?;
};

# Capabilities that a server may support. Known capabilities are defined here, in this schema,
# but this is not a closed set: any server can define its own, additional capabilities.
#
# + experimental - Experimental, non-standard capabilities that the server supports.
# + logging - Present if the server supports sending log messages to the client.
# + completions - Present if the server supports argument autocompletion suggestions.
# + prompts - Present if the server offers any prompt templates.
# + resources - Present if the server offers any resources to read.
# + tools - Present if the server offers any tools to call.
public type ServerCapabilities record {
    record {|record {}...;|} experimental?;
    record {} logging?;
    record {} completions?;
    record {|
        # Whether this server supports notifications for changes to the prompt list.
        boolean listChanged?;
    |} prompts?;
    record {|
        # Whether this server supports subscribing to resource updates.
        boolean subscribe?;
        # Whether this server supports notifications for changes to the resource list.
        boolean listChanged?;
    |} resources?;
    record {|
        # Whether this server supports notifications for changes to the tool list.
        boolean listChanged?;
    |} tools?;
};

# Describes the name and version of an MCP implementation.
#
# + name - The name of the implementation
# + version - The version of the implementation
public type Implementation record {|
    string name;
    string version;
|};

# A ping, issued by either the server or the client, to check that 
# the other party is still alive. The receiver must promptly respond, 
# or else may be disconnected.
#
# + method - The method name
public type PingRequest record {|
    *Request;
    "ping" method;
|};

# An out-of-band notification used to inform the receiver of a progress update for a long-running request.
#
# + method - The method name for the notification
# + params - The parameters for the progress notification
public type ProgressNotification record {|
    *Notification;
    "notifications/progress" method;
    record {
        # The progress token which was given in the initial request, 
        # used to associate this notification with the request that is proceeding.
        ProgressToken progressToken;
        # The progress thus far. This should increase every time progress is made, 
        # even if the total is unknown.
        int progress;
        # Total number of items to process (or total progress required), if known.
        int total?;
        # An optional message describing the current progress.
        string message?;
        record {} _meta?;
    } params;
|};

# Represents a paginated request with optional cursor-based pagination.
#
# + params - Optional pagination parameters
public type PaginatedRequest record {|
    record {|
        # An opaque token representing the current pagination position.
        # If provided, the server should return results starting after this cursor.
        Cursor cursor?;
    |} params?;
|};

# Result that supports pagination
#
# + nextCursor - An opaque token representing the pagination position after the last returned result.
# If present, there may be more results available.
public type PaginatedResult record {|
    *Result;
    Cursor nextCursor?;
|};

# An optional notification from the server to the client, informing it that the list of resources it can read from has changed. 
# This may be issued by servers without any previous subscription from the client.
#
# + method - The JSON-RPC method name for resource list changed notifications
public type ResourceListChangedNotification record {|
    *Notification;
    "notifications/resources/list_changed" method;
|};

# A notification from the server to the client, informing it that a resource has changed and may need to be read again.
# This should only be sent if the client previously sent a resources/subscribe request.
#
# + method - The JSON-RPC method name for resource updated notifications
public type ResourceUpdatedNotification record {|
    *Notification;
    "notifications/resources/updated" method;
    # The parameters for the resource updated notification
    record {
        # The URI of the resource that has been updated. This might be a sub-resource of the one 
        # that the client actually subscribed to.
        string uri;
        record {} _meta?;
    } params;
|};

# The contents of a specific resource or sub-resource.
#
# + uri - The URI of this resource.
# + mimeType - The MIME type of this resource, if known.
public type ResourceContents record {|
    string uri;
    string mimeType?;
|};

# Text resource contents
#
# + text - The text of the item. This must only be set if the item can actually be represented as text (not binary data).
public type TextResourceContents record {|
    *ResourceContents;
    string text;
|};

# Binary resource contents
#
# + blob - A base64-encoded string representing the binary data of the item.
public type BlobResourceContents record {|
    *ResourceContents;
    string blob;
|};

# The sender or recipient of messages and data in a conversation.
public type Role "user"|"assistant";

# The contents of a resource, embedded into a prompt or tool call result.
#
# It is up to the client how best to render embedded resources for the benefit
# of the LLM and/or the user.
#
# + type - The type of content
# + resource - The resource content
# + annotations - Optional annotations for the client
public type EmbeddedResource record {|
    "resource" 'type;
    TextResourceContents|BlobResourceContents 'resource;
    Annotations annotations?;
|};

# An optional notification from the server to the client, informing it that
# the list of prompts it offers has changed. This may be issued by servers
# without any previous subscription from the client.
#
# + method - The JSON-RPC method name for prompt list changed notifications
public type PromptListChangedNotification record {|
    *Notification;
    "notifications/prompts/list_changed" method;
|};

# Sent from the client to request a list of tools the server has.
#
# + method - The method identifier for this request
public type ListToolsRequest record {|
    *PaginatedRequest;
    "tools/list" method;
|};

# The server's response to a tools/list request from the client.
#
# + tools - A list of tools available on the server.
public type ListToolsResult record {|
    *PaginatedResult;
    Tool[] tools;
|};

# The server's response to a tool call.
#
# Any errors that originate from the tool SHOULD be reported inside the result
# object, with `isError` set to true, _not_ as an MCP protocol-level error
# response. Otherwise, the LLM would not be able to see that an error occurred
# and self-correct.
#
# However, any errors in _finding_ the tool, an error indicating that the
# server does not support tool calls, or any other exceptional conditions,
# should be reported as an MCP error response.
#
# + content - The content of the tool call result
# + isError - Whether the tool call ended in an error.
# If not set, this is assumed to be false (the call was successful).
public type CallToolResult record {|
    (TextContent|ImageContent|AudioContent|EmbeddedResource)[] content;
    boolean isError?;
|};

# Used by the client to invoke a tool provided by the server.
#
# + method - The JSON-RPC method name
# + params - The parameters for the tool call
public type CallToolRequest record {|
    "tools/call" method;
    CallToolParams params;
|};

# Parameters for the tools/call request
#
# + name - The name of the tool to invoke
# + arguments - Optional arguments to pass to the tool
public type CallToolParams record {|
    string name;
    record {} arguments?;
|};

# An optional notification from the server to the client, informing it that the list of tools 
# it offers has changed. This may be issued by servers without any previous subscription from the client.
#
# + method - The JSON-RPC method name for tool list changed notifications
public type ToolListChangedNotification record {|
    *Notification;
    "notifications/tools/list_changed" method;
|};

# Additional properties describing a Tool to clients.
# NOTE: all properties in ToolAnnotations are **hints**.
# They are not guaranteed to provide a faithful description of
# tool behavior (including descriptive properties like `title`).
# Clients should never make tool use decisions based on ToolAnnotations
# received from untrusted servers.
#
# + title - A human-readable title for the tool.
# + readOnlyHint - If true, the tool does not modify its environment.
# Default: false
# + destructiveHint - If true, the tool may perform destructive updates to its environment.
# If false, the tool performs only additive updates.
# (This property is meaningful only when `readOnlyHint == false`)
# Default: true
# + idempotentHint - If true, calling the tool repeatedly with the same arguments
# will have no additional effect on the its environment.
# (This property is meaningful only when `readOnlyHint == false`)
# Default: false
# + openWorldHint - If true, this tool may interact with an "open world" of external
# entities. If false, the tool's domain of interaction is closed.
# For example, the world of a web search tool is open, whereas that
# of a memory tool is not.
# Default: true
public type ToolAnnotations record {|
    string title?;
    boolean readOnlyHint?;
    boolean destructiveHint?;
    boolean idempotentHint?;
    boolean openWorldHint?;
|};

# Definition for a tool the client can call.
#
# + name - The name of the tool
# + description - A human-readable description of the tool
# This can be used by clients to improve the LLM's understanding of available tools.
# + inputSchema - A JSON Schema object defining the expected parameters for the tool.
# + annotations - Optional additional tool information.
public type Tool record {|
    string name;
    string description?;
    record {
        "object" 'type;
        record {|record {}...;|} properties?;
        string[] required?;
    } inputSchema;
    ToolAnnotations annotations?;
|};

# Notification of a log message passed from server to client. If no logging/setLevel request has been 
# sent from the client, the server MAY decide which messages to send automatically.
#
# + method - The method name for the notification
# + params - The parameters for the logging message notification
public type LoggingMessageNotification record {|
    *Notification;
    "notifications/message" method;
    record {
        # The severity of this log message.
        LoggingLevel level;
        # An optional name of the logger issuing this message.
        string logger?;
        # The data to be logged, such as a string message or an object. Any JSON serializable type is allowed here.
        anydata data;
        record {} _meta?;
    } params;
|};

# The severity of a log message.
#
# These map to syslog message severities, as specified in RFC-5424:
# https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.1
public type LoggingLevel "debug"|"info"|"notice"|"warning"|"error"|"critical"|"alert"|"emergency";

# Optional annotations for the client. The client can use annotations to inform how objects are used or displayed
#
# + audience - Describes who the intended customer of this object or data is.
# This can include multiple entries to indicate content useful for multiple audiences (e.g., `["user", "assistant"]`).
# + priority - Describes how important this data is for operating the server.
# A value of 1 means "most important," and indicates that the data is effectively required,
# while 0 means "least important," and indicates that the data is entirely optional.
public type Annotations record {|
    Role[] audience?;
    decimal priority?;
|};

# Text provided to or from an LLM.
#
# + type - The type of content
# + text - The text content of the message
# + annotations - Optional annotations for the client
public type TextContent record {|
    "text" 'type;
    string text;
    Annotations annotations?;
|};

# An image provided to or from an LLM.
#
# + type - The type of content
# + data - The base64-encoded image data
# + mimeType - The MIME type of the image. Different providers may support different image types.
# + annotations - Optional annotations for the client
public type ImageContent record {|
    "image" 'type;
    string data;
    string mimeType;
    Annotations annotations?;
|};

# Audio provided to or from an LLM.
#
# + type - The type of content
# + data - The base64-encoded audio data
# + mimeType - The MIME type of the audio. Different providers may support different audio types.
# + annotations - Optional annotations for the client
public type AudioContent record {|
    "audio" 'type;
    string data;
    string mimeType;
    Annotations annotations?;
|};

// Client messages
# Represents a request sent from the client to the server.
public type ClientRequest PingRequest|InitializeRequest|CallToolRequest|ListToolsRequest;

# Represents a notification sent from the client to the server.
public type ClientNotification CancelledNotification|ProgressNotification|InitializedNotification;

# Represents a result sent from the client to the server.
public type ClientResult EmptyResult;

// Server messages
# Represents a response sent from the server to the client.
public type ServerRequest PingRequest;

# Represents a notification sent from the server to the client.
public type ServerNotification CancelledNotification
    |ProgressNotification
    |LoggingMessageNotification
    |ResourceUpdatedNotification
    |ResourceListChangedNotification
    |ToolListChangedNotification
    |PromptListChangedNotification;

# Represents a result sent from the server to the client.
public type ServerResult InitializeResult|CallToolResult|ListToolsResult|EmptyResult;
