import ballerina/mcp;

listener mcp:Listener testListener = check new (9091);

service mcp:Service /test on testListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
