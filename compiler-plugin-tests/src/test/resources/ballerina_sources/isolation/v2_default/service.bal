import ballerina/mcp.v2;

service v2:StreamableHttpService /v2 on new v2:StreamableHttpListener(9091) {
    # Adds two numbers
    remote function add(int a, int b) returns int {
        return a + b;
    }
}
