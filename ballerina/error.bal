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

# Defines the common error type for the module.
public type Error distinct error;

# Errors due to unsupported content type.
public type UnsupportedContentTypeError distinct Error;

# Errors related to transport issues.
public type TransportError distinct Error;

# Errors related to client.
public type ClientError distinct Error;

# Errors related to uninitialized transport.
public type UninitializedTransportError distinct TransportError;

# Errors related to initialization of the transport.
public type TransportInitializationError distinct TransportError;

# Errors related to initialization of the client.
public type ClientInitializationError distinct ClientError;

# Errors related to list tools operation.
public type ListToolError distinct ClientError;

# Errors related to tool call operation.
public type CallToolError distinct ClientError;
