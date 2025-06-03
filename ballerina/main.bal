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

import ballerina/io;

Client mcpClient = new ("http://localhost:3000/mcp", {"name": "MCP Client", "version": "1.0.0"});
record {
    string name;
    string description?;
}[] tools = [];

// Change to remove functions in the client
public function main() returns error? {
    check mcpClient->initialize();
    // stream<JSONRPCServerMessage, error?> serverMessages = check mcpClient.subscribeToServerMessages();
    //             check from JSONRPCServerMessage serverMessage in serverMessages
    //             do {
    //                 io:println("Received server message: ", serverMessage);
    //             };
    check listTools();
    // foreach var tool in tools {
    //     check callTool(tool.name);
    // }
    // // let's introduce close and let the user implement this.
    // check mcpClient.waitForCompletion();
}

function listTools() returns error? {
    ListToolsResult toolsResult = check mcpClient->listTools();
    foreach Tool tool in toolsResult.tools {
        io:println("Tool Name: ", tool.name);
        tools.push({
            name: tool.name,
            description: tool.description
        });
    }
}

// function callTool(string name) returns error? {
//     io:println("\nCalling tool: " + name);
//     JSONRPCServerMessage|stream<JSONRPCServerMessage, error?> result = check mcpClient.callTool({
//         name: name,
//         arguments: {"name": "itsuki"}
//     });
//     if result is JSONRPCServerMessage {
//         if result is JSONRPCResponse {
//             ServerResult serverResult = result.result;
//             if serverResult is CallToolResult {
//                 io:println("Tool call result: ", serverResult);
//             } else {
//                 return error CallToolError("Received unexpected response type for tool call: " + serverResult.toString());
//             }
//         } else if result is JSONRPCNotification {
//             io:println("Received notification for tool call: ", result);
//         }
//     } else if result is stream<JSONRPCServerMessage, error?> {
//         check from JSONRPCServerMessage serverMessage in 'result
//             do {
//                 check handleMessage(serverMessage);
//             };
//     }
// }

// function executeWithDefaultValues(JSONRPCServerMessage notif) returns error? {
//     io:println("Received notification: ", notif);
// }

// function handleMessage(JSONRPCServerMessage serverMessage) returns error? {
//     if serverMessage is JSONRPCResponse {
//         io:println("Received message for tool call: ", serverMessage);
//     } else if serverMessage is JSONRPCNotification {
//         io:println("Received notification for tool call: ", serverMessage);
//     } else if serverMessage is JSONRPCError {
//         io:println("Received error for tool call: ", serverMessage);
//     } else {
//         return error CallToolError("Received unexpected response type for tool call: " + serverMessage.toString());
//     }
// }
