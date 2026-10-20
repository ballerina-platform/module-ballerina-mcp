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
import ballerina/jballerina.java;
import ballerina/lang.runtime;
import ballerina/time;

// Seconds between SSE comment keep-alives on an idle subscription.
const decimal SUBSCRIPTION_KEEP_ALIVE_INTERVAL = 15;

isolated decimal keepAliveInterval = SUBSCRIPTION_KEEP_ALIVE_INTERVAL;

isolated function currentKeepAliveInterval() returns decimal {
    lock {
        return keepAliveInterval;
    }
}

// Returned by a wait for the user stream that timed out or was woken.
const SOURCE_IDLE = "idle";

// Test-only: lets tests shorten the keep-alive interval for subscriptions opened afterwards.
isolated function setKeepAliveIntervalForTesting(decimal interval) {
    lock {
        keepAliveInterval = interval;
    }
}

isolated function invokeOnSubscribe(StreamableHttpAdvancedService mcpService, SubscriptionFilter notifications,
        http:Headers headers, http:Request request, map<string[]> headerValues, boolean treatNilableAsOptional,
        AuthContext? authContext) returns stream<JsonRpcNotification, error?>|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function hasSubscriptionHandler(StreamableHttpAdvancedService mcpService) returns boolean = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

// Seconds `gracefulStop` waits for open subscriptions to send their `complete` result.
const decimal SUBSCRIPTION_SHUTDOWN_TIMEOUT = 5;

// The open subscriptions of one listener, so that shutdown can end them.
isolated class SubscriptionRegistry {
    private final map<ServerSubscriptionStream> openSubscriptions = {};
    private int lastKey = 0;
    private boolean stopping = false;

    isolated function newKey() returns string {
        lock {
            self.lastKey += 1;
            return self.lastKey.toString();
        }
    }

    // Returns whether the listener is already stopping, in which case the subscription must complete at once.
    isolated function add(string key, ServerSubscriptionStream subscription) returns boolean {
        lock {
            self.openSubscriptions[key] = subscription;
            return self.stopping;
        }
    }

    isolated function remove(string key) {
        lock {
            _ = self.openSubscriptions.removeIfHasKey(key);
        }
    }

    // Asks every open subscription to send `complete`, and waits until they have or the timeout passes.
    isolated function stopAll(decimal timeout) {
        foreach string key in self.beginStopping() {
            ServerSubscriptionStream? subscription = self.get(key);
            if subscription is ServerSubscriptionStream {
                subscription.stop();
            }
        }
        decimal waited = 0;
        while waited < timeout {
            lock {
                if self.openSubscriptions.length() == 0 {
                    return;
                }
            }
            runtime:sleep(0.05);
            waited += 0.05d;
        }
    }

    // Closes every open subscription's source without sending `complete`.
    isolated function abortAll() {
        foreach string key in self.beginStopping() {
            ServerSubscriptionStream? subscription = self.get(key);
            if subscription is ServerSubscriptionStream {
                subscription.abort();
            }
        }
    }

    private isolated function beginStopping() returns string[] & readonly {
        lock {
            self.stopping = true;
            return self.openSubscriptions.keys().cloneReadOnly();
        }
    }

    private isolated function get(string key) returns ServerSubscriptionStream? {
        lock {
            return self.openSubscriptions[key];
        }
    }
}

