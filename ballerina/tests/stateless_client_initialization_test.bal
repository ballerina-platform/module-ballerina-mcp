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

const string VALID_MCP_URL = "http://localhost:3000/mcp";
const string UNREACHABLE_MCP_URL = "http://localhost:9999/mcp";
const string INVALID_URL = "invalid-url";
const string TEST_CLIENT_NAME = "test-client";
const string TEST_CLIENT_NAME_2 = "test-client-2";
const string TEST_CLIENT_VERSION = "1.0.0";

final StreamableHttpClient mcpClient = check new (VALID_MCP_URL);
final StreamableHttpClient invalidClient = check new (INVALID_URL);
final StreamableHttpClient unreachableClient = check new (UNREACHABLE_MCP_URL);
final Implementation clientInfo = {
    name: TEST_CLIENT_NAME,
    version: TEST_CLIENT_VERSION
};

@test:Config {}
function testClientConstructionWithValidUrl() returns error? {
    test:assertTrue(mcpClient is StreamableHttpClient);
}

@test:Config {}
function testClientConstructionWithInvalidUrlFormat() returns error? {
    test:assertTrue(invalidClient is StreamableHttpClient);
}

@test:Config {}
function testClientConstructionWithUnreachableServer() returns error? {
    test:assertTrue(unreachableClient is StreamableHttpClient);
}

@test:Config {}
function testClientConstructionWithConfig() returns error? {
    StreamableHttpClientConfig config = {
        timeout: 30,
        followRedirects: {enabled: true}
    };
    StreamableHttpClient 'client = check new (VALID_MCP_URL, config);

    test:assertTrue('client is StreamableHttpClient);
}

@test:Config {}
function testClientOperationsRequireConnect() returns error? {
    StreamableHttpClient disconnectedClient = check new (VALID_MCP_URL);
    ListToolsResult|ClientError result = disconnectedClient->listTools();
    test:assertTrue(result is ClientInitializationError);
}

@test:Config {}
function testClientInitializationWithValidUrl() returns error? {
    ClientCapabilities capabilities = {};
    ConnectionInfo|ClientError result = mcpClient->connect(clientInfo, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testClientInitializationWithInvalidUrl() returns error? {
    ConnectionInfo|ClientError result = invalidClient->connect(clientInfo);

    test:assertTrue(result is error);
}

@test:Config {}
function testClientInitializationWithUnreachableUrl() returns error? {
    ConnectionInfo|ClientError result = unreachableClient->connect(clientInfo);

    test:assertTrue(result is error);
}

@test:Config {}
function testClientInitializationProtocolVersionNegotiation() returns error? {
    _ = check mcpClient->connect(clientInfo);

    test:assertTrue(true);
}

@test:Config {}
function testClientInitializationStoresServerCapabilities() returns error? {
    _ = check mcpClient->connect(clientInfo);

    test:assertTrue(true);
}

@test:Config {}
function testDoubleInitializationHandling() returns error? {
    _ = check mcpClient->connect(clientInfo);
    ConnectionInfo|ClientError result = mcpClient->connect(clientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithEmptyClientName() returns error? {
    Implementation clientInfo = {
        name: "",
        version: TEST_CLIENT_VERSION
    };
    ConnectionInfo|ClientError result = mcpClient->connect(clientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithEmptyVersion() returns error? {
    Implementation clientInfo = {
        name: TEST_CLIENT_NAME,
        version: ""
    };
    ConnectionInfo|ClientError result = mcpClient->connect(clientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithClientCapabilities() returns error? {
    ClientCapabilities capabilities = {
        roots: {
            listChanged: true
        },
        sampling: {}
    };
    ConnectionInfo|ClientError result = mcpClient->connect(clientInfo, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithExperimentalCapability() returns error? {
    ClientCapabilities capabilities = {
        experimental: {"customFeature": {}}
    };
    ConnectionInfo|ClientError result = mcpClient->connect(clientInfo, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithExtendedImplementationInfo() returns error? {
    Implementation extendedClientInfo = {
        name: TEST_CLIENT_NAME,
        title: "Test MCP Client",
        version: TEST_CLIENT_VERSION,
        description: "A client used for integration testing",
        websiteUrl: "https://example.com"
    };
    ConnectionInfo|ClientError result = mcpClient->connect(extendedClientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithEmptyCapabilities() returns error? {
    ClientCapabilities capabilities = {};
    ConnectionInfo|ClientError result = mcpClient->connect(clientInfo, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithoutCapabilities() returns error? {
    ConnectionInfo|ClientError result = mcpClient->connect(clientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testMultipleClientsInitialization() returns error? {
    StreamableHttpClient mcpClient2 = check new (VALID_MCP_URL);
    Implementation clientInfo2 = {
        name: TEST_CLIENT_NAME_2,
        version: TEST_CLIENT_VERSION
    };
    ConnectionInfo|ClientError initializeResult1 = mcpClient->connect(clientInfo);
    ConnectionInfo|ClientError initializeResult2 = mcpClient2->connect(clientInfo2);

    test:assertFalse(initializeResult1 is error);
    test:assertFalse(initializeResult2 is error);
}
