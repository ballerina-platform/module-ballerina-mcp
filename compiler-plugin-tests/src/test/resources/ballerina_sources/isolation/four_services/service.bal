import ballerina/mcp as old;
import ballerina/mcp.v2 as mcp;

listener old:StreamableHttpListener rootListener = check new (9090);
listener mcp:StreamableHttpListener v2Listener = check new (9091);

service old:StreamableHttpService /rootBasic on rootListener {
    # Root tool
    remote function rootTool(int a) returns int {
        return a;
    }
}

service old:StreamableHttpAdvancedService /rootAdvanced on rootListener {
    remote isolated function onListTools() returns old:ListToolsResult|old:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(old:CallToolParams params, old:Session? session)
            returns old:CallToolResult|old:ServerError {
        return error old:ServerError("not implemented");
    }
}

service mcp:StreamableHttpService /v2Basic on v2Listener {
    # V2 tool
    remote function v2Tool(int a) returns int {
        return a;
    }
}

service mcp:StreamableHttpAdvancedService /v2Advanced on v2Listener {
    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params, mcp:HttpSession? session)
            returns mcp:CallToolResult|mcp:ServerError {
        return error mcp:ServerError("not implemented");
    }
}
