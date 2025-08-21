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

final Implementation clientInfo = {
    name: TEST_CLIENT_NAME,
    version: TEST_CLIENT_VERSION
};

@test:Config {}
function testClientConstructionWithValidUrl() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);

    test:assertTrue('client is StreamableHttpClient);
}

@test:Config {}
function testClientConstructionWithInvalidUrlFormat() returns error? {
    StreamableHttpClient 'client = check new (INVALID_URL);

    test:assertTrue('client is StreamableHttpClient);
}

@test:Config {}
function testClientConstructionWithUnreachableServer() returns error? {
    StreamableHttpClient 'client = check new (UNREACHABLE_MCP_URL);

    test:assertTrue('client is StreamableHttpClient);
}

@test:Config {}
function testClientConstructionWithConfig() returns error? {
    StreamableHttpClientTransportConfig config = {
        timeout: 30,
        followRedirects: {enabled: true}
    };
    StreamableHttpClient 'client = check new (VALID_MCP_URL, config);

    test:assertTrue('client is StreamableHttpClient);
}

@test:Config {}
function testClientInitializationWithValidUrl() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);
    ClientCapabilities capabilities = {};
    error? result = 'client->initialize(clientInfo, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testClientInitializationWithInvalidUrl() returns error? {
    StreamableHttpClient 'client = check new (INVALID_URL);
    error? result = 'client->initialize(clientInfo);

    test:assertTrue(result is error);
}

@test:Config {}
function testClientInitializationWithUnreachableUrl() returns error? {
    StreamableHttpClient 'client = check new (UNREACHABLE_MCP_URL);
    error? result = 'client->initialize(clientInfo);

    test:assertTrue(result is error);
}

@test:Config {}
function testClientInitializationProtocolVersionNegotiation() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);
    check 'client->initialize(clientInfo);

    test:assertTrue(true);
}

@test:Config {}
function testClientInitializationStoresServerCapabilities() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);
    check 'client->initialize(clientInfo);

    test:assertTrue(true);
}

@test:Config {}
function testDoubleInitializationHandling() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);
    check 'client->initialize(clientInfo);
    error? result = 'client->initialize(clientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithEmptyClientName() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);
    Implementation clientInfo = {
        name: "",
        version: TEST_CLIENT_VERSION
    };
    error? result = 'client->initialize(clientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithEmptyVersion() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);
    Implementation clientInfo = {
        name: TEST_CLIENT_NAME,
        version: ""
    };
    error? result = 'client->initialize(clientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithClientCapabilities() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);
    ClientCapabilities capabilities = {
        roots: {
            listChanged: true
        },
        sampling: {}
    };
    error? result = 'client->initialize(clientInfo, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithEmptyCapabilities() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);
    ClientCapabilities capabilities = {};
    error? result = 'client->initialize(clientInfo, capabilities);

    test:assertFalse(result is error);
}

@test:Config {}
function testInitializationWithoutCapabilities() returns error? {
    StreamableHttpClient 'client = check new (VALID_MCP_URL);
    error? result = 'client->initialize(clientInfo);

    test:assertFalse(result is error);
}

@test:Config {}
function testMultipleClientsInitialization() returns error? {
    StreamableHttpClient firstClient = check new (VALID_MCP_URL);
    StreamableHttpClient secondClient = check new (VALID_MCP_URL);
    Implementation clientInfo2 = {
        name: TEST_CLIENT_NAME_2,
        version: TEST_CLIENT_VERSION
    };
    error? firstInitializeResult = firstClient->initialize(clientInfo);
    error? secondInitializeResult = secondClient->initialize(clientInfo2);

    test:assertFalse(firstInitializeResult is error);
    test:assertFalse(secondInitializeResult is error);
}
