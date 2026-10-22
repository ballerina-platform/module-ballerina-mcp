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

import ballerina/http;
import ballerina/test;

const string MOCK_SERVER_URL2 = "http://localhost:3272/mcp";

// Protocol version the mock server echoes back during initialization (controllable per test).
isolated string mockNegotiatedVersion2 = "2025-06-18";
// The MCP-Protocol-Version header value captured on the last non-initialize request.
isolated string? mockCapturedVersionHeader2 = ();
// Whether the initialize request carried an MCP-Protocol-Version header (it must not).
isolated boolean mockInitHadVersionHeader2 = false;

isolated function setMockNegotiatedVersion2(string version) {
    lock {
        mockNegotiatedVersion2 = version;
    }
}

isolated function resetMockCapturedState2() {
    lock {
        mockCapturedVersionHeader2 = ();
    }
    lock {
        mockInitHadVersionHeader2 = false;
    }
}

isolated function getMockCapturedVersionHeader2() returns string? {
    lock {
        return mockCapturedVersionHeader2;
    }
}

isolated function getMockInitHadVersionHeader2() returns boolean {
    lock {
        return mockInitHadVersionHeader2;
    }
}

// A minimal MCP-like HTTP server used to drive client-side protocol version negotiation behavior.
isolated service /mcp on new http:Listener(3272) {
    isolated resource function post .(@http:Payload json payload, http:Headers headers)
            returns http:Ok|http:Accepted|error {
        string method = check payload.method.ensureType();
        string|http:HeaderNotFoundError versionHeader = headers.getHeader(PROTOCOL_VERSION_HEADER);

        if method == REQUEST_INITIALIZE {
            lock {
                mockInitHadVersionHeader2 = versionHeader is string;
            }
            string negotiatedVersion;
            lock {
                negotiatedVersion = mockNegotiatedVersion2;
            }
            return <http:Ok>{
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: check payload.id,
                    result: {
                        protocolVersion: negotiatedVersion,
                        capabilities: {tools: {}},
                        serverInfo: {name: "mock-server", version: "1.0.0"}
                    }
                }
            };
        }

        lock {
            mockCapturedVersionHeader2 = versionHeader is string ? versionHeader : ();
        }

        if method == NOTIFICATION_INITIALIZED {
            return http:ACCEPTED;
        }

        // tools/list and any other request.
        return <http:Ok>{
            body: {
                jsonrpc: JSONRPC_VERSION,
                id: check payload.id,
                result: {tools: []}
            }
        };
    }
}

// The client must omit the header on initialize but send the negotiated version on all later requests.
@test:Config {}
function testClientSendsNegotiatedProtocolVersionHeader2() returns error? {
    setMockNegotiatedVersion2("2025-06-18");
    resetMockCapturedState2();

    StreamableHttpClient2 'client = check new (MOCK_SERVER_URL2);
    _ = check 'client->initializeLegacy();

    test:assertFalse(getMockInitHadVersionHeader2(),
            "initialize request must not carry an MCP-Protocol-Version header");

    ToolPage _ = check 'client->listTools();
    test:assertEquals(getMockCapturedVersionHeader2(), "2025-06-18",
            "subsequent requests must carry the negotiated MCP-Protocol-Version header");
}

// The client must accept a server that downgrades to an older supported version and send that version.
@test:Config {}
function testClientSendsDowngradedProtocolVersionHeader2() returns error? {
    setMockNegotiatedVersion2("2025-03-26");
    resetMockCapturedState2();

    StreamableHttpClient2 'client = check new (MOCK_SERVER_URL2);
    _ = check 'client->connect();

    ToolPage _ = check 'client->listTools();
    test:assertEquals(getMockCapturedVersionHeader2(), "2025-03-26",
            "client must send the downgraded negotiated version as the MCP-Protocol-Version header");
}

// The client must disconnect (error) if the server returns a version it does not support.
@test:Config {}
function testClientRejectsUnsupportedNegotiatedVersion2() returns error? {
    setMockNegotiatedVersion2("1999-01-01");

    StreamableHttpClient2 'client = check new (MOCK_SERVER_URL2);
    ConnectionInfo|ClientError result = 'client->connect();
    test:assertTrue(result is ProtocolVersionError,
            "client must reject an unsupported negotiated protocol version");
}
