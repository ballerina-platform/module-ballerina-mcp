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

isolated map<int> paginatedListings = {};

// Serves its tools in two pages and rejects any other cursor with INVALID_PARAMS.
@StreamableHttpServiceConfig {info: {name: "paginated", version: "1"}, cacheHints: {listTools: {ttlMs: 60000}}}
service StreamableHttpAdvancedService /paginated on cachingListener {
    remote isolated function onListTools(Cursor? cursor) returns ListToolsResult|ServerError {
        string page = cursor ?: "first";
        lock {
            paginatedListings[page] = (paginatedListings[page] ?: 0) + 1;
        }
        if cursor is () {
            return {tools: [{name: "alpha", inputSchema: {'type: "object"}}], nextCursor: "page-2"};
        }
        if cursor == "page-2" {
            return {tools: [{name: "beta", inputSchema: {'type: "object"}}]};
        }
        return error InvalidParamsError("Unknown cursor");
    }

    remote isolated function onCallTool(CallToolParams params) returns CallToolResult =>
        {content: [{'type: "text", text: "called " + params.name}]};
}

isolated function paginatedListingCount(string page) returns int {
    lock {
        return paginatedListings[page] ?: 0;
    }
}

isolated function toolNames(ListToolsResult listing) returns string[] =>
    from ToolDefinition toolInfo in listing.tools select toolInfo.name;

@test:Config {}
function testPaginatingServiceReturnsPagesOnBothProtocols() returns error? {
    ProtocolMode[] protocolModes = ["modern", "legacy"];
    foreach ProtocolMode protocolMode in protocolModes {
        StreamableHttpClient pagedClient = check new ("http://localhost:3222/paginated", protocolMode = protocolMode);
        _ = check pagedClient->connect();
        ListToolsResult firstPage = check pagedClient->listTools();
        test:assertEquals(toolNames(firstPage), ["alpha"], protocolMode);
        test:assertEquals(firstPage.nextCursor, "page-2", protocolMode);
        ListToolsResult secondPage = check pagedClient->listTools(cursor = "page-2");
        test:assertEquals(toolNames(secondPage), ["beta"], protocolMode);
        test:assertEquals(secondPage.nextCursor, (), protocolMode);

        CallToolResult called = check pagedClient->callTool({name: "beta"});
        test:assertEquals(called.content, [{'type: "text", text: "called beta"}], protocolMode);
        check pagedClient->close();
    }
}

@test:Config {}
function testClientCachesEachPageAndDropsAllOnRejectedCursor() returns error? {
    StreamableHttpClient pagedClient = check new ("http://localhost:3222/paginated", protocolMode = "modern");
    _ = check pagedClient->connect();
    int firstListings = paginatedListingCount("first");
    int secondListings = paginatedListingCount("page-2");

    foreach int _ in 0 ..< 2 {
        ListToolsResult firstPage = check pagedClient->listTools();
        test:assertEquals(toolNames(firstPage), ["alpha"]);
        ListToolsResult secondPage = check pagedClient->listTools(cursor = "page-2");
        test:assertEquals(toolNames(secondPage), ["beta"]);
    }
    test:assertEquals(paginatedListingCount("first"), firstListings + 1, "the first page must be cached");
    test:assertEquals(paginatedListingCount("page-2"), secondListings + 1, "each page must be cached under its cursor");

    ListToolsResult|ClientError rejected = pagedClient->listTools(cursor = "stale");
    if rejected !is ClientError {
        test:assertFail("a rejected cursor must fail the listing");
    }
    var rpcError = rejected.detail()["rpcError"];
    test:assertTrue(rpcError is JsonRpcError && rpcError.'error.code == INVALID_PARAMS, rejected.message());

    _ = check pagedClient->listTools();
    _ = check pagedClient->listTools(cursor = "page-2");
    test:assertEquals(paginatedListingCount("first"), firstListings + 2, "a rejected cursor must drop the first page");
    test:assertEquals(paginatedListingCount("page-2"), secondListings + 2, "a rejected cursor must drop every page");
    check pagedClient->close();
}

isolated function assertInvalidParams(ClientError failure, string expectedMessage) {
    var rpcError = failure.detail()["rpcError"];
    if rpcError is JsonRpcError {
        test:assertEquals(rpcError.'error.code, INVALID_PARAMS);
        test:assertEquals(rpcError.'error.message, expectedMessage);
        return;
    }
    // A legacy client reports the JSON-RPC error in its message.
    test:assertTrue(failure.message().includes(string `"code":${INVALID_PARAMS}`), failure.message());
    test:assertTrue(failure.message().includes(string `"message":"${expectedMessage}"`), failure.message());
}

@test:Config {}
function testRejectedCursorIsInvalidParamsOnBothProtocols() returns error? {
    ProtocolMode[] protocolModes = ["modern", "legacy"];
    foreach ProtocolMode protocolMode in protocolModes {
        StreamableHttpClient pagedClient = check new ("http://localhost:3222/paginated", protocolMode = protocolMode);
        _ = check pagedClient->connect();
        ListToolsResult|ClientError rejected = pagedClient->listTools(cursor = "stale");
        if rejected !is ClientError {
            test:assertFail("a rejected cursor must fail the listing");
        }
        assertInvalidParams(rejected, "Unknown cursor");
        check pagedClient->close();
    }
}
