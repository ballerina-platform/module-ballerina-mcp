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

@test:Config {}
function testProtocolVersionListsSplitByLifecycle2() {
    test:assertEquals(MODERN_PROTOCOL_VERSIONS, ["2026-07-28"]);
    test:assertEquals(LEGACY_PROTOCOL_VERSIONS, ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"]);
}

// A legacy request cannot name a modern revision in its MCP-Protocol-Version header.
@test:Config {}
function testValidateProtocolVersionHeaderRejectsModernVersion2() {
    test:assertTrue(validateProtocolVersionHeader("2026-07-28") is http:BadRequest);
}

// Version negotiation: the server must echo a requested version it supports.
@test:Config {}
function testSelectProtocolVersionEchoesSupportedVersions2() {
    foreach string supportedVersion in [...MODERN_PROTOCOL_VERSIONS, ...LEGACY_PROTOCOL_VERSIONS] {
        test:assertEquals(selectProtocolVersion(supportedVersion),
                supportedVersion == LATEST_MODERN_PROTOCOL_VERSION ? LATEST_LEGACY_PROTOCOL_VERSION : supportedVersion,
                string `Server should echo the supported requested version '${supportedVersion}'`);
    }
}

// Version negotiation: for an unsupported request, the server must fall back to its latest version.
@test:Config {}
function testSelectProtocolVersionFallsBackToLatest2() {
    test:assertEquals(selectProtocolVersion("1.0.0"), LATEST_LEGACY_PROTOCOL_VERSION);
    test:assertEquals(selectProtocolVersion("2099-01-01"), LATEST_LEGACY_PROTOCOL_VERSION);
    test:assertEquals(selectProtocolVersion(""), LATEST_LEGACY_PROTOCOL_VERSION);
}

// Transport: an absent MCP-Protocol-Version header is tolerated (server assumes 2025-03-26).
@test:Config {}
function testValidateProtocolVersionHeaderAbsentIsAllowed2() {
    http:BadRequest? result = validateProtocolVersionHeader(());
    test:assertTrue(result is (), "Absent MCP-Protocol-Version header must be tolerated");
}

// Transport: a present, legacy MCP-Protocol-Version header is accepted.
@test:Config {}
function testValidateProtocolVersionHeaderSupportedIsAllowed2() {
    foreach string supportedVersion in LEGACY_PROTOCOL_VERSIONS {
        http:BadRequest? result = validateProtocolVersionHeader(supportedVersion);
        test:assertTrue(result is (),
                string `Supported MCP-Protocol-Version header '${supportedVersion}' must be accepted`);
    }
}

// Transport: a present, unsupported MCP-Protocol-Version header must be rejected with 400.
@test:Config {}
function testValidateProtocolVersionHeaderUnsupportedIsRejected2() {
    http:BadRequest? result = validateProtocolVersionHeader("1999-01-01");
    test:assertTrue(result is http:BadRequest,
            "Unsupported MCP-Protocol-Version header must be rejected with 400 Bad Request");
}
