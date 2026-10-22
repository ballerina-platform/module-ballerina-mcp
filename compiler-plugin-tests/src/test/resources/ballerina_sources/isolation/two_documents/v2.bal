import ballerina/mcp.v2 as mcp;

service mcp:StreamableHttpService /v2 on new mcp:StreamableHttpListener(9091) {
    # V2 tool
    remote function v2Tool(int a) returns int {
        return a;
    }
}
