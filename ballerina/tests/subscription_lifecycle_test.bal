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
import ballerina/time;

const LIFECYCLE_URL = "http://localhost:3241";
const decimal TEST_KEEP_ALIVE_INTERVAL = 0.3;
const PROBE_HEADER = "X-Probe";

// Subscription sources the lifecycle services created, keyed by the probe header of their request.
isolated map<ControlledNotificationSource> probeSources = {};

isolated function probeSource(string probe) returns ControlledNotificationSource? {
    lock {
        return probeSources[probe];
    }
}

isolated function awaitProbeSource(string probe) returns ControlledNotificationSource|error {
    foreach int _ in 0 ..< 100 {
        ControlledNotificationSource? eventSource = probeSource(probe);
        if eventSource is ControlledNotificationSource {
            return eventSource;
        }
        runtime:sleep(0.1);
    }
    return error(string `No subscription opened for probe '${probe}'`);
}

// A notification source that stays idle until the test publishes; next() blocks meanwhile.
isolated class ControlledNotificationSource {
    private JsonRpcNotification[] pending = [];
    private boolean closed = false;
    private boolean ignoresClose;

    isolated function init(boolean ignoresClose = false) {
        self.ignoresClose = ignoresClose;
    }

    isolated function publish(string method) {
        lock {
            self.pending.push({jsonrpc: JSONRPC_VERSION, method});
        }
    }

    isolated function isClosed() returns boolean {
        lock {
            return self.closed;
        }
    }

    public isolated function next() returns record {|JsonRpcNotification value;|}|error? {
        while true {
            lock {
                if self.closed && !self.ignoresClose {
                    return;
                }
                if self.pending.length() > 0 {
                    return {value: self.pending.shift().clone()};
                }
            }
            runtime:sleep(0.05);
        }
    }

    public isolated function close() returns error? {
        lock {
            self.closed = true;
        }
    }
}

isolated function openProbeSubscription(string probe, boolean ignoresClose)
        returns stream<JsonRpcNotification, error?> {
    ControlledNotificationSource eventSource = new (ignoresClose);
    lock {
        probeSources[probe] = eventSource;
    }
    return new (eventSource);
}

@StreamableHttpServiceConfig {info: {name: "subscription-lifecycle", version: "1"}}
service StreamableHttpAdvancedService /lifecycle on new StreamableHttpListener(3241) {
    remote isolated function onListTools() returns ListToolsResult => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};

    remote isolated function onSubscribe(@http:Header {name: PROBE_HEADER} string probe,
            SubscriptionFilter notifications) returns stream<JsonRpcNotification, error?> =>
        openProbeSubscription(probe, false);
}

isolated function newLifecycleService(boolean ignoresClose) returns StreamableHttpAdvancedService =>
    @StreamableHttpServiceConfig {info: {name: "subscription-lifecycle", version: "1"}}
    isolated service object {
        private final boolean ignoresClose = ignoresClose;

        remote isolated function onListTools() returns ListToolsResult => {tools: []};

        remote isolated function onCallTool(CallToolParams callParams) returns CallToolResult => {content: []};

        remote isolated function onSubscribe(@http:Header {name: PROBE_HEADER} string probe,
                SubscriptionFilter notifications) returns stream<JsonRpcNotification, error?> =>
            openProbeSubscription(probe, self.ignoresClose);
    };

isolated function listenRequest(string probe) returns [JsonRpcRequest, map<string|string[]>] => [
    {
        jsonrpc: JSONRPC_VERSION,
        id: 1,
        method: "subscriptions/listen",
        params: {
            _meta: {[PROTOCOL_META_KEY]: LATEST_PROTOCOL_VERSION, [CAPABILITIES_META_KEY]: {}},
            "notifications": {toolsListChanged: true}
        }
    },
    {
        [CONTENT_TYPE_HEADER]: CONTENT_TYPE_JSON,
        [ACCEPT_HEADER]: string `${CONTENT_TYPE_JSON}, ${CONTENT_TYPE_SSE}`,
        [PROTOCOL_VERSION_HEADER]: LATEST_PROTOCOL_VERSION,
        [METHOD_HEADER]: "subscriptions/listen",
        [PROBE_HEADER]: probe
    }
];

