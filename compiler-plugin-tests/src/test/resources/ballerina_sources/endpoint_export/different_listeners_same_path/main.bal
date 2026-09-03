import ballerina/mcp;

listener mcp:Listener listenerOne = check new (9090);
listener mcp:Listener listenerTwo = check new (9091);

service mcp:Service /mcp on listenerOne {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}

service mcp:Service /mcp on listenerTwo {
    @mcp:Tool {description: "Stub tool."}
    remote function pong() returns string {
        return "ping";
    }
}
