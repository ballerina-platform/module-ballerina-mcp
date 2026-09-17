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
public type TransportError distinct Error & ClientError;

# Error for protocol negotiation, validation, or server response failures.
public type ProtocolError distinct Error & ClientError;

# Error for invalid or unexpected responses from the server.
type ServerResponseError distinct ProtocolError;

# Error for failures occurring within client operations.
public type ClientError distinct Error;

# Error for failures while processing SSE event streams.
type SseEventStreamError distinct StreamError;

# Error for JSON-RPC message transformation failures during streaming.
type JsonRpcMessageTransformationError distinct StreamError;

# Error when required data is missing from an SSE event.
type MissingSseDataError distinct JsonRpcMessageTransformationError;

# Error for failures converting JSON to JsonRpcMessage.
type TypeConversionError distinct JsonRpcMessageTransformationError;

# Error when an invalid message type is received from the server.
type InvalidMessageTypeError distinct ServerResponseError;

# Error when the server response is malformed or unexpected.
type MalformedResponseError distinct ServerResponseError;

# Error for failures during HTTP transport operations.
type StreamableHttpTransportError distinct TransportError;

# Error for failures during HTTP client operations.
type HttpClientError distinct StreamableHttpTransportError;

# Error for unsupported content types in HTTP responses.
type UnsupportedContentTypeError distinct StreamableHttpTransportError;

# Error for failures during session operations.
type SessionOperationError distinct StreamableHttpTransportError;

# Error for failures while parsing HTTP response content.
type ResponseParsingError distinct StreamableHttpTransportError & ProtocolError;

# Error for failures during SSE stream establishment.
type SseStreamEstablishmentError distinct StreamableHttpTransportError;

# Error for operations attempted before transport initialization.
type UninitializedTransportError distinct ClientError;

# Error for failures during client initialization.
type ClientInitializationError distinct ClientError;

# Error for protocol version negotiation failures.
type ProtocolVersionError distinct ClientInitializationError & ProtocolError;

# Error for failures during tool listing operations.
type ListToolsError distinct ClientError;

# Error for failures during tool execution operations.
public type ToolCallError distinct ClientError;

# Errors for failures occurring during server operations.
public type ServerError distinct Error;

# Custom error type for dispatcher service operations.
type DispatcherError distinct ServerError;

# Error for failures while binding tool parameters from the incoming request,
# such as missing or invalid header values.
type ParameterBindingError distinct ServerError;

# Error for failures while obtaining authorization for a request.
public type AuthorizationError distinct StreamableHttpTransportError;

# Error for an invalid or incomplete `OAuthConfig`.
type OAuthConfigError distinct Error;

# Error while discovering protected resource or authorization server metadata.
type OAuthDiscoveryError distinct Error;

# Error while constructing or validating an authorization code exchange.
type OAuthAuthorizationError distinct Error;

# Error while requesting or refreshing a token at the token endpoint.
type OAuthTokenError distinct Error;

# Error when the token endpoint rejects the grant, such as an expired authorization code or
# a revoked refresh token.
type OAuthInvalidGrantError distinct OAuthTokenError;
