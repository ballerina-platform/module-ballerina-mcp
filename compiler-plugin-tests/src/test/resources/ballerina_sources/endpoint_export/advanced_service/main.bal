import ballerina/mcp;

listener mcp:Listener mcpListener = check new (9090);

service mcp:AdvancedService /mcp on mcpListener {

    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params, mcp:Session? session)
            returns mcp:CallToolResult|mcp:ServerError {
        return error mcp:ServerError("not implemented");
    }
}
