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

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/test;

listener StreamableHttpListener cachingListener = check new (3222);

@StreamableHttpConfig {
    info: {name: "hinted", version: "1"},
    cacheHints: {
        discover: {ttlMs: 300000, cacheScope: "public"},
        listTools: {ttlMs: 60000, cacheScope: "public"}
    }
}
service StreamableHttpService /hinted on cachingListener {
    @Tool {description: "echo", schema: {'type: "object"}}
    remote isolated function echo() returns string => "ok";
}

@StreamableHttpConfig {info: {name: "unhinted", version: "1"}}
service StreamableHttpService /unhinted on cachingListener {
    @Tool {description: "echo", schema: {'type: "object"}}
    remote isolated function echo() returns string => "ok";
}

@StreamableHttpConfig {
    info: {name: "handler-hinted", version: "1"},
    sessionMode: STATELESS,
    cacheHints: {listTools: {ttlMs: 60000, cacheScope: "public"}}
}
service StreamableHttpAdvancedService /handlerHinted on cachingListener {
    remote isolated function onListTools() returns ListToolsResult => {tools: [], ttlMs: 1000};

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

@StreamableHttpConfig {info: {name: "scope-only", version: "1"}, cacheHints: {listTools: {cacheScope: "public"}}}
service StreamableHttpAdvancedService /scopeOnly on cachingListener {
    remote isolated function onListTools() returns ListToolsResult => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
}

final http:Client cachingHttpClient = check new ("http://localhost:3222");

isolated function cachingPost(string servicePath, string methodName) returns map<json>|error {
    JsonRpcRequest requestMessage = {
        jsonrpc: JSONRPC_VERSION,
        id: 300,
        method: methodName,
        params: {_meta: {[PROTOCOL_META_KEY]: MODERN_PROTOCOL_VERSION, [CAPABILITIES_META_KEY]: {}}}
    };
    http:Response response = check cachingHttpClient->post(servicePath, requestMessage, headers = {
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: MODERN_PROTOCOL_VERSION,
        [METHOD_HEADER]: methodName
    });
    WireResponse payload = check (check response.getJsonPayload()).cloneWithType();
    return payload.result.toJson().ensureType();
}

@test:Config {}
function testServerSendsConfiguredCacheHints() returns error? {
    map<json> discovered = check cachingPost("/hinted", "server/discover");
    test:assertEquals(discovered["ttlMs"], 300000);
    test:assertEquals(discovered["cacheScope"], "public");

    map<json> listed = check cachingPost("/hinted", REQUEST_LIST_TOOLS);
    test:assertEquals(listed["ttlMs"], 60000);
    test:assertEquals(listed["cacheScope"], "public");

    map<json> defaults = check cachingPost("/unhinted", REQUEST_LIST_TOOLS);
    test:assertEquals(defaults["ttlMs"], 0);
    test:assertEquals(defaults["cacheScope"], "private");
}

@test:Config {}
function testHandlerHintsTakePrecedencePerField() returns error? {
    map<json> handlerTtl = check cachingPost("/handlerHinted", REQUEST_LIST_TOOLS);
    test:assertEquals(handlerTtl["ttlMs"], 1000);
    test:assertEquals(handlerTtl["cacheScope"], "public");

    map<json> scopeOnly = check cachingPost("/scopeOnly", REQUEST_LIST_TOOLS);
    test:assertEquals(scopeOnly["ttlMs"], 0);
    test:assertEquals(scopeOnly["cacheScope"], "public");
}

@test:Config {}
function testLegacyResultsCarryNoCacheHints() returns error? {
    http:Response response = check cachingHttpClient->post("/handlerHinted", legacyRequest(REQUEST_LIST_TOOLS),
            headers = legacyHeaders());
    JsonRpcResponse payload = check (check response.getJsonPayload()).cloneWithType();
    map<json> listed = check payload.result.toJson().ensureType();
    test:assertFalse(listed.hasKey("ttlMs"));
    test:assertFalse(listed.hasKey("cacheScope"));
    test:assertFalse(listed.hasKey("resultType"));
}

@test:Config {}
function testNegativeConfiguredTtlIsRejectedOnAttach() returns error? {
    StreamableHttpAdvancedService negativeService = @StreamableHttpConfig {
        info: {name: "negative", version: "1"},
        cacheHints: {discover: {ttlMs: -1}}
    } isolated service object {
        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};
    };
    StreamableHttpListener unstartedListener = check new (3224);
    Error? attachResult = unstartedListener.attach(negativeService, "/negative");
    if attachResult !is Error {
        test:assertFail("expected the negative ttlMs to be rejected");
    }
    test:assertEquals(attachResult.message(), "Cache hint ttlMs must be non-negative");
}

// A peer whose tools/list hints vary by scenario; it counts the tools/list requests that reach it.
const CACHE_MOCK_URL = "http://localhost:3223/cacheMock";

isolated map<int> cacheMockHits = {};

isolated function recordCacheMockHit(string hitKey) {
    lock {
        cacheMockHits[hitKey] = (cacheMockHits[hitKey] ?: 0) + 1;
    }
}

isolated function cacheMockHitCount(string scenario, string testId) returns int {
    lock {
        return cacheMockHits[scenario + "/" + testId] ?: 0;
    }
}

isolated function cacheMockListResult(RequestId requestId, int ttlMs, CacheScope cacheScope = "private",
        string? nextCursor = ()) returns http:Response {
    map<json> resultValue = {
        "resultType": "complete",
        "tools": [{"name": "echo", "inputSchema": {"type": "object"}}],
        "ttlMs": ttlMs,
        "cacheScope": cacheScope
    };
    if nextCursor is string {
        resultValue["nextCursor"] = nextCursor;
    }
    return mockJson({"jsonrpc": JSONRPC_VERSION, "id": requestId, "result": resultValue});
}

isolated function cacheMockError(RequestId requestId, int errorCode, int statusCode = 200) returns http:Response =>
    mockJson({"jsonrpc": JSONRPC_VERSION, "id": requestId, "error": {"code": errorCode, "message": "rejected"}}, statusCode);

service /cacheMock on new http:Listener(3223) {

    resource function post [string scenario]/[string testId](http:Request request) returns http:Response|error {
        JsonRpcRequest|error parsedRequest = (check request.getJsonPayload()).cloneWithType();
        if parsedRequest is error {
            http:Response acknowledgement = new;
            acknowledgement.statusCode = http:STATUS_ACCEPTED;
            return acknowledgement;
        }
        RequestId requestId = parsedRequest.id;
        string hitKey = scenario + "/" + testId;
        match parsedRequest.method {
            "server/discover" => {
                return mockDiscoverResult(requestId);
            }
            "subscriptions/listen" => {
                return mockSse([
                    mockAckEvent(requestId, {"toolsListChanged": true}),
                    mockNotificationEvent("notifications/tools/list_changed", requestId)
                ]);
            }
            REQUEST_CALL_TOOL => {
                recordCacheMockHit(hitKey + ":call");
                int callNumber = cacheMockHitCount(scenario, testId + ":call");
                // The first call reports stale tool metadata, as a server whose tools changed would.
                if callNumber == 1 {
                    return cacheMockError(requestId, HEADER_MISMATCH, 400);
                }
                return mockJson({"jsonrpc": JSONRPC_VERSION, "id": requestId, "result": {"resultType": "complete", "content": []}});
            }
        }
        recordCacheMockHit(hitKey);
        anydata cursor = (parsedRequest.params ?: {})["cursor"];
        match scenario {
            "private" => {
                return cacheMockListResult(requestId, 60000);
            }
            "public" => {
                return cacheMockListResult(requestId, 60000, "public");
            }
            "uncacheable" => {
                return cacheMockListResult(requestId, 0);
            }
            "negativeTtl" => {
                return cacheMockListResult(requestId, -5);
            }
            "shortTtl" => {
                return cacheMockListResult(requestId, 200);
            }
            "paged" => {
                if cursor is () {
                    return cacheMockListResult(requestId, 60000, nextCursor = "page2");
                }
                if cursor == "page2" {
                    return cacheMockListResult(requestId, 60000);
                }
                return cacheMockError(requestId, INVALID_PARAMS);
            }
        }
        return cacheMockError(requestId, METHOD_NOT_FOUND);
    }
}

isolated function connectedCacheClient(string scenario, string testId, ResultCacheConfig? resultCache = {})
        returns StreamableHttpClient|error {
    StreamableHttpClient cacheClient = check new (string `${CACHE_MOCK_URL}/${scenario}/${testId}`,
        protocolMode = "modern", resultCache = resultCache);
    _ = check cacheClient->connect();
    return cacheClient;
}

@test:Config {}
function testClientReusesFreshResults() returns error? {
    StreamableHttpClient freshClient = check connectedCacheClient("private", "fresh");
    ListToolsResult firstList = check freshClient->listTools();
    ListToolsResult secondList = check freshClient->listTools();
    test:assertEquals(cacheMockHitCount("private", "fresh"), 1);
    test:assertEquals(secondList, firstList);
    test:assertEquals(secondList.ttlMs, 60000);

    StreamableHttpClient zeroTtlClient = check connectedCacheClient("uncacheable", "fresh");
    _ = check zeroTtlClient->listTools();
    _ = check zeroTtlClient->listTools();
    test:assertEquals(cacheMockHitCount("uncacheable", "fresh"), 2);

    StreamableHttpClient disabledClient = check connectedCacheClient("private", "disabled", resultCache = ());
    _ = check disabledClient->listTools();
    _ = check disabledClient->listTools();
    test:assertEquals(cacheMockHitCount("private", "disabled"), 2);
}

@test:Config {}
function testClientCacheModes() returns error? {
    StreamableHttpClient modeClient = check connectedCacheClient("private", "modes");
    _ = check modeClient->listTools(cacheMode = "bypass");
    _ = check modeClient->listTools();
    test:assertEquals(cacheMockHitCount("private", "modes"), 2, "bypass must not store its result");
    _ = check modeClient->listTools(cacheMode = "refresh");
    test:assertEquals(cacheMockHitCount("private", "modes"), 3);
    _ = check modeClient->listTools();
    test:assertEquals(cacheMockHitCount("private", "modes"), 3);
}

@test:Config {}
function testClientTreatsNegativeTtlAsZero() returns error? {
    StreamableHttpClient negativeClient = check connectedCacheClient("negativeTtl", "floor");
    ListToolsResult listed = check negativeClient->listTools();
    test:assertEquals(listed.ttlMs, 0);
    _ = check negativeClient->listTools();
    test:assertEquals(cacheMockHitCount("negativeTtl", "floor"), 2);
}

@test:Config {}
function testClientRefetchesExpiredResults() returns error? {
    StreamableHttpClient expiringClient = check connectedCacheClient("shortTtl", "expiry");
    _ = check expiringClient->listTools();
    _ = check expiringClient->listTools();
    test:assertEquals(cacheMockHitCount("shortTtl", "expiry"), 1);
    runtime:sleep(0.3);
    _ = check expiringClient->listTools();
    test:assertEquals(cacheMockHitCount("shortTtl", "expiry"), 2);

    StreamableHttpClient cappedClient = check connectedCacheClient("private", "capped", resultCache = {maxTtlMs: 100});
    _ = check cappedClient->listTools();
    runtime:sleep(0.2);
    _ = check cappedClient->listTools();
    test:assertEquals(cacheMockHitCount("private", "capped"), 2);
}

@test:Config {}
function testCacheIsPerClientAndIgnoresHeaders() returns error? {
    StreamableHttpClient firstClient = check connectedCacheClient("private", "perClient");
    _ = check firstClient->listTools({"traceparent": "00-aaaa-01"});
    _ = check firstClient->listTools({"traceparent": "00-bbbb-01"});
    test:assertEquals(cacheMockHitCount("private", "perClient"), 1);

    StreamableHttpClient secondClient = check connectedCacheClient("private", "perClient");
    _ = check secondClient->listTools();
    test:assertEquals(cacheMockHitCount("private", "perClient"), 2, "clients must not share cached results");
}

@test:Config {}
function testPagesAreCachedPerCursor() returns error? {
    StreamableHttpClient pagedClient = check connectedCacheClient("paged", "pages");
    ListToolsResult firstPage = check pagedClient->listTools();
    test:assertEquals(firstPage.nextCursor, "page2");
    _ = check pagedClient->listTools(cursor = "page2");
    _ = check pagedClient->listTools();
    _ = check pagedClient->listTools(cursor = "page2");
    test:assertEquals(cacheMockHitCount("paged", "pages"), 2);

    ListToolsResult|ClientError rejectedCursor = pagedClient->listTools(cursor = "expired");
    test:assertTrue(rejectedCursor is ClientError);
    _ = check pagedClient->listTools();
    _ = check pagedClient->listTools(cursor = "page2");
    test:assertEquals(cacheMockHitCount("paged", "pages"), 5, "a rejected cursor must drop every cached page");
}

@test:Config {}
function testListChangedNotificationInvalidatesCachedList() returns error? {
    StreamableHttpClient notifiedClient = check connectedCacheClient("private", "notified");
    _ = check notifiedClient->listTools();
    stream<JsonRpcMessage, StreamError?> eventStream = check notifiedClient->listen();
    boolean sawListChanged = false;
    while !sawListChanged {
        record {|JsonRpcMessage value;|}? nextEvent = check eventStream.next();
        if nextEvent is () {
            break;
        }
        JsonRpcMessage eventMessage = nextEvent.value;
        sawListChanged = eventMessage is JsonRpcNotification && eventMessage.method == "notifications/tools/list_changed";
    }
    check eventStream.close();
    test:assertTrue(sawListChanged);
    _ = check notifiedClient->listTools();
    test:assertEquals(cacheMockHitCount("private", "notified"), 2);
}

@test:Config {}
function testHeaderMismatchRefetchesCachedTools() returns error? {
    StreamableHttpClient mismatchClient = check connectedCacheClient("private", "mismatch");
    _ = check mismatchClient->listTools();
    var callResult = check mismatchClient->callToolOnce({name: "echo"});
    test:assertTrue(callResult is CallToolResult);
    test:assertEquals(cacheMockHitCount("private", "mismatch"), 2);
    test:assertEquals(cacheMockHitCount("private", "mismatch:call"), 2);
}

@test:Config {}
function testCloseClearsCachedResults() returns error? {
    StreamableHttpClient closingClient = check connectedCacheClient("private", "close");
    _ = check closingClient->listTools();
    check closingClient->close();
    _ = check closingClient->connect();
    _ = check closingClient->listTools();
    test:assertEquals(cacheMockHitCount("private", "close"), 2);
}

isolated decimal fakeCacheNow = 0;

isolated function fakeCacheClock() returns decimal {
    lock {
        return fakeCacheNow;
    }
}

isolated function advanceFakeCacheClock(decimal seconds) {
    lock {
        fakeCacheNow += seconds;
    }
}

@test:Config {}
function testResultCacheFreshness() {
    ResultCache resultCache = new ({}, fakeCacheClock);
    resultCache.put(REQUEST_LIST_TOOLS, (), {"ttlMs": 1000, "cacheScope": "public"}, resultCache.generation());
    advanceFakeCacheClock(0.999);
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, ()) is Result);
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, "page2") is ());
    advanceFakeCacheClock(0.001);
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, ()) is ());

    int staleGeneration = resultCache.generation();
    resultCache.invalidate(REQUEST_LIST_TOOLS);
    resultCache.put(REQUEST_LIST_TOOLS, (), {"ttlMs": 1000}, staleGeneration);
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, ()) is (),
            "a result fetched across an invalidation must not be stored");

    ResultCache disabledCache = new ((), fakeCacheClock);
    disabledCache.put(REQUEST_LIST_TOOLS, (), {"ttlMs": 1000}, disabledCache.generation());
    test:assertTrue(disabledCache.get(REQUEST_LIST_TOOLS, ()) is ());
}

