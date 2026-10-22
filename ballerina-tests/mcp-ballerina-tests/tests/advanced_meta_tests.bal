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

// An mcp:AdvancedService builds the whole CallToolResult, so it can attach server-originated
// response _meta regardless of whether the client sent request _meta.
listener mcp:Listener advancedMetaListener = check new (8768);

@mcp:ServiceConfig {
    info: {name: "advanced-meta-test-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
service mcp:AdvancedService /mcp on advancedMetaListener {

    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {
            tools: [
                {
                    name: "ping",
                    description: "Returns a fixed response with server-originated metadata",
                    inputSchema: {"type": "object", "properties": {}}
                }
            ]
        };
    }

    remote isolated function onCallTool(mcp:CallToolParams params, mcp:Session? session)
            returns mcp:CallToolResult|mcp:ServerError {
        // Server-originated metadata, independent of the request.
        record {} responseMeta = {"serverId": "srv-1"};

        // Optionally fold in a client-supplied key, if present.
        if params._meta is record {} {
            record {} clientMeta = <record {}>params._meta;
            anydata traceId = clientMeta["traceId"];
            if traceId !is () {
                responseMeta["traceId"] = traceId;
            }
        }

        return {
            content: [{'type: "text", text: "pong"}],
            _meta: responseMeta
        };
    }
}

final mcp:StreamableHttpClient advancedMetaClient = check new ("http://localhost:8768/mcp");
final mcp:Implementation advancedMetaClientInfo = {name: "advanced-meta-test-client", version: "1.0.0"};

@test:Config
function testAdvancedServiceOriginatesResponseMetaWithoutRequestMeta() returns error? {
    check advancedMetaClient->initialize(advancedMetaClientInfo);

    // The client sends no _meta, yet the server attaches its own response _meta.
    mcp:CallToolResult result = check advancedMetaClient->callTool({name: "ping"});

    test:assertTrue(result._meta is record {},
            msg = "AdvancedService must be able to originate response _meta with no request _meta");
    record {} responseMeta = check result._meta.ensureType();
    test:assertEquals(responseMeta["serverId"], "srv-1");
    test:assertFalse(responseMeta.hasKey("traceId"),
            msg = "No client meta was sent, so no client-derived key should appear");
}

@test:Config {dependsOn: [testAdvancedServiceOriginatesResponseMetaWithoutRequestMeta]}
function testAdvancedServiceReadsRequestMetaAndReturnsOwn() returns error? {
    mcp:CallToolResult result = check advancedMetaClient->callTool({
        name: "ping",
        _meta: {"traceId": "trace-xyz"}
    });

    record {} responseMeta = check result._meta.ensureType();
    test:assertEquals(responseMeta["serverId"], "srv-1",
            msg = "Server-originated _meta must be present");
    test:assertEquals(responseMeta["traceId"], "trace-xyz",
            msg = "AdvancedService must be able to read request _meta via params._meta");
}
