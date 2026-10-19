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

enum Seating {
    INDOOR = "indoor",
    PATIO = "patio"
}

type TableBooking record {|
    # Who the table is for
    string name;
    # How many people are coming
    int guests;
    # Where to sit
    Seating seating;
    # Anything the kitchen should know
    string notes?;
    # Whether a high chair is needed
    boolean highChair = false;
|};

@mcp:StreamableHttpConfig {info: {name: "booking", version: "1.0.0"}}
service mcp:StreamableHttpService /booking on new mcp:StreamableHttpListener(8794) {
    # Books a table, asking the user for the details.
    #
    # + context - The input of this round
    # + return - The confirmation, or a request for the booking details
    remote isolated function bookTable(mcp:Context context) returns string|mcp:InputRequiredResult {
        TableBooking? booking = context.acceptedContent("booking");
        if booking is () {
            return {inputRequests: {"booking": mcp:elicitForm("Book a table", TableBooking)}};
        }
        return string `${booking.name}: ${booking.guests} on the ${booking.seating}`;
    }
}

isolated function fillBooking(mcp:InputRequest inputRequest) returns mcp:InputResponse|mcp:ClientError =>
    {action: "accept", content: {name: "Ada", guests: 2, seating: "patio"}};

@test:Config
function testRecordTypeFormElicitation() returns error? {
    mcp:StreamableHttpClient bookingClient = check new ("http://localhost:8794/booking",
        elicitationHandler = fillBooking);
    _ = check bookingClient->connect();

    mcp:CallToolResult|mcp:InputRequiredResult firstRound = check bookingClient->callToolOnce({name: "bookTable"});
    if firstRound !is mcp:InputRequiredResult {
        test:assertFail("expected an input-required result");
    }
    mcp:InputRequest bookingRequest = (firstRound.inputRequests ?: {}).get("booking");
    test:assertEquals(bookingRequest.params, <mcp:FormElicitationParams>{
        message: "Book a table",
        requestedSchema: {
            properties: {
                name: {'type: "string", description: "Who the table is for"},
                guests: {'type: "integer", description: "How many people are coming"},
                seating: {'type: "string", description: "Where to sit", 'enum: ["indoor", "patio"]},
                notes: {'type: "string", description: "Anything the kitchen should know"},
                highChair: {'type: "boolean", description: "Whether a high chair is needed"}
            },
            required: ["name", "guests", "seating"]
        }
    });

    mcp:CallToolResult callResult = check bookingClient->callTool({name: "bookTable"});
    test:assertEquals(callResult.content[0], <mcp:TextContent>{'type: "text", text: "Ada: 2 on the patio"});
    check bookingClient->close();
}
