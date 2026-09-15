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

# Selects change notifications for a subscription.
public type SubscriptionFilter record {|
    # Subscribe to tool list changes.
    boolean toolsListChanged = false;
    # Subscribe to prompt list changes when supported by the peer.
    boolean promptsListChanged = false;
    # Subscribe to resource list changes when supported by the peer.
    boolean resourcesListChanged = false;
    # Resource URIs whose changes should be observed.
    string[] resourceSubscriptions = [];
|};

isolated function invokeOnSubscribe(StreamableHttpAdvancedService mcpService, SubscriptionFilter notifications)
        returns stream<JsonRpcNotification, error?>|ServerError = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function hasSubscriptionHandler(StreamableHttpAdvancedService mcpService) returns boolean = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

// The shared native stream holder permits close to run while the event source waits in next.
isolated class ServerSubscriptionStream {
    private final RequestId subscriptionId;
    private final SubscriptionFilter & readonly acceptedFilter;
    private boolean acknowledged = false;
    private boolean finished = false;

    isolated function init(stream<JsonRpcNotification, error?> eventSource, RequestId subscriptionId,
            SubscriptionFilter acceptedFilter) {
        self.subscriptionId = subscriptionId;
        self.acceptedFilter = acceptedFilter.cloneReadOnly();
        self.attachSseStream(eventSource);
    }

    public isolated function next() returns record {|http:SseEvent value;|}|error? {
        lock {
            if self.finished {
                return;
            }
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
        while true {
            var sourceItem = check self.getNextSseEvent();
            if sourceItem is () {
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
            if sourceItem.value.method == "notifications/tools/list_changed" && self.acceptedFilter.toolsListChanged {
                record {NotificationMetaObject _meta?;} notificationParams = {...(sourceItem.value.params ?: {})};
                NotificationMetaObject notificationMeta = {...(sourceItem.value.params?._meta ?: {})};
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
        return self.closeSseEventStream();
    }

    private isolated function attachSseStream(stream<JsonRpcNotification, error?> sseEventStream) = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SseEventStreamHelper"
    } external;

    private isolated function getNextSseEvent() returns record {|JsonRpcNotification value;|}?|error? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SseEventStreamHelper"
    } external;

    private isolated function closeSseEventStream() returns error? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.SseEventStreamHelper"
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
