import ballerina/mcp;
import ballerina/mcp.v2 as _;

service mcp:StreamableHttpService /root on new mcp:StreamableHttpListener(9090) {
    # Root tool
    remote function rootTool(int a) returns int {
        return a;
    }
}
