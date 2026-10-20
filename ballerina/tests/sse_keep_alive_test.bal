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
function testSubscriptionSkipsKeepAliveComments() returns error? {
    StreamableHttpClient modernClient = check new (mockUrl("sseKeepAlive"), protocolMode = "modern");
    _ = check modernClient->connect();
    stream<JsonRpcMessage, StreamError?> events = check modernClient->listen();
    string[] methods = [];
    check from JsonRpcMessage message in events
        do {
            if message is JsonRpcNotification {
                methods.push(message.method);
            }
        };
    test:assertEquals(methods, ["notifications/subscriptions/acknowledged", "notifications/tools/list_changed"]);
    check modernClient->close();
}

@test:Config {}
function testModernSseToolCallSkipsKeepAliveComments() returns error? {
    StreamableHttpClient modernClient = check new (mockUrl("sseKeepAlive"), protocolMode = "modern");
    _ = check modernClient->connect();
    CallToolResult result = check modernClient->callTool({name: "echo"});
    test:assertEquals(result.content, [{'type: "text", text: "after keep-alive"}]);
    check modernClient->close();
}

@test:Config {}
function testLegacyEventStreamSkipsKeepAliveComments() returns error? {
    StreamableHttpClient legacyClient = check legacyMockClient("sseKeepAlive");
    stream<JsonRpcMessage, StreamError?> events = check legacyClient->listen();
    foreach int _ in 0 ..< 2 {
        var notification = check events.next();
        test:assertTrue(notification is record {|JsonRpcMessage value;|});
        if notification is record {|JsonRpcMessage value;|} {
            JsonRpcMessage message = notification.value;
            test:assertTrue(message is JsonRpcNotification);
            if message is JsonRpcNotification {
                test:assertEquals(message.method, "notifications/tools/list_changed");
            }
        }
    }
    test:assertEquals(check events.next(), ());
    check events.close();
}

@test:Config {}
function testLegacySseToolCallSkipsKeepAliveComments() returns error? {
    StreamableHttpClient legacyClient = check legacyMockClient("sseKeepAlive");
    CallToolResult result = check legacyClient->callTool({name: "echo"});
    test:assertEquals(result.content, [{'type: "text", text: "after keep-alive"}]);
}

@test:Config {}
function testLegacySseToolCallSkipsPrimingEvents() returns error? {
    StreamableHttpClient legacyClient = check legacyMockClient("ssePriming");
    CallToolResult result = check legacyClient->callTool({name: "echo"});
    test:assertEquals(result.content, [{'type: "text", text: "after priming"}]);
}
