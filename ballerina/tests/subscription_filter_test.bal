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
function testSubscriptionSubsetAcceptsNarrowerFilters() {
    SubscriptionFilter requestedFilter = {
        toolsListChanged: true,
        promptsListChanged: true,
        resourcesListChanged: true,
        resourceSubscriptions: ["file:///a", "file:///b"]
    };
    test:assertTrue(isSubscriptionSubset({}, requestedFilter));
    test:assertTrue(isSubscriptionSubset({toolsListChanged: true}, requestedFilter));
    test:assertTrue(isSubscriptionSubset(requestedFilter, requestedFilter));
    test:assertTrue(isSubscriptionSubset({resourceSubscriptions: ["file:///b"]}, requestedFilter));
}

@test:Config {}
function testSubscriptionSubsetRejectsWiderFilters() {
    SubscriptionFilter narrowFilter = {toolsListChanged: true};
    test:assertFalse(isSubscriptionSubset({toolsListChanged: true, promptsListChanged: true}, narrowFilter));
    test:assertFalse(isSubscriptionSubset({toolsListChanged: true, resourcesListChanged: true}, narrowFilter));
    test:assertFalse(isSubscriptionSubset({promptsListChanged: true}, {promptsListChanged: false}));
    test:assertFalse(isSubscriptionSubset({resourceSubscriptions: ["file:///c"]},
            {resourceSubscriptions: ["file:///a"]}));
}

@test:Config {}
function testSubscriptionNotificationFiltering() {
    SubscriptionFilter toolsOnly = {toolsListChanged: true};
    test:assertTrue(allowsSubscriptionNotification(toolsOnly,
            {jsonrpc: JSONRPC_VERSION, method: "notifications/tools/list_changed"}));
    test:assertFalse(allowsSubscriptionNotification(toolsOnly,
            {jsonrpc: JSONRPC_VERSION, method: "notifications/prompts/list_changed"}));

    SubscriptionFilter listFilters = {promptsListChanged: true, resourcesListChanged: true};
    test:assertTrue(allowsSubscriptionNotification(listFilters,
            {jsonrpc: JSONRPC_VERSION, method: "notifications/prompts/list_changed"}));
    test:assertTrue(allowsSubscriptionNotification(listFilters,
            {jsonrpc: JSONRPC_VERSION, method: "notifications/resources/list_changed"}));

    // Unknown notification methods are never delivered.
    test:assertFalse(allowsSubscriptionNotification(toolsOnly,
            {jsonrpc: JSONRPC_VERSION, method: "notifications/progress"}));
}

@test:Config {}
function testResourceUpdateNotificationsMatchOnUri() {
    SubscriptionFilter resourceFilter = {resourceSubscriptions: ["file:///watched"]};
    test:assertTrue(allowsSubscriptionNotification(resourceFilter, {
        jsonrpc: JSONRPC_VERSION,
        method: "notifications/resources/updated",
        params: {"uri": "file:///watched"}
    }));
    test:assertFalse(allowsSubscriptionNotification(resourceFilter, {
        jsonrpc: JSONRPC_VERSION,
        method: "notifications/resources/updated",
        params: {"uri": "file:///other"}
    }));
    // A resource update without a URI matches nothing.
    test:assertFalse(allowsSubscriptionNotification(resourceFilter, {
        jsonrpc: JSONRPC_VERSION,
        method: "notifications/resources/updated"
    }));
}

isolated function firstSubscriptionError(string scenario) returns error? {
    StreamableHttpClient subscriptionClient = check new (mockUrl(scenario), protocolMode = "modern");
    _ = check subscriptionClient->connect();
    stream<JsonRpcMessage, StreamError?> eventStream = check subscriptionClient->listen();
    error? streamError = ();
    while true {
        var nextItem = eventStream.next();
        if nextItem is error {
            streamError = nextItem;
            break;
        }
        if nextItem is () {
            break;
        }
    }
    // next() already closed the stream; the client itself still holds the connection.
    ClientError? closeError = subscriptionClient->close();
    return streamError ?: closeError;
}

@test:Config {}
function testClientSubscriptionRejectsProtocolViolations() returns error? {
    map<string> expectedMessages = {
        "subNoAck": "Subscription acknowledgment must be the first message",
        "subBadFilter": "Invalid subscription acknowledgment filter",
        "subWrongId": "Notification subscription ID does not match",
        "subDisallowed": "Notification was not accepted by the subscription filter",
        "subError": "subscription failed",
        "subEarlyComplete": "Subscription ended before acknowledgment",
        "subBadComplete": "Invalid subscription completion response",
        "subDisconnect": "Subscription disconnected",
        "subUnexpected": "Unexpected subscription message"
    };
    foreach var [scenario, expectedMessage] in expectedMessages.entries() {
        error? subscriptionError = firstSubscriptionError(scenario);
        test:assertTrue(subscriptionError is error, string `${scenario} should surface an error`);
        if subscriptionError is error {
            test:assertTrue(subscriptionError.message().includes(expectedMessage),
                    string `${scenario}: unexpected message '${subscriptionError.message()}'`);
        }
    }
}

@test:Config {}
function testClientSubscriptionDeliversAcknowledgedNotifications() returns error? {
    StreamableHttpClient subscriptionClient = check new (mockUrl("subComplete"), protocolMode = "modern");
    _ = check subscriptionClient->connect();
    stream<JsonRpcMessage, StreamError?> eventStream = check subscriptionClient->listen();

    var ackEvent = check eventStream.next();
    test:assertTrue(ackEvent is record {|JsonRpcMessage value;|});
    if ackEvent is record {|JsonRpcMessage value;|} {
        JsonRpcMessage ackMessage = ackEvent.value;
        test:assertTrue(ackMessage is JsonRpcNotification);
        if ackMessage is JsonRpcNotification {
            test:assertEquals(ackMessage.method, "notifications/subscriptions/acknowledged");
        }
    }

    var changeEvent = check eventStream.next();
    test:assertTrue(changeEvent is record {|JsonRpcMessage value;|});
    if changeEvent is record {|JsonRpcMessage value;|} {
        JsonRpcMessage changeMessage = changeEvent.value;
        test:assertTrue(changeMessage is JsonRpcNotification);
        if changeMessage is JsonRpcNotification {
            test:assertEquals(changeMessage.method, "notifications/tools/list_changed");
        }
    }

    // The completion response terminates the stream.
    test:assertEquals(check eventStream.next(), ());
    check eventStream.close();
    check subscriptionClient->close();
}

@test:Config {}
function testSubscriptionRequiresAnSseResponse() returns error? {
    StreamableHttpClient subscriptionClient = check new (mockUrl("subNotSse"), protocolMode = "modern");
    _ = check subscriptionClient->connect();
    var listenResult = subscriptionClient->listen();
    check subscriptionClient->close();
    test:assertTrue(listenResult is ClientError);
    if listenResult is ClientError {
        test:assertTrue(listenResult.message().includes("Invalid subscription filter"));
    }
}
