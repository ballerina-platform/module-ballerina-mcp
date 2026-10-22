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

const string MOCK_SERVER_URL = "http://localhost:3202/mcp";

// Protocol version the mock server echoes back during initialization (controllable per test).
isolated string mockNegotiatedVersion = "2025-06-18";
// The MCP-Protocol-Version header value captured on the last non-initialize request.
isolated string? mockCapturedVersionHeader = ();
// Whether the initialize request carried an MCP-Protocol-Version header (it must not).
isolated boolean mockInitHadVersionHeader = false;

isolated function setMockNegotiatedVersion(string version) {
    lock {
        mockNegotiatedVersion = version;
    }
}

isolated function resetMockCapturedState() {
    lock {
        mockCapturedVersionHeader = ();
    }
    lock {
        mockInitHadVersionHeader = false;
    }
}

isolated function getMockCapturedVersionHeader() returns string? {
    lock {
        return mockCapturedVersionHeader;
    }
}

isolated function getMockInitHadVersionHeader() returns boolean {
    lock {
        return mockInitHadVersionHeader;
    }
}

// A minimal MCP-like HTTP server used to drive client-side protocol version negotiation behavior.
isolated service /mcp on new http:Listener(3202) {
    isolated resource function post .(@http:Payload json payload, http:Headers headers)
            returns http:Ok|http:Accepted|error {
        string method = check payload.method.ensureType();
        string|http:HeaderNotFoundError versionHeader = headers.getHeader(PROTOCOL_VERSION_HEADER);

        if method == REQUEST_INITIALIZE {
            lock {
                mockInitHadVersionHeader = versionHeader is string;
            }
            string negotiatedVersion;
            lock {
                negotiatedVersion = mockNegotiatedVersion;
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
            mockCapturedVersionHeader = versionHeader is string ? versionHeader : ();
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
function testClientSendsNegotiatedProtocolVersionHeader() returns error? {
    setMockNegotiatedVersion("2025-06-18");
    resetMockCapturedState();

    StreamableHttpClient 'client = check new (MOCK_SERVER_URL);
    check 'client->initialize();

    test:assertFalse(getMockInitHadVersionHeader(),
            "initialize request must not carry an MCP-Protocol-Version header");

    ListToolsResult _ = check 'client->listTools();
    test:assertEquals(getMockCapturedVersionHeader(), "2025-06-18",
            "subsequent requests must carry the negotiated MCP-Protocol-Version header");
}

// The client must accept a server that downgrades to an older supported version and send that version.
@test:Config {}
function testClientSendsDowngradedProtocolVersionHeader() returns error? {
    setMockNegotiatedVersion("2025-03-26");
    resetMockCapturedState();

    StreamableHttpClient 'client = check new (MOCK_SERVER_URL);
    check 'client->initialize();

    ListToolsResult _ = check 'client->listTools();
    test:assertEquals(getMockCapturedVersionHeader(), "2025-03-26",
            "client must send the downgraded negotiated version as the MCP-Protocol-Version header");
}

// The client must disconnect (error) if the server returns a version it does not support.
@test:Config {}
function testClientRejectsUnsupportedNegotiatedVersion() returns error? {
    setMockNegotiatedVersion("1999-01-01");

    StreamableHttpClient 'client = check new (MOCK_SERVER_URL);
    ClientError? result = 'client->initialize();
    test:assertTrue(result is ProtocolVersionError,
            "client must reject an unsupported negotiated protocol version");
}
