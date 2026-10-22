import ballerina/mcp;
import ballerina/mcp.v2;

service mcp:StreamableHttpService /root on new mcp:StreamableHttpListener(9090) {
    # Root tool
    remote function rootTool(int a) returns int {
        return a;
    }
}

service v2:StreamableHttpService /v2 on new v2:StreamableHttpListener(9091) {
    # V2 tool
    remote function v2Tool(int a) returns int {
        return a;
    }
}
