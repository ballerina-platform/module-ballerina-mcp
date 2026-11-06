import ballerina/mcp;
import ballerina/mcp.v2;

listener mcp:StreamableHttpListener rootListener = check new (9090);
listener v2:StreamableHttpListener v2Listener = check new (9091);

service mcp:StreamableHttpService /root on rootListener {
    @mcp:Tool {description: "Root tool."}
    remote function ping() returns string {
        return "pong";
    }
}

service v2:StreamableHttpService /v2 on v2Listener {
    @v2:Tool {description: "V2 tool."}
    remote function ping() returns string {
        return "pong";
    }
}
