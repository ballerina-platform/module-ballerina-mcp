import ballerina/mcp;

service mcp:StreamableHttpService /root on new mcp:StreamableHttpListener(9090) {
    # Root tool
    remote function rootTool(UndefinedType a) returns int {
        return a;
    }
}

service mcp:StreamableHttpAdvancedService /rootAdvanced on undefinedListener {
    remote function onCallTool(mcp:CallToolParams params) returns mcp:CallToolResult {
        return missing;
    }
}
