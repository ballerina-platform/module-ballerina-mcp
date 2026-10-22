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

@test:Config {}
function testConcurrentFirstConnectsShareOneDiscovery() returns error? {
    StreamableHttpClient2 racingClient = check new (mockUrl("slowModernConnect"));
    future<ConnectionInfo|ClientError> first = start racingClient->connect();
    future<ConnectionInfo|ClientError> second = start racingClient->connect();
    ConnectionInfo firstConnection = check wait first;
    ConnectionInfo secondConnection = check wait second;

    test:assertEquals(mockCallCount("slowModernConnect:discover"), 1);
    test:assertEquals(firstConnection, secondConnection);
    test:assertEquals(firstConnection.protocolVersion, LATEST_MODERN_PROTOCOL_VERSION);
}

@test:Config {}
function testConcurrentFirstLegacyConnectsShareOneInitialize() returns error? {
    StreamableHttpClient2 racingClient = check new (mockUrl("slowLegacyConnect"), protocolMode = "legacy");
    future<ConnectionInfo|ClientError> first = start racingClient->connect();
    future<ConnectionInfo|ClientError> second = start racingClient->connect();
    ConnectionInfo firstConnection = check wait first;
    ConnectionInfo secondConnection = check wait second;

    test:assertEquals(mockCallCount("slowLegacyConnect:initialize"), 1);
    test:assertEquals(firstConnection, secondConnection);
    test:assertEquals(firstConnection.protocolVersion, LATEST_LEGACY_PROTOCOL_VERSION);
}

@test:Config {}
function testConnectAfterCloseRunsANewHandshake() returns error? {
    StreamableHttpClient2 reconnectingClient = check new (mockUrl("reconnectAfterClose"));
    _ = check reconnectingClient->connect();
    _ = check reconnectingClient->connect();
    test:assertEquals(mockCallCount("reconnectAfterClose:discover"), 1);

    check reconnectingClient->close();
    ConnectionInfo reconnected = check reconnectingClient->connect();
    test:assertEquals(mockCallCount("reconnectAfterClose:discover"), 2);
    test:assertEquals(reconnected.protocolVersion, LATEST_MODERN_PROTOCOL_VERSION);
    _ = check reconnectingClient->listTools();
}
