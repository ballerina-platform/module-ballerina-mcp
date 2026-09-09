import ballerina/test;

@StreamableHttpServiceConfig {info: {name: "subscription-test", version: "1"}}
service SubscriptionService /mcp on new StreamableHttpListener(3206) {
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
