import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9095);

@mcp:StreamableHttpServiceConfig {
    info: {name: "streamable-transport-agnostic", version: "1.0.0"}
}
service mcp:Service /transportagnostic on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
