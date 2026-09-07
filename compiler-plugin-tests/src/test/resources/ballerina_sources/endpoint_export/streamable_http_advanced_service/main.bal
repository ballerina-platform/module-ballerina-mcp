import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9093);

@mcp:StreamableHttpServiceConfig {
    info: {name: "streamable-advanced", version: "1.0.0"}
}
service mcp:StreamableHttpAdvancedService /advanced on mcpListener {
    remote function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote function onCallTool(mcp:CallToolParams params) returns mcp:CallToolResult|mcp:ServerError {
        return {content: []};
    }
}
