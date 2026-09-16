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