// Wraps the stream `onSubscribe` returned. A wait for its next item times out after the keep-alive
// interval, so an idle subscription still writes, and http only notices a disconnect on a failed write.
isolated class ServerSubscriptionStream {
    private final RequestId subscriptionId;
    private final SubscriptionFilter & readonly acceptedFilter;
    private final decimal keepAliveInterval;
    private final SubscriptionRegistry registry;
    private final string registryKey;
    private boolean acknowledged = false;
    private boolean finished = false;
    private boolean stopping = false;

    isolated function init(stream<JsonRpcNotification, error?> eventSource, RequestId subscriptionId,
            SubscriptionFilter acceptedFilter, SubscriptionRegistry registry) {
        self.subscriptionId = subscriptionId;
        self.acceptedFilter = acceptedFilter.cloneReadOnly();
        self.keepAliveInterval = currentKeepAliveInterval();
        self.registry = registry;
        self.registryKey = registry.newKey();
        self.attachSubscriptionSource(eventSource);
        self.stopping = registry.add(self.registryKey, self);
    }

    public isolated function next() returns record {|http:SseEvent value;|}|error? {
        if self.isFinished() {
            // http asks for the next event only once the previous one was written.
            self.registry.remove(self.registryKey);
            return;
        }
        lock {
            if !self.acknowledged {
                self.acknowledged = true;
                record {} acceptedNotifications = {};
                if self.acceptedFilter.toolsListChanged {
                    acceptedNotifications["toolsListChanged"] = true;
                }
                JsonRpcNotification acknowledgement = {
                    jsonrpc: JSONRPC_VERSION,
                    method: "notifications/subscriptions/acknowledged",
                    params: {
                        _meta: {"io.modelcontextprotocol/subscriptionId": self.subscriptionId},
                        "notifications": acceptedNotifications
                    }
                };
                return {value: {data: acknowledgement.toJsonString()}};
            }
        }
        // Dropped items write nothing, so they must not push the next keep-alive back.
        decimal keepAliveDue = time:monotonicNow() + self.keepAliveInterval;
        while true {
            if self.isStopping() {
                self.closeSubscriptionSourceLater();
                return self.complete();
            }
            decimal untilKeepAlive = keepAliveDue - time:monotonicNow();
            record {|JsonRpcNotification value;|}|SOURCE_IDLE? sourceItem = untilKeepAlive > 0d
                ? check self.pollSubscriptionSource(untilKeepAlive) : SOURCE_IDLE;
            if sourceItem is SOURCE_IDLE {
                if self.isFinished() {
                    return;
                }
                if self.isStopping() {
                    continue;
                }
                return {value: {comment: "keep-alive"}};
            }
            if sourceItem is () {
                return self.complete();
            }
            if sourceItem.value.method == "notifications/tools/list_changed" && self.acceptedFilter.toolsListChanged {
                record {NotificationMeta _meta?;} notificationParams = {...(sourceItem.value.params ?: {})};
                NotificationMeta notificationMeta = {...(sourceItem.value.params?._meta ?: {})};
                notificationMeta["io.modelcontextprotocol/subscriptionId"] = self.subscriptionId;
                notificationParams._meta = notificationMeta;
                JsonRpcNotification notificationValue = {
                    jsonrpc: JSONRPC_VERSION,
                    method: sourceItem.value.method,
                    params: notificationParams
                };
                return {value: {data: notificationValue.toJsonString()}};
            }
        }
    }

    public isolated function close() returns error? {
        lock {
            self.finished = true;
        }
        self.registry.remove(self.registryKey);
        return self.closeSubscriptionSource();
    }

    // Ends the subscription with `complete` at its next event, without waiting for the source.
    isolated function stop() {
        lock {
            self.stopping = true;
        }
        self.wakeSubscriptionSource();
    }

    isolated function abort() {
        lock {
            self.finished = true;
        }
        self.registry.remove(self.registryKey);
        self.closeSubscriptionSourceLater();
    }

    private isolated function isFinished() returns boolean {
        lock {
            return self.finished;
        }
    }

    private isolated function isStopping() returns boolean {
        lock {
            return self.stopping;
        }
    }

    private isolated function complete() returns record {|http:SseEvent value;|} {
        lock {
            self.finished = true;
        }
        WireResponse completed = {
            jsonrpc: JSONRPC_VERSION,
            id: self.subscriptionId,
            result: {"resultType": "complete", _meta: {"io.modelcontextprotocol/subscriptionId": self.subscriptionId}}
        };
        return {value: {data: completed.toJsonString()}};
    }

    private isolated function attachSubscriptionSource(stream<JsonRpcNotification, error?> eventSource) = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SubscriptionSource"
    } external;

    private isolated function pollSubscriptionSource(decimal timeout)
            returns record {|JsonRpcNotification value;|}|SOURCE_IDLE|error? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SubscriptionSource"
    } external;

    private isolated function closeSubscriptionSource() returns error? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SubscriptionSource"
    } external;

    private isolated function closeSubscriptionSourceLater() = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SubscriptionSource"
    } external;

    private isolated function wakeSubscriptionSource() = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SubscriptionSource"
    } external;
}

