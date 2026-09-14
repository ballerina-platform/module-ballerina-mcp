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

@StreamableHttpServiceConfig {info: {name: "subscription-test", version: "1"}}
service StreamableHttpAdvancedService /mcp on new StreamableHttpListener(3206) {
    remote isolated function onListTools() returns ProtocolListToolsResult => {tools: []};

    remote isolated function onCallTool(CallToolParams callParams) returns ProtocolCallToolResult => {content: []};

    remote isolated function onSubscribe(SubscriptionFilter notifications) returns stream<JsonRpcNotification, error?> {
        TestNotificationSource eventSource = new;
        return new (eventSource);
    }
}

isolated class TestNotificationSource {
    private boolean sentEvent = false;

    public isolated function next() returns record {|JsonRpcNotification value;|}|error? {
        lock {
            if self.sentEvent {
                return;
            }
            self.sentEvent = true;
            return {value: {jsonrpc: JSONRPC_VERSION, method: "notifications/tools/list_changed"}};
        }
    }

    public isolated function close() returns error? {
        lock {
            self.sentEvent = true;
        }
    }
}

@test:Config {}
function testSubscriptionAcknowledgementAndCompletion() returns error? {
    StreamableHttpClient subscriptionClient = check new ("http://localhost:3206/mcp");
    stream<JsonRpcNotification, StreamError?> eventStream = check subscriptionClient->listen();
    var firstEvent = check eventStream.next();
    test:assertTrue(firstEvent is record {|JsonRpcNotification value;|});
    if firstEvent is record {|JsonRpcNotification value;|} {
        test:assertEquals(firstEvent.value.method, "notifications/subscriptions/acknowledged");
    }
    var secondEvent = check eventStream.next();
    test:assertTrue(secondEvent is record {|JsonRpcNotification value;|});
    if secondEvent is record {|JsonRpcNotification value;|} {
        test:assertEquals(secondEvent.value.method, "notifications/tools/list_changed");
    }
    test:assertEquals(check eventStream.next(), ());
    check eventStream.close();
    check subscriptionClient->close();
}

@test:Config {}
function testClientCloseCancelsSubscriptions() returns error? {
    StreamableHttpClient subscriptionClient = check new ("http://localhost:3206/mcp");
    stream<JsonRpcNotification, StreamError?> eventStream = check subscriptionClient->listen();
    _ = check eventStream.next();
    check subscriptionClient->close();
    test:assertEquals(check eventStream.next(), ());
}
