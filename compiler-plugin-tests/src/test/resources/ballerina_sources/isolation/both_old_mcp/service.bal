import ballerina/mcp as old;
import ballerina/mcp.v2 as mcp;

service old:StreamableHttpService /root on new old:StreamableHttpListener(9090) {
    # Root tool
    remote function rootTool(int a) returns int {
        return a;
    }
}

service mcp:StreamableHttpService /v2 on new mcp:StreamableHttpListener(9091) {
    # V2 tool
    remote function v2Tool(int a) returns int {
        return a;
    }
}