isolated class ClientSubscriptionStream {
    private final ProtocolMessageStream messageStream;
    private final StreamableHttpClientTransport ownerTransport;
    private final RequestId subscriptionId;
    private SubscriptionFilter? acknowledgedFilter = ();
    private final SubscriptionFilter & readonly requestedFilter;
    private boolean finished = false;
    private boolean released = false;

    isolated function init(ProtocolMessageStream messageStream, RequestId subscriptionId,
            SubscriptionFilter requestedFilter, StreamableHttpClientTransport ownerTransport) {
        self.ownerTransport = ownerTransport;
        self.messageStream = messageStream;
        self.subscriptionId = subscriptionId;
        self.requestedFilter = requestedFilter.cloneReadOnly();
    }

    public isolated function next() returns record {|JsonRpcNotification value;|}|StreamError? {
        var nextItem = self.readNext();
        if nextItem is StreamError || nextItem is () {
            StreamError? closeError = self.close();
            if closeError is StreamError {
                return closeError;
            }
        }
        return nextItem;
    }

    private isolated function readNext() returns record {|JsonRpcNotification value;|}|StreamError? {
        lock {
            if self.finished {
                return;
            }
        }
        var streamItem = self.messageStream.next();
        if streamItem is StreamError {
            return streamItem;
        }
        if streamItem is () {
            return error SseEventStreamError("Subscription disconnected; reconnect explicitly to create a new subscription");
        }
        WireMessage messageValue = streamItem.value;
        if messageValue is WireResponse {
            lock {
                if self.acknowledgedFilter is () {
                    return error SseEventStreamError("Subscription ended before acknowledgment");
                }
            }
            if messageValue.id != self.subscriptionId || messageValue.result["resultType"] != "complete" {
                return error SseEventStreamError("Invalid subscription completion response");
            }
            lock {
                self.finished = true;
            }
            return;
        }
        if messageValue is WireError {
            return error SseEventStreamError(messageValue.'error.message, rpcError = messageValue);
        }
        if messageValue !is JsonRpcNotification {
            return error SseEventStreamError("Unexpected subscription message");
        }
        record {} notificationMeta = messageValue.params?._meta ?: {};
        if notificationMeta["io.modelcontextprotocol/subscriptionId"] != self.subscriptionId {
            return error SseEventStreamError("Notification subscription ID does not match");
        }
        JsonRpcNotification & readonly notificationMessage = messageValue.cloneReadOnly();
        lock {
            if self.acknowledgedFilter is () {
                if notificationMessage.method != "notifications/subscriptions/acknowledged" {
                    return error SseEventStreamError("Subscription acknowledgment must be the first message");
                }
                record {} notificationParams = notificationMessage.params ?: {};
                SubscriptionFilter|error acceptedFilter = notificationParams["notifications"].cloneWithType();
                if acceptedFilter is error || !isSubscriptionSubset(acceptedFilter, self.requestedFilter) {
                    return error SseEventStreamError("Invalid subscription acknowledgment filter");
                }
                self.acknowledgedFilter = acceptedFilter.cloneReadOnly();
            } else if !allowsSubscriptionNotification(<SubscriptionFilter>self.acknowledgedFilter, notificationMessage) {
                return error SseEventStreamError("Notification was not accepted by the subscription filter");
            }
        }
        self.ownerTransport.cache().invalidateFor(notificationMessage);
        return {value: messageValue};
    }

    public isolated function close() returns StreamError? {
        lock {
            if self.released {
                return;
            }
            self.finished = true;
            self.released = true;
        }
        self.ownerTransport.removeSubscription(self.subscriptionId);
        return self.messageStream.close();
    }
}

isolated function isSubscriptionSubset(SubscriptionFilter acceptedFilter, SubscriptionFilter requestedFilter) returns boolean {
    if (acceptedFilter.toolsListChanged && !requestedFilter.toolsListChanged) ||
            (acceptedFilter.promptsListChanged && !requestedFilter.promptsListChanged) ||
            (acceptedFilter.resourcesListChanged && !requestedFilter.resourcesListChanged) {
        return false;
    }
    foreach string resourceUri in acceptedFilter.resourceSubscriptions {
        boolean foundUri = false;
        foreach string requestedUri in requestedFilter.resourceSubscriptions {
            if resourceUri == requestedUri {
                foundUri = true;
                break;
            }
        }
        if !foundUri {
            return false;
        }
    }
    return true;
}

isolated function allowsSubscriptionNotification(SubscriptionFilter acceptedFilter, JsonRpcNotification notificationValue)
        returns boolean {
    match notificationValue.method {
        "notifications/tools/list_changed" => {
            return acceptedFilter.toolsListChanged;
        }
        "notifications/prompts/list_changed" => {
            return acceptedFilter.promptsListChanged;
        }
        "notifications/resources/list_changed" => {
            return acceptedFilter.resourcesListChanged;
        }
        "notifications/resources/updated" => {
            record {} notificationParams = notificationValue.params ?: {};
            foreach string resourceUri in acceptedFilter.resourceSubscriptions {
                if resourceUri == notificationParams["uri"] {
                    return true;
                }
            }
            return false;
        }
        _ => {
            return false;
        }
    }
}
