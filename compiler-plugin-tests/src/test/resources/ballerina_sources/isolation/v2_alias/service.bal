import ballerina/mcp.v2 as m2;

service m2:StreamableHttpService /v2 on new m2:StreamableHttpListener(9091) {
    # Adds two numbers
    remote function add(int a, int b) returns int {
        return a + b;
    }
}
