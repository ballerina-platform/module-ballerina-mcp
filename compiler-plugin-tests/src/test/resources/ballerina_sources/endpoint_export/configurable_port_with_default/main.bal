import ballerina/mcp;

configurable int port = 9090;

listener mcp:Listener mcpListener = check new (port);

service mcp:Service /mcp on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
