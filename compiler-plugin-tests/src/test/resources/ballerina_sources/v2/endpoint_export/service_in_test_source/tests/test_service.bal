import ballerina/mcp;

listener mcp:StreamableHttpListener testListener = check new (9091);

service mcp:StreamableHttpService /test on testListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
