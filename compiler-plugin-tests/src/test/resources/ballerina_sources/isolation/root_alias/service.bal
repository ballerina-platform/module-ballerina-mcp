import ballerina/mcp as old;

service old:StreamableHttpService /root on new old:StreamableHttpListener(9090) {
    # Adds two numbers
    remote function add(int a, int b) returns int {
        return a + b;
    }

    @old:Tool {description: "Explicit"}
    remote function echo(string text) returns string {
        return text;
    }
}
