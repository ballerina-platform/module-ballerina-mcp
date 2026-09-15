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

import ballerina/io;
import ballerina/mcp;

configurable string interopUrl = ?;

public function main() returns error? {
    mcp:ProtocolMode[] protocolModes = ["legacy", "auto", "modern"];
    foreach mcp:ProtocolMode protocolMode in protocolModes {
        mcp:StreamableHttpClient peerClient = check new (interopUrl, protocolMode = protocolMode);
        _ = check peerClient->connect();
        mcp:CallToolResult addResult = check peerClient->callTool({name: "add", arguments: {"firstValue": 2, "secondValue": 3}});
        mcp:TextContent addText = check addResult.content[0].ensureType();
        if addText.text != "5" {
            return error("Unexpected addition result");
        }
        mcp:CallToolResult echoResult = check peerClient->callTool({name: "echo", arguments: {"region": "世界"}});
        mcp:TextContent echoText = check echoResult.content[0].ensureType();
        if echoText.text != "世界" {
            return error("Unexpected mirrored-header result");
        }
        check peerClient->close();
        io:println(protocolMode, " HTTP/SSE add and mirrored-header echo PASS");
    }
}
