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

import ballerina/mcp.v2 as mcpv2;
import ballerina/test;

listener mcpv2:StreamableHttpListener upgradeListener = check new (8788);

@mcpv2:StreamableHttpServiceConfig {
    info: {name: "protocol-upgrade", version: "2.0.0"},
    protocolMode: "auto"
}
service mcpv2:StreamableHttpService /upgrade on upgradeListener {
    remote isolated function versionedEcho(string inputValue, mcpv2:RequestMeta? requestMeta) returns string {
        return inputValue + (requestMeta is () ? ":no-meta" : ":meta");
    }
}

@test:Config {}
function testBuiltPackageSupportsBothProtocolEras() returns error? {
    test:assertEquals(mcpv2:LATEST_PROTOCOL_VERSION, "2026-07-28",
            msg = "Integration tests must resolve the package being built, not a cached earlier release");
    mcpv2:StreamableHttpClient modernClient = check new ("http://localhost:8788/upgrade", protocolMode = "auto");
    _ = check modernClient->connect();
    mcpv2:DiscoverResult discoveryResult = check modernClient->discover();
    test:assertTrue(discoveryResult.supportedVersions.some(versionValue => versionValue == "2026-07-28"));
    mcpv2:CallToolResult modernResult = check modernClient->callTool({name: "versionedEcho", arguments: {"inputValue": "hello"}});
    mcpv2:TextContent modernText = check modernResult.content[0].ensureType();
    test:assertEquals(modernText.text, "hello:no-meta");
    test:assertEquals(modernResult._meta?.serverInfo?.name, "protocol-upgrade");
    check modernClient->close();

    mcpv2:StreamableHttpClient legacyClient = check new ("http://localhost:8788/upgrade", protocolMode = "legacy");
    _ = check legacyClient->connect();
    mcpv2:CallToolResult legacyResult = check legacyClient->callTool({name: "versionedEcho", arguments: {"inputValue": "hello"}});
    mcpv2:TextContent legacyText = check legacyResult.content[0].ensureType();
    test:assertEquals(legacyText.text, "hello:no-meta");
    check legacyClient->close();
}
