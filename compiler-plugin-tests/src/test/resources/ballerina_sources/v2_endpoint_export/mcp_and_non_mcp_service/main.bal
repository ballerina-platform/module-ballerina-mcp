import ballerina/http;
import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);

service mcp:StreamableHttpService /mcp on mcpListener {
    @mcp:Tool {description: "Stub tool."}
    remote function ping() returns string {
        return "pong";
    }
}

listener http:Listener httpListener = new (8080);

service /api on httpListener {
    resource function get hello() returns string {
        return "hi";
    }
}
