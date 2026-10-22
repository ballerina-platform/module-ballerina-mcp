import ballerina/mcp;

configurable int port = ?;

listener mcp:StreamableHttpListener mcpListener = check new (port);

service mcp:StreamableHttpService /mcp on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
