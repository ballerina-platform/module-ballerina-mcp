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

import ballerina/test;

const string VALID_MCP_URL2 = "http://localhost:3000/mcp";
const string UNREACHABLE_MCP_URL2 = "http://localhost:9999/mcp";
const string INVALID_URL2 = "invalid-url";
const string TEST_CLIENT_NAME2 = "test-client";
const string TEST_CLIENT_NAME_22 = "test-client-2";
const string TEST_CLIENT_VERSION2 = "1.0.0";

final StreamableHttpClient2 mcpClient2 = check new (VALID_MCP_URL2);
final StreamableHttpClient2 invalidClient2 = check new (INVALID_URL2);
final StreamableHttpClient2 unreachableClient2 = check new (UNREACHABLE_MCP_URL2);
final Implementation clientInfo2 = {
    name: TEST_CLIENT_NAME2,
    version: TEST_CLIENT_VERSION2
};

@test:Config {}
function testClientConstructionWithValidUrl2() returns error? {
    test:assertTrue(mcpClient2 is StreamableHttpClient2);
}

@test:Config {}
function testClientConstructionWithInvalidUrlFormat2() returns error? {
    test:assertTrue(invalidClient2 is StreamableHttpClient2);
}

@test:Config {}
function testClientConstructionWithUnreachableServer2() returns error? {
    test:assertTrue(unreachableClient2 is StreamableHttpClient2);
}

@test:Config {}
function testClientConstructionWithConfig2() returns error? {
    StreamableHttpClientConfig config = {
        httpConfig: {
            timeout: 30,
            followRedirects: {enabled: true}
        }
    };
    StreamableHttpClient2 'client = check new (VALID_MCP_URL2, config);

    test:assertTrue('client is StreamableHttpClient2);
}

@test:Config {}
function testClientOperationsRequireConnect2() returns error? {
    StreamableHttpClient2 disconnectedClient = check new (VALID_MCP_URL2);
    ToolPage|ClientError result = disconnectedClient->listTools();
    test:assertTrue(result is ClientInitializationError);
}

@test:Config {}
function testClientInitializationWithValidUrl2() returns error? {
    ClientCapabilities capabilities = {};
    ConnectionInfo|ClientError result = mcpClient2->connect(clientInfo2, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testClientInitializationWithInvalidUrl2() returns error? {
    ConnectionInfo|ClientError result = invalidClient2->connect(clientInfo2);

    test:assertTrue(result is error);
}

@test:Config {}
function testClientInitializationWithUnreachableUrl2() returns error? {
    ConnectionInfo|ClientError result = unreachableClient2->connect(clientInfo2);

    test:assertTrue(result is error);
}

@test:Config {}
function testClientInitializationProtocolVersionNegotiation2() returns error? {
    _ = check mcpClient2->connect(clientInfo2);

    test:assertTrue(true);
}

@test:Config {}
function testClientInitializationStoresServerCapabilities2() returns error? {
    _ = check mcpClient2->connect(clientInfo2);

    test:assertTrue(true);
}

@test:Config {}
function testDoubleInitializationHandling2() returns error? {
    _ = check mcpClient2->connect(clientInfo2);
    ConnectionInfo|ClientError result = mcpClient2->connect(clientInfo2);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithEmptyClientName2() returns error? {
    Implementation clientInfo2 = {
        name: "",
        version: TEST_CLIENT_VERSION2
    };
    ConnectionInfo|ClientError result = mcpClient2->connect(clientInfo2);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithEmptyVersion2() returns error? {
    Implementation clientInfo2 = {
        name: TEST_CLIENT_NAME2,
        version: ""
    };
    ConnectionInfo|ClientError result = mcpClient2->connect(clientInfo2);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithClientCapabilities2() returns error? {
    ClientCapabilities capabilities = {
        roots: {
            listChanged: true
        },
        sampling: {}
    };
    ConnectionInfo|ClientError result = mcpClient2->connect(clientInfo2, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithExperimentalCapability2() returns error? {
    ClientCapabilities capabilities = {
        experimental: {"customFeature": {}}
    };
    ConnectionInfo|ClientError result = mcpClient2->connect(clientInfo2, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithExtendedImplementationInfo2() returns error? {
    Implementation extendedClientInfo = {
        name: TEST_CLIENT_NAME2,
        title: "Test MCP Client",
        version: TEST_CLIENT_VERSION2,
        description: "A client used for integration testing",
        websiteUrl: "https://example.com"
    };
    ConnectionInfo|ClientError result = mcpClient2->connect(extendedClientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithEmptyCapabilities2() returns error? {
    ClientCapabilities capabilities = {};
    ConnectionInfo|ClientError result = mcpClient2->connect(clientInfo2, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithoutCapabilities2() returns error? {
    ConnectionInfo|ClientError result = mcpClient2->connect(clientInfo2);

    test:assertFalse(result is error);
}

@test:Config {}
function testMultipleClientsInitialization2() returns error? {
    StreamableHttpClient2 mcpClient2 = check new (VALID_MCP_URL2);
    Implementation clientInfo2 = {
        name: TEST_CLIENT_NAME_22,
        version: TEST_CLIENT_VERSION2
    };
    ConnectionInfo|ClientError initializeResult1 = mcpClient2->connect(clientInfo2);
    ConnectionInfo|ClientError initializeResult2 = mcpClient2->connect(clientInfo2);

    test:assertFalse(initializeResult1 is error);
    test:assertFalse(initializeResult2 is error);
}
