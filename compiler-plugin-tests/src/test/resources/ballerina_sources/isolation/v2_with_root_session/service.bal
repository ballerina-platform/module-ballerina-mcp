import ballerina/mcp;
import ballerina/mcp.v2;

service v2:StreamableHttpService /v2 on new v2:StreamableHttpListener(9091) {
    # Takes a root session
    remote function withSession(mcp:Session session, string text) returns string {
        return text;
    }
}