isolated function rawListen(string baseUrl, string path, string probe) returns stream<http:SseEvent, error?>|error {
    http:Client rawClient = check new (baseUrl, timeout = 10);
    [JsonRpcRequest, map<string|string[]>] [requestMessage, requestHeaders] = listenRequest(probe);
    return rawClient->post(path, requestMessage, headers = requestHeaders);
}

function lowerKeepAliveInterval() {
    setKeepAliveIntervalForTesting(TEST_KEEP_ALIVE_INTERVAL);
}

function restoreKeepAliveInterval() {
    setKeepAliveIntervalForTesting(SUBSCRIPTION_KEEP_ALIVE_INTERVAL);
}

@test:Config {before: lowerKeepAliveInterval, after: restoreKeepAliveInterval}
function testIdleSubscriptionReceivesKeepAliveComments() returns error? {
    stream<http:SseEvent, error?> events = check rawListen(LIFECYCLE_URL, "/lifecycle", "keepAliveComments");
    record {|http:SseEvent value;|}? acknowledgement = check events.next();
    test:assertTrue(acknowledgement?.value?.data is string);
    time:Utc startedAt = time:utcNow();
    foreach int _ in 0 ..< 3 {
        record {|http:SseEvent value;|}? keepAlive = check events.next();
        if keepAlive is () {
            test:assertFail("the subscription ended instead of sending a keep-alive");
        }
        test:assertTrue(keepAlive.value.comment is string, keepAlive.value.toString());
        test:assertEquals(keepAlive.value.data, ());
    }
    decimal elapsed = time:utcDiffSeconds(time:utcNow(), startedAt);
    test:assertTrue(elapsed >= 0.6d && elapsed < 10d, elapsed.toString());
    check events.close();
}

isolated function nextMethod(stream<JsonRpcMessage, StreamError?> events) returns string|error {
    record {|JsonRpcMessage value;|}? event = check events.next();
    if event is () {
        return error("the subscription ended");
    }
    JsonRpcMessage message = event.value;
    if message is JsonRpcNotification {
        return message.method;
    }
    return error(string `expected a notification: ${message.toJsonString()}`);
}

@test:Config {before: lowerKeepAliveInterval, after: restoreKeepAliveInterval}
function testQuietSubscriptionOutlivesClientIdleTimeout() returns error? {
    StreamableHttpClient mcpClient = check new (LIFECYCLE_URL + "/lifecycle", httpConfig = {timeout: 1.5});
    _ = check mcpClient->connect();
    stream<JsonRpcMessage, StreamError?> events = check mcpClient->listen(headers = {[PROBE_HEADER]: "outlivesIdle"});
    test:assertEquals(check nextMethod(events), "notifications/subscriptions/acknowledged");
    ControlledNotificationSource eventSource = check awaitProbeSource("outlivesIdle");
    runtime:sleep(4);
    eventSource.publish("notifications/tools/list_changed");
    test:assertEquals(check nextMethod(events), "notifications/tools/list_changed");
    check events.close();
    check mcpClient->close();
}

isolated function awaitClosed(ControlledNotificationSource eventSource, decimal timeout) returns boolean {
    time:Utc deadline = time:utcAddSeconds(time:utcNow(), timeout);
    while time:utcDiffSeconds(deadline, time:utcNow()) > 0d {
        if eventSource.isClosed() {
            return true;
        }
        runtime:sleep(0.05);
    }
    return eventSource.isClosed();
}

function useOneSecondKeepAlive() {
    setKeepAliveIntervalForTesting(1);
}

