// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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

import ballerina/mcp;
import ballerina/test;

type FileDeletion record {|
    boolean confirmed;
|};

@mcp:StreamableHttpConfig {info: {name: "elicitation", version: "1.0.0"}}
service mcp:StreamableHttpService /elicitation on new mcp:StreamableHttpListener(8793) {
    # Deletes a file after the user confirms.
    #
    # + path - The file to delete
    # + context - The input of this round
    # + return - The outcome, or a request to confirm
    remote isolated function deleteFile(string path, mcp:Context context) returns string|mcp:InputRequiredResult {
        FileDeletion? deletion = context.acceptedContent("confirm");
        if deletion is () {
            return {
                inputRequests: {
                    "confirm": mcp:elicitForm(string `Delete ${path}?`,
                            {properties: {confirmed: {'type: "boolean"}}, required: ["confirmed"]})
                }
            };
        }
        return deletion.confirmed ? string `deleted ${path}` : string `kept ${path}`;
    }
}

isolated function confirmDeletion(mcp:InputRequest inputRequest) returns mcp:InputResponse|mcp:ClientError =>
    {action: "accept", content: {confirmed: true}};

@test:Config
function testBasicToolElicitsThroughContext() returns error? {
    mcp:StreamableHttpClient elicitingClient = check new ("http://localhost:8793/elicitation",
        elicitationHandler = confirmDeletion);
    _ = check elicitingClient->connect();

    mcp:ListToolsResult toolList = check elicitingClient->listTools();
    mcp:ToolDefinition tool = toolList.tools[0];
    test:assertEquals((tool.inputSchema.properties ?: {}).keys(), ["path"]);
    test:assertEquals(tool.outputSchema, {"type": "string"});

    mcp:CallToolResult callResult = check elicitingClient->callTool({name: "deleteFile", arguments: {"path": "a.txt"}});
    test:assertEquals(callResult.content[0], <mcp:TextContent>{'type: "text", text: "deleted a.txt"});
    check elicitingClient->close();
}
