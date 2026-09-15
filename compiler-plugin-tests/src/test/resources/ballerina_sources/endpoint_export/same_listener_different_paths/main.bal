import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);

service mcp:StreamableHttpService /alpha on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}

service mcp:StreamableHttpService /beta on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function pong() returns string {
        return "ping";
    }
}
