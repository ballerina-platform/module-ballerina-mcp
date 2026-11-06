import ballerina/mcp;
import ballerina/mcp.v2;

service mcp:StreamableHttpService /root on new mcp:StreamableHttpListener(9090) {
    # Takes a v2 context
    remote function withContext(v2:Context context) returns string {
        return "";
    }

    # Returns a v2 input request
    remote function withInputRequired(string text) returns string|v2:InputRequiredResult {
        return text;
    }
}
