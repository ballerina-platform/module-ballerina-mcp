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

import ballerina/test;

@test:Config {}
function testModernSseToolCallSkipsKeepAliveComments() returns error? {
    StreamableHttpClient2 modernClient = check new (mockUrl("sseKeepAlive"), protocolMode = "modern");
    _ = check modernClient->connect();
    ToolResult result = check modernClient->callTool({name: "echo"});
    test:assertEquals(result.content, [{'type: "text", text: "after keep-alive"}]);
    check modernClient->close();
}

@test:Config {}
function testLegacySseToolCallSkipsKeepAliveComments() returns error? {
    StreamableHttpClient2 legacyClient = check legacyMockClient("sseKeepAlive");
    ToolResult result = check legacyClient->callTool({name: "echo"});
    test:assertEquals(result.content, [{'type: "text", text: "after keep-alive"}]);
}

@test:Config {}
function testLegacySseToolCallSkipsPrimingEvents() returns error? {
    StreamableHttpClient2 legacyClient = check legacyMockClient("ssePriming");
    ToolResult result = check legacyClient->callTool({name: "echo"});
    test:assertEquals(result.content, [{'type: "text", text: "after priming"}]);
}