@test:Config {before: useOneSecondKeepAlive, after: restoreKeepAliveInterval}
function testClientDisconnectClosesIdleSubscriptionSource() returns error? {
    // The client drops the connection on its own idle timeout, which is shorter than the keep-alive interval.
    http:Client rawClient = check new (LIFECYCLE_URL, timeout = 0.3);
    [JsonRpcRequest, map<string|string[]>] [requestMessage, requestHeaders] = listenRequest("disconnect");
    stream<http:SseEvent, error?> events = check rawClient->post("/lifecycle", requestMessage, headers = requestHeaders);
    record {|http:SseEvent value;|}? acknowledgement = check events.next();
    test:assertTrue(acknowledgement?.value?.data is string);
    ControlledNotificationSource eventSource = check awaitProbeSource("disconnect");
    record {|http:SseEvent value;|}|error? idleRead = events.next();
    test:assertTrue(idleRead is error, "expected the client to time out");
    test:assertFalse(eventSource.isClosed());
    // The source's next() is blocked the whole time; close() must still reach it.
    test:assertTrue(awaitClosed(eventSource, 5), "the subscription source was not closed after the disconnect");
}

// Data of the events a raw subscription receives until it ends or fails, skipping keep-alives.
isolated function remainingData(stream<http:SseEvent, error?> events) returns string[] {
    string[] received = [];
    while true {
        record {|http:SseEvent value;|}|error? event = events.next();
        if event !is record {|http:SseEvent value;|} {
            return received;
        }
        string? data = event.value.data;
        if data is string {
            received.push(data);
        }
    }
}

isolated function isCompleteResult(string data) returns boolean {
    json|error message = data.fromJsonString();
    return message is map<json> && message["result"] is map<json> && message.result.resultType == "complete";
}

@test:Config {before: lowerKeepAliveInterval, after: restoreKeepAliveInterval}
function testGracefulStopCompletesOpenSubscriptions() returns error? {
    StreamableHttpListener stoppingListener = check new (3242);
    check stoppingListener.attach(newLifecycleService(false), "/endsOnClose");
    check stoppingListener.attach(newLifecycleService(true), "/neverEnds");
    check stoppingListener.'start();
    string baseUrl = "http://localhost:3242";
    stream<http:SseEvent, error?> closingEvents = check rawListen(baseUrl, "/endsOnClose", "gracefulEndsOnClose");
    stream<http:SseEvent, error?> stuckEvents = check rawListen(baseUrl, "/neverEnds", "gracefulNeverEnds");
    _ = check closingEvents.next();
    _ = check stuckEvents.next();
    ControlledNotificationSource closingSource = check awaitProbeSource("gracefulEndsOnClose");
    ControlledNotificationSource stuckSource = check awaitProbeSource("gracefulNeverEnds");

    time:Utc stoppingAt = time:utcNow();
    check stoppingListener.gracefulStop();
    decimal stopDuration = time:utcDiffSeconds(time:utcNow(), stoppingAt);
    test:assertTrue(stopDuration < 7d, string `gracefulStop took ${stopDuration}s`);

    string[] closingData = remainingData(closingEvents);
    test:assertEquals(closingData.length(), 1, closingData.toString());
    test:assertTrue(isCompleteResult(closingData[0]), closingData[0]);
    string[] stuckData = remainingData(stuckEvents);
    test:assertEquals(stuckData.length(), 1, stuckData.toString());
    test:assertTrue(isCompleteResult(stuckData[0]), stuckData[0]);
    test:assertTrue(awaitClosed(closingSource, 5));
    test:assertTrue(awaitClosed(stuckSource, 5));
}

@test:Config {before: lowerKeepAliveInterval, after: restoreKeepAliveInterval}
function testImmediateStopSendsNoComplete() returns error? {
    StreamableHttpListener stoppingListener = check new (3243);
    check stoppingListener.attach(newLifecycleService(false), "/immediate");
    check stoppingListener.'start();
    stream<http:SseEvent, error?> events = check rawListen("http://localhost:3243", "/immediate", "immediateStop");
    _ = check events.next();
    ControlledNotificationSource eventSource = check awaitProbeSource("immediateStop");
    check stoppingListener.immediateStop();
    string[] received = remainingData(events);
    test:assertEquals(received, [], received.toString());
    test:assertTrue(awaitClosed(eventSource, 5));
}
