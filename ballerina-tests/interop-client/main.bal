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
import ballerina/mcp.v2 as mcpv2;

configurable string interopUrl = ?;

public function main() returns error? {
    mcpv2:ProtocolMode[] protocolModes = ["legacy", "auto", "modern"];
    foreach mcpv2:ProtocolMode protocolMode in protocolModes {
        mcpv2:StreamableHttpClient peerClient = check new (interopUrl, protocolMode = protocolMode);
        _ = check peerClient->connect();
        mcpv2:CallToolResult addResult = check peerClient->callTool({name: "add", arguments: {"firstValue": 2, "secondValue": 3}});
        mcpv2:TextContent addText = check addResult.content[0].ensureType();
        if addText.text != "5" {
            return error("Unexpected addition result");
        }
        mcpv2:CallToolResult echoResult = check peerClient->callTool({name: "echo", arguments: {"region": "世界"}});
        mcpv2:TextContent echoText = check echoResult.content[0].ensureType();
        if echoText.text != "世界" {
            return error("Unexpected mirrored-header result");
        }
        if protocolMode == "modern" {
            check verifyToolListCaching(peerClient);
        }
        check peerClient->close();
        io:println(protocolMode, " HTTP/SSE add and mirrored-header echo PASS");
    }
    check verifyFormElicitation();
}

// The peer's bookTable tool asks for the seat count and checks its request state came back intact.
function verifyFormElicitation() returns error? {
    mcpv2:StreamableHttpClient peerClient = check new (interopUrl, protocolMode = "modern",
        elicitationHandler = answerSeats);
    _ = check peerClient->connect();
    mcpv2:CallToolResult bookResult = check peerClient->callTool({name: "bookTable", arguments: {"name": "Ada"}});
    mcpv2:TextContent bookText = check bookResult.content[0].ensureType();
    if bookText.text != "booked 4 for Ada" {
        return error(string `Unexpected booking result: ${bookText.text}`);
    }
    check peerClient->close();
    io:println("modern form elicitation PASS");
}

isolated function answerSeats(mcpv2:ElicitRequest inputRequest) returns mcpv2:ElicitResult|mcpv2:ClientError {
    mcpv2:FormElicitationParams|mcpv2:UrlElicitationParams params = inputRequest.params;
    if params !is mcpv2:FormElicitationParams || !params.requestedSchema.properties.hasKey("seats") {
        return error mcpv2:ClientError("Expected a form asking for seats");
    }
    return {action: "accept", content: {seats: 4}};
}

// A listing within the peer's hinted TTL must not reach the peer; a peer that sends no TTL is listed every time.
function verifyToolListCaching(mcpv2:StreamableHttpClient peerClient) returns error? {
    mcpv2:ListToolsResult firstList = check peerClient->listTools();
    int listingsBefore = check peerListingCount(peerClient);
    _ = check peerClient->listTools();
    int repeatListings = check peerListingCount(peerClient) - listingsBefore;
    int expectedListings = (firstList.ttlMs ?: 0) > 0 ? 0 : 1;
    if repeatListings != expectedListings {
        return error(string `Expected ${expectedListings} tools/list request(s) for ttlMs ${firstList.ttlMs.toString()}, got ${repeatListings}`);
    }
    _ = check peerClient->listTools(cacheMode = "refresh");
    if check peerListingCount(peerClient) != listingsBefore + repeatListings + 1 {
        return error("A refreshed tools/list did not reach the peer");
    }
    io:println("modern tools/list caching with ttlMs ", firstList.ttlMs, " PASS");
}

function peerListingCount(mcpv2:StreamableHttpClient peerClient) returns int|error {
    mcpv2:CallToolResult countResult = check peerClient->callTool({name: "listCount"});
    mcpv2:TextContent countText = check countResult.content[0].ensureType();
    return int:fromString(countText.text);
}
