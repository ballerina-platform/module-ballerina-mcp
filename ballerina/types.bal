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
public type JsonRpcMessage JsonRpcRequest|JsonRpcNotification|JsonRpcResponse;

public const LATEST_PROTOCOL_VERSION = "2025-03-26";
public const SUPPORTED_PROTOCOL_VERSIONS = [
    LATEST_PROTOCOL_VERSION,
    "2024-11-05",
    "2024-10-07"
];

public const JSONRPC_VERSION = "2.0";

// # Notification methods
public const NOTIFICATION_INITIALIZED = "notifications/initialized";

# A progress token, used to associate progress notifications with the original request.
public type ProgressToken string|int;

# An opaque token used to represent a cursor for pagination.
public type Cursor string;

# Parameters for the request
public type RequestParams record {
    # Optional parameters for the request
    record {
        # If specified, the caller is requesting out-of-band progress notifications for this request (as represented by notifications/progress).
        # The value of this parameter is an opaque token that will be attached to any subsequent notifications. The receiver is not obligated to provide these notifications.
        ProgressToken progressToken?;
    } _meta?;
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

# Base result type with common fields.
public type Result record {
    # This result property is reserved by the protocol to allow clients and servers
    # to attach additional metadata to their responses.
    record {} _meta?;
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
public const PARSE_ERROR = -32700;
public const INVALID_REQUEST = -32600;
public const METHOD_NOT_FOUND = -32601;
public const INVALID_PARAMS = -32602;
public const INTERNAL_ERROR = -32603;

// Library-defined error codes
public const NOT_ACCEPTABLE = -32001;
public const UNSUPPORTED_MEDIA_TYPE = -32002;

# A response to a request that indicates an error occurred.
public type JsonRpcError record {
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
};

# This request is sent from the client to the server when it first connects, asking it to begin initialization.
type InitializeRequest record {|
    *Request;
    # Method name for the request
    "initialize" method;
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
    NOTIFICATION_INITIALIZED method;
|};

# Capabilities a client may support. Known capabilities are defined here, in this schema,
# but this is not a closed set: any client can define its own, additional capabilities.
public type ClientCapabilities record {
    # Present if the client supports listing roots.
    record {
        # Whether the client supports notifications for changes to the roots list.
        boolean listChanged?;
    } roots?;
    # Present if the client supports sampling from an LLM. 
    record {} sampling?;
};

# Capabilities that a server may support. Known capabilities are defined here, in this schema,
# but this is not a closed set: any server can define its own, additional capabilities.
public type ServerCapabilities record {
    # Experimental, non-standard capabilities that the server supports.
    record {|record {}...;|} experimental?;
    # Present if the server supports sending log messages to the client.
    record {|record {}...;|} logging?;
    # Present if the server supports argument autocompletion suggestions.
    record {|record {}...;|} completions?;
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
};

# Describes the name and version of an MCP implementation.
public type Implementation record {
    # The name of the implementation
    string name;
    # The version of the implementation
    string version;
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

# The sender or recipient of messages and data in a conversation.
public type Role "user"|"assistant";

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
    "tools/list" method;
|};

# The server's response to a tools/list request from the client.
public type ListToolsResult record {
    *PaginatedResult;
    # A list of tools available on the server.
    Tool[] tools;
};

# The server's response to a tool call.
public type CallToolResult record {
    # The content of the tool call result
    (TextContent|ImageContent|AudioContent|EmbeddedResource)[] content;
    # Whether the tool call ended in an error.
    # If not set, this is assumed to be false (the call was successful).
    boolean isError?;
};

# Used by the client to invoke a tool provided by the server.
public type CallToolRequest record {|
    # The JSON-RPC method name
    "tools/call" method;
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

# Definition for a tool the client can call.
public type Tool record {
    # The name of the tool
    string name;
    # A human-readable description of the tool
    # This can be used by clients to improve the LLM's understanding of available tools.
    string description?;
    # A JSON Schema object defining the expected parameters for the tool.
    record {
        "object" 'type;
        record {|record {}...;|} properties?;
        string[] required?;
    } inputSchema;
    # Optional additional tool information.
    ToolAnnotations annotations?;
};

# Optional annotations for the client. The client can use annotations to inform how objects are used or displayed
public type Annotations record {|
    # Describes who the intended customer of this object or data is.
    # This can include multiple entries to indicate content useful for multiple audiences (e.g., `["user", "assistant"]`).
    Role[] audience?;
    # Describes how important this data is for operating the server.
    # A value of 1 means "most important," and indicates that the data is effectively required,
    # while 0 means "least important," and indicates that the data is entirely optional.
    decimal priority?;
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
    json schema?;
|};

# Annotation to mark a function as an MCP tool configuration.
public annotation McpToolConfig McpTool on object function;

# Defines a mcp service interface that handles incoming mcp requests.
public type AdvancedService distinct isolated service object {
    remote isolated function onListTools() returns ListToolsResult|error;
    remote isolated function onCallTool(CallToolParams params) returns CallToolResult|error;
};

public type Service distinct isolated service object {

};
