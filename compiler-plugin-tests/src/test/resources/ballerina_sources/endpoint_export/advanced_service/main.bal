import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);

service mcp:StreamableHttpAdvancedService /mcp on mcpListener {

    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params, mcp:HttpSession? session)
            returns mcp:CallToolResult|mcp:ServerError {
        return error mcp:ServerError("not implemented");
    }
}