@test:Config {}
function testResultCacheEvictsLeastRecentlyUsed() {
    ResultCache resultCache = new ({maxEntries: 2}, fakeCacheClock);
    resultCache.put(REQUEST_LIST_TOOLS, "first", {"ttlMs": 60000}, resultCache.generation());
    resultCache.put(REQUEST_LIST_TOOLS, "second", {"ttlMs": 60000}, resultCache.generation());
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, "first") is Result);
    resultCache.put(REQUEST_LIST_TOOLS, "third", {"ttlMs": 60000}, resultCache.generation());
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, "first") is Result);
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, "second") is ());
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, "third") is Result);

    // An expired entry is pruned on the next store rather than taking a slot from a fresh one.
    resultCache.put(REQUEST_LIST_TOOLS, "shortLived", {"ttlMs": 10}, resultCache.generation());
    advanceFakeCacheClock(0.02);
    resultCache.put(REQUEST_LIST_TOOLS, "fourth", {"ttlMs": 60000}, resultCache.generation());
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, "third") is Result);
    test:assertTrue(resultCache.get(REQUEST_LIST_TOOLS, "fourth") is Result);
}

@test:Config {}
function testResultCacheToolSchemas() {
    ResultCache resultCache = new ({}, fakeCacheClock);
    ToolDefinition firstTool = {name: "first", inputSchema: {'type: "object"}};
    ToolDefinition secondTool = {name: "second", inputSchema: {'type: "object"}};

    resultCache.recordToolSchemas([firstTool], ());
    resultCache.recordToolSchemas([secondTool], "page2");
    test:assertEquals(resultCache.toolSchema("first"), firstTool);
    test:assertEquals(resultCache.toolSchema("second"), secondTool);

    resultCache.recordToolSchemas([secondTool], ());
    test:assertEquals(resultCache.toolSchema("first"), (), "a first page starts a new listing");

    resultCache.invalidateFor({jsonrpc: JSONRPC_VERSION, method: "notifications/tools/list_changed"});
    test:assertEquals(resultCache.toolSchema("second"), ());
}
