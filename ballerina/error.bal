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

# Defines the common base error type for this module.
public type Error distinct error;

# Error for failures during streaming operations.
public type StreamError distinct Error & ClientError;

# Error for failures during transport operations.
public type TransportError distinct Error;

# Error for invalid or unexpected responses from the server.
public type ServerResponseError distinct Error & ClientError;

# Error for failures occurring within client operations.
public type ClientError distinct Error;

# Error for failures while processing SSE event streams.
public type SseEventStreamError distinct StreamError;

# Error for JSON-RPC message transformation failures during streaming.
public type JsonRpcMessageTransformationError distinct StreamError;

# Error when required data is missing from an SSE event.
public type MissingSseDataError distinct JsonRpcMessageTransformationError;

# Error for failures converting JSON to JsonRpcMessage.
public type TypeConversionError distinct JsonRpcMessageTransformationError;

# Error when an invalid message type is received from the server.
public type InvalidMessageTypeError distinct ServerResponseError;

# Error when the server response is malformed or unexpected.
public type MalformedResponseError distinct ServerResponseError;

# Error for failures during HTTP transport operations.
public type StreamableHttpTransportError distinct TransportError & ClientError;

# Error for failures during HTTP client operations.
public type HttpClientError distinct StreamableHttpTransportError;

# Error for unsupported content types in HTTP responses.
public type UnsupportedContentTypeError distinct StreamableHttpTransportError;

# Error for failures during session operations.
public type SessionOperationError distinct StreamableHttpTransportError;

# Error for failures while parsing HTTP response content.
public type ResponseParsingError distinct StreamableHttpTransportError;

# Error for failures during SSE stream establishment.
public type SseStreamEstablishmentError distinct StreamableHttpTransportError;

# Error for operations attempted before transport initialization.
public type UninitializedTransportError distinct ClientError;

# Error for failures during client initialization.
public type ClientInitializationError distinct ClientError;

# Error for protocol version negotiation failures.
public type ProtocolVersionError distinct ClientInitializationError;

# Error for failures during tool listing operations.
public type ListToolsError distinct ClientError;

# Error for failures during tool execution operations.
public type ToolCallError distinct ClientError;

# Errors for failures occurring during server operations.
public type ServerError distinct Error;

# Custom error type for dispatcher service operations.
type DispatcherError distinct ServerError;
