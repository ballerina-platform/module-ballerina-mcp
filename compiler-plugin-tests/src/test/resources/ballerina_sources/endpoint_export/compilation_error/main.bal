import ballerina/mcp;

service mcp:StreamableHttpService /mcp on undefinedListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
