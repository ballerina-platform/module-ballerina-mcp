import ballerina/mcp.v2 as mcp;

service mcp:StreamableHttpService /v2 on new mcp:StreamableHttpListener(9091) {
    # Adds two numbers
    remote function add(int a, int b) returns int {
        return a + b;
    }
}
