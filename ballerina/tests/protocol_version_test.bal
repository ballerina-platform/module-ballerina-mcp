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

// Version negotiation: the server must echo a requested version it supports.
@test:Config {}
function testSelectProtocolVersionEchoesSupportedVersions() {
    foreach string supportedVersion in SUPPORTED_PROTOCOL_VERSIONS {
        test:assertEquals(selectProtocolVersion(supportedVersion), supportedVersion,
                string `Server should echo the supported requested version '${supportedVersion}'`);
    }
}

// Version negotiation: for an unsupported request, the server must fall back to its latest version.
@test:Config {}
function testSelectProtocolVersionFallsBackToLatest() {
    test:assertEquals(selectProtocolVersion("1.0.0"), LATEST_PROTOCOL_VERSION);
    test:assertEquals(selectProtocolVersion("2099-01-01"), LATEST_PROTOCOL_VERSION);
    test:assertEquals(selectProtocolVersion(""), LATEST_PROTOCOL_VERSION);
}

// Transport: an absent MCP-Protocol-Version header is tolerated (server assumes 2025-03-26).
@test:Config {}
function testValidateProtocolVersionHeaderAbsentIsAllowed() {
    http:BadRequest? result = validateProtocolVersionHeader(());
    test:assertTrue(result is (), "Absent MCP-Protocol-Version header must be tolerated");
}

// Transport: a present, supported MCP-Protocol-Version header is accepted.
@test:Config {}
function testValidateProtocolVersionHeaderSupportedIsAllowed() {
    foreach string supportedVersion in SUPPORTED_PROTOCOL_VERSIONS {
        http:BadRequest? result = validateProtocolVersionHeader(supportedVersion);
        test:assertTrue(result is (),
                string `Supported MCP-Protocol-Version header '${supportedVersion}' must be accepted`);
    }
}

// Transport: a present, unsupported MCP-Protocol-Version header must be rejected with 400.
@test:Config {}
function testValidateProtocolVersionHeaderUnsupportedIsRejected() {
    http:BadRequest? result = validateProtocolVersionHeader("1999-01-01");
    test:assertTrue(result is http:BadRequest,
            "Unsupported MCP-Protocol-Version header must be rejected with 400 Bad Request");
}
