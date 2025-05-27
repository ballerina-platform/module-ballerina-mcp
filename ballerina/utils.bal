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

function handleInitializeResponse(JSONRPCServerMessage|stream<JSONRPCServerMessage, error?>|() response) returns InitializeResult|error {
    if response is stream<JSONRPCServerMessage, error?> {
        (record {|JSONRPCServerMessage value;|}|error)? message = response.next();
        if message is () {
            return error ClientInitializationError("Failed to receive an initialize response");
        }
        if message is error {
            return message;
        }
        JSONRPCServerMessage serverMessage = message.value;
        if serverMessage is JSONRPCResponse {
            ServerResult result = serverMessage.result;
            if result is InitializeResult {
                return result;
            } else {
                return error ClientInitializationError("Received unexpected response type for initialization");
            }
        } else {
            return error ClientInitializationError("Received unexpected response type for initialization");
        }
    } else if response is JSONRPCServerMessage {
        if response is JSONRPCResponse {
            ServerResult result = response.result;
            if result is InitializeResult {
                return result;
            } else {
                return error ClientInitializationError("Received unexpected response type for initialization");
            }
        } else {
            return error ClientInitializationError("Received unexpected response type for initialization");
        }
    } else {
        return error ClientInitializationError("No response received for initialization");
    }
} 

function handleListToolResult(JSONRPCServerMessage|stream<JSONRPCServerMessage, error?>|() response) returns ListToolsResult|error {
    if response is stream<JSONRPCServerMessage, error?> {
        (record {|JSONRPCServerMessage value;|}|error)? message = response.next();
        if message is () {
            return error ListToolError("Failed to receive a list tools response");
        }
        if message is error {
            return message;
        }
        JSONRPCServerMessage serverMessage = message.value;
        if serverMessage is JSONRPCResponse {
            ServerResult result = serverMessage.result;
            if result is ListToolsResult {
                return result;
            } else {
                return error ListToolError("Received unexpected response type for list tools");
            }
        } else {
            return error ListToolError("Received unexpected response type for list tools");
        }
    } else if response is JSONRPCServerMessage {
        if response is JSONRPCResponse {
            ServerResult result = response.result;
            if result is ListToolsResult {
                return result;
            } else {
                return error ListToolError("Received unexpected response type for list tools");
            }
        } else {
            return error ListToolError("Received unexpected response type for list tools");
        }
    } else {
        return error ListToolError("No response received for list tools");
    }
}
