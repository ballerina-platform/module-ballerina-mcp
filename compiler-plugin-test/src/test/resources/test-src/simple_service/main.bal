import ballerina/mcp;

listener mcp:Listener mcpListener = check new (9090);

service mcp:Service /mcp on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
