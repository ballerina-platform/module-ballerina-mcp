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

configurable int interopPort = ?;
listener mcp:StreamableHttpListener interopListener = new (interopPort);

@mcp:StreamableHttpConfig {info: {name: "ballerina-interop", version: "2.0.0"}}
service mcp:StreamableHttpService /mcp on interopListener {
    remote isolated function add(int firstValue, int secondValue) returns int => firstValue + secondValue;

    remote isolated function echo(
            @mcp:Argument {headerName: "Region"} string region) returns string => region;
}

@mcp:StreamableHttpConfig {info: {name: "ballerina-stateful-interop", version: "2.0.0"}}
service mcp:StreamableHttpService /stateful on interopListener {
    remote isolated function sessionIdentity(mcp:HttpSession sessionValue) returns string => sessionValue.getSessionId();
}

@mcp:StreamableHttpConfig {info: {name: "ballerina-modern-interop", version: "2.0.0"}, protocolMode: "modern"}
service mcp:StreamableHttpAdvancedService /modern on interopListener {
    remote isolated function onListTools() returns mcp:ListToolsResult => {
        tools: [{name: "scalar", inputSchema: {'type: "object"}, outputSchema: {"type": "integer"}}]
    };

    remote isolated function onCallTool(mcp:CallToolParams callParams) returns mcp:CallToolResult => {
        content: [{'type: "text", text: "42"}],
        structuredContent: 42
    };
}

type SeatCount record {|
    # How many seats to book
    int seats;
|};

@mcp:StreamableHttpConfig {info: {name: "ballerina-elicitation-interop", version: "2.0.0"}}
service mcp:StreamableHttpService /elicitation on interopListener {
    // The module signs the request state, so getting the name back shows the client echoed it unchanged.
    remote isolated function bookTable(string name, mcp:Context context)
            returns string|mcp:InputRequiredResult|error {
        mcp:InputResponse? answer = context.elicitResult("seats");
        string? state = context.requestState();
        if answer is () || state is () {
            return {
                inputRequests: {"seats": mcp:elicitForm(string `How many seats for ${name}?`, SeatCount)},
                requestState: name
            };
        }
        if state != name {
            return error("Request state was altered");
        }
        SeatCount? seatCount = context.acceptedContent("seats");
        return seatCount is () ? string `not booked: ${answer.action}` : string `booked ${seatCount.seats} for ${name}`;
    }
}

isolated int cachedListingCount = 0;

@mcp:StreamableHttpConfig {
    info: {name: "ballerina-cached-interop", version: "2.0.0"},
    protocolMode: "modern",
    cacheHints: {
        discover: {ttlMs: 300000, cacheScope: "public"},
        listTools: {ttlMs: 60000, cacheScope: "public"}
    }
}
service mcp:StreamableHttpAdvancedService /cached on interopListener {
    // The description changes on every listing, so a client can tell a cached list from a fresh one.
    remote isolated function onListTools() returns mcp:ListToolsResult {
        int listingNumber;
        lock {
            cachedListingCount += 1;
            listingNumber = cachedListingCount;
        }
        return {tools: [{name: "listing", description: listingNumber.toString(), inputSchema: {'type: "object"}}]};
    }

    remote isolated function onCallTool(mcp:CallToolParams callParams) returns mcp:CallToolResult => {content: []};
}
