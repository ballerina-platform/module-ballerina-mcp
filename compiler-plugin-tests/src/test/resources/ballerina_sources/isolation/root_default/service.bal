import ballerina/mcp;

service mcp:StreamableHttpService /root on new mcp:StreamableHttpListener(9090) {
    # Adds two numbers
    remote function add(int a, int b) returns int {
        return a + b;
    }
}
