import ballerina/mcp;

const int PORT = 9090;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(PORT) {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
