import ballerina/mcp;

listener mcp:StreamableHttpListener listenerOne = check new (9090);
listener mcp:StreamableHttpListener listenerTwo = check new (9091);

service mcp:StreamableHttpService /mcp on listenerOne {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}

service mcp:StreamableHttpService /mcp on listenerTwo {
    @mcp:Tool {description: "Stub tool."}
    remote function pong() returns string {
        return "ping";
    }
}
