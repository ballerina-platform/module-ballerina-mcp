import ballerina/mcp;

service mcp:StreamableHttpService /root on new mcp:StreamableHttpListener(9090) {
    # Root tool
    remote function rootTool(int a) returns int {
        return a;
    }
}
