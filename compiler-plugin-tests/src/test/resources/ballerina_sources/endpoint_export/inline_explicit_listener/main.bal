import ballerina/mcp;

const int PORT = 9090;

service mcp:Service /mcp on new mcp:Listener(PORT) {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}
