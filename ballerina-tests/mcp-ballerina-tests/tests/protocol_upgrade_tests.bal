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

listener mcp:StreamableHttpListener upgradeListener = check new (8788);

@mcp:StreamableHttpServiceConfig {
    info: {name: "protocol-upgrade", version: "1.4.0"},
    protocolMode: "auto"
}
service mcp:StreamableHttpService /upgrade on upgradeListener {
    remote isolated function versionedEcho(string inputValue, mcp:Meta? requestMeta) returns string {
        return inputValue + (requestMeta is () ? ":no-meta" : ":meta");
    }
}

@test:Config {}
function testBuiltPackageSupportsBothProtocolEras() returns error? {
    test:assertEquals(mcp:LATEST_PROTOCOL_VERSION, "2026-07-28",
            msg = "Integration tests must resolve the package being built, not a cached earlier release");
    mcp:StreamableHttpClient modernClient = check new ("http://localhost:8788/upgrade", protocolMode = "auto");
    check modernClient->initialize();
    mcp:DiscoverResult discoveryResult = check modernClient->discover();
    test:assertTrue(discoveryResult.supportedVersions.some(versionValue => versionValue == "2026-07-28"));
    mcp:CallToolResult modernResult = check modernClient->callTool({name: "versionedEcho", arguments: {"inputValue": "hello"}});
    mcp:TextContent modernText = check modernResult.content[0].ensureType();
    test:assertEquals(modernText.text, "hello:no-meta");
    test:assertEquals(modernResult._meta, ());
    check modernClient->close();

    mcp:StreamableHttpClient legacyClient = check new ("http://localhost:8788/upgrade", protocolMode = "legacy");
    check legacyClient->initialize();
    mcp:CallToolResult legacyResult = check legacyClient->callTool({name: "versionedEcho", arguments: {"inputValue": "hello"}});
    mcp:TextContent legacyText = check legacyResult.content[0].ensureType();
    test:assertEquals(legacyText.text, "hello:no-meta");
    check legacyClient->close();
}
