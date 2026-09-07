import ballerina/mcp;

service mcp:Service /mcp on undefinedListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
