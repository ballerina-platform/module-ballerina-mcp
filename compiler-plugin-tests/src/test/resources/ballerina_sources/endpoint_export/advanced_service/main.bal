import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);

service mcp:StreamableHttpAdvancedService /mcp on mcpListener {

    remote isolated function onListTools() returns mcp:ToolPage|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params, mcp:Session? session)
            returns mcp:ToolResult|mcp:ServerError {
        return error mcp:ServerError("not implemented");
    }
}
