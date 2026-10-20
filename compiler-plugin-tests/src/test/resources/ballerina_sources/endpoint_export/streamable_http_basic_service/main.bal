import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9092);

@mcp:StreamableHttpServiceConfig {
    info: {name: "streamable-basic", version: "1.0.0"}
}
service mcp:StreamableHttpService /streamable on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
