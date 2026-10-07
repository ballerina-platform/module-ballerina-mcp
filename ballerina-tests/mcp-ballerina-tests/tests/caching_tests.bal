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

isolated int toolListingCount = 0;

@mcp:StreamableHttpConfig {
    info: {name: "cached-tools", version: "1.0.0"},
    protocolMode: "modern",
    cacheHints: {
        discover: {ttlMs: 300000, cacheScope: "public"},
        listTools: {ttlMs: 60000}
    }
}
service mcp:StreamableHttpAdvancedService /cached on new mcp:StreamableHttpListener(8790) {
    remote isolated function onListTools() returns mcp:ListToolsResult {
        lock {
            toolListingCount += 1;
        }
        return {tools: [{name: "echo", inputSchema: {'type: "object"}}]};
    }

    remote isolated function onCallTool(mcp:CallToolParams params) returns mcp:CallToolResult => {content: []};
}

isolated function listingCount() returns int {
    lock {
        return toolListingCount;
    }
}

@test:Config {}
function testClientReusesToolListWithinServerTtl() returns error? {
    mcp:StreamableHttpClient cachingClient = check new ("http://localhost:8790/cached", protocolMode = "modern");
    mcp:DiscoverResult discovered = check cachingClient->discover();
    test:assertEquals(discovered.ttlMs, 300000);
    test:assertEquals(discovered.cacheScope, "public");
    _ = check cachingClient->connect();

    int initialCount = listingCount();
    mcp:ListToolsResult firstList = check cachingClient->listTools();
    test:assertEquals(firstList.ttlMs, 60000);
    test:assertEquals(firstList.cacheScope, "private");
    _ = check cachingClient->listTools();
    test:assertEquals(listingCount(), initialCount + 1);

    _ = check cachingClient->listTools(cacheMode = "refresh");
    test:assertEquals(listingCount(), initialCount + 2);
    check cachingClient->close();
}
