import ballerina/mcp;

listener mcp:Listener mcpListener = check new (9090);

service mcp:Service /alpha on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}

service mcp:Service /beta on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function pong() returns string {
        return "ping";
    }
}
