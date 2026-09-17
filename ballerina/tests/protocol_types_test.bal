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
function testResourceTypes() {
    ResourceContents contents = {uri: "file:///doc.txt", mimeType: "text/plain"};
    test:assertEquals(contents.uri, "file:///doc.txt");

    TextResourceContents textContents = {uri: "file:///doc.txt", mimeType: "text/plain", text: "hello"};
    test:assertEquals(textContents.text, "hello");

    BlobResourceContents blobContents = {uri: "file:///img.png", mimeType: "image/png", blob: "aGVsbG8="};
    test:assertEquals(blobContents.blob, "aGVsbG8=");

    Resource resourceInfo = {
        name: "doc",
        title: "Document",
        uri: "file:///doc.txt",
        description: "A document",
        mimeType: "text/plain",
        size: 42,
        icons: [{src: "data:image/png;base64,icon", mimeType: "image/png"}],
        annotations: {audience: ["user", "assistant"], priority: 0.5, lastModified: "2026-01-01T00:00:00Z"}
    };
    test:assertEquals(resourceInfo.size, 42);
    test:assertEquals(resourceInfo.annotations?.audience, <Role[]>["user", "assistant"]);
    test:assertEquals(resourceInfo.annotations?.priority, 0.5d);
}

@test:Config {}
function testBaseMetadataAndIcons() {
    BaseMetadata metadata = {name: "thing", title: "Thing"};
    test:assertEquals(metadata.title, "Thing");

    Icons iconSet = {
        icons: [
            {src: "https://example.com/dark.png", theme: "dark", sizes: ["32x32"]},
            {src: "https://example.com/light.svg", theme: "light", sizes: ["any"]}
        ]
    };
    Icon[] icons = iconSet.icons ?: [];
    test:assertEquals(icons.length(), 2);
    test:assertEquals(icons[0].theme, "dark");
}

@test:Config {}
function testRequestAndNotificationShapes() {
    Notification notification = {
        method: "notifications/resources/updated",
        params: {_meta: {subscriptionId: "sub-1"}}
    };
    test:assertEquals(notification.params?._meta?.subscriptionId, "sub-1");

    PaginatedRequest paginatedRequest = {params: {"cursor": "page-2"}};
    test:assertEquals(paginatedRequest.params["cursor"], "page-2");

    ListToolsRequest listRequest = {params: {"cursor": "page-3"}};
    test:assertEquals(listRequest.method, REQUEST_LIST_TOOLS);

    PaginatedResult paginatedResult = {nextCursor: "page-4"};
    test:assertEquals(paginatedResult.nextCursor, "page-4");

    CallToolParams continuation = {
        name: "ask",
        arguments: {"value": 1},
        requestState: "opaque",
        inputResponses: {"answer": {"action": "accept"}}
    };
    test:assertEquals((continuation.inputResponses ?: {}).length(), 1);
}

@test:Config {}
function testToolAnnotationsAndConfiguration() {
    ToolAnnotations annotations = {
        title: "Delete everything",
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false
    };
    test:assertEquals(annotations.title, "Delete everything");
    test:assertTrue(annotations.destructiveHint ?: false);

    ArgumentConfig argumentConfig = {headerName: "Region"};
    test:assertEquals(argumentConfig.headerName, "Region");

    ServerOptions serverOptions = {
        capabilities: {logging: {}, completions: {}, experimental: {"vendor": "x"}, extensions: {"ext": {}}},
        instructions: "Use the echo tool first.",
        enforceStrictCapabilities: true
    };
    test:assertEquals(serverOptions.instructions, "Use the echo tool first.");
    test:assertTrue(serverOptions.capabilities?.logging is map<anydata>);
    test:assertTrue(serverOptions.capabilities?.completions is map<anydata>);

    JsonSchema schema = {"type": "object", "additionalProperties": false};
    test:assertEquals(schema["type"], "object");
}

@test:Config {}
function testClientCapabilityExtensions() {
    ClientCapabilities capabilities = {
        extensions: {"vendor/ext": {}},
        experimental: {"beta": true},
        roots: {listChanged: true}
    };
    test:assertEquals((capabilities.extensions ?: {}).length(), 1);
    test:assertEquals(capabilities.roots?.listChanged, true);
}

@test:Config {}
function testLegacyFallbackHonoursAdvertisedVersions() {
    // A peer that still advertises the modern revision is not worth downgrading for.
    test:assertFalse(shouldUseLegacy(unsupportedVersionError([MODERN_PROTOCOL_VERSION, "2025-06-18"])));

    // A peer that advertises only legacy revisions we support is.
    test:assertTrue(shouldUseLegacy(unsupportedVersionError([LATEST_LEGACY_PROTOCOL_VERSION])));
    test:assertTrue(shouldUseLegacy(unsupportedVersionError(["2024-10-07"])));

    // Nothing in common leaves no protocol to fall back to.
    test:assertFalse(shouldUseLegacy(unsupportedVersionError(["1999-01-01"])));

    // Malformed negotiation data is not a downgrade signal either.
    test:assertFalse(shouldUseLegacy(error ServerResponseError("bad data", rpcError = {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        'error: {code: UNSUPPORTED_PROTOCOL_VERSION, message: "no", data: {"supported": "not-an-array"}}
    })));
    test:assertFalse(shouldUseLegacy(error ServerResponseError("no data", rpcError = {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        'error: {code: UNSUPPORTED_PROTOCOL_VERSION, message: "no"}
    })));

    // Any other JSON-RPC error means the peer spoke a protocol we can retry in legacy mode.
    test:assertTrue(shouldUseLegacy(error ServerResponseError("method missing", rpcError = {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        'error: {code: METHOD_NOT_FOUND, message: "Method not found"}
    })));

    foreach int statusCode in [404, 405] {
        test:assertTrue(shouldUseLegacy(error HttpClientError("legacy peer", statusCode = statusCode)));
    }
    test:assertTrue(shouldUseLegacy(error ResponseParsingError("not a modern response")));
}

isolated function unsupportedVersionError(string[] supportedVersions) returns ClientError =>
    error ServerResponseError("Unsupported protocol version", rpcError = {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        'error: {
            code: UNSUPPORTED_PROTOCOL_VERSION,
            message: "Unsupported protocol version",
            data: {"supported": supportedVersions, "requested": MODERN_PROTOCOL_VERSION}
        }
    });
