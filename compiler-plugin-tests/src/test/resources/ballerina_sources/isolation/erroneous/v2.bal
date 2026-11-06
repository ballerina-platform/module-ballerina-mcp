import ballerina/mcp.v2;

service v2:StreamableHttpService /v2 on new v2:StreamableHttpListener(9091) {
    # V2 tool
    remote function v2Tool(UndefinedType a) returns int {
        return v2:elicitForm("Broken", UndefinedRecord);
    }
}

service v2:StreamableHttpAdvancedService /v2Advanced on undefinedListener {
    remote function onListTools() returns v2:ListToolsResult {
        return missing;
    }
}
