import ballerina/mcp;
@mcp:StreamableHttpConfig {info: {name: "session-test", version: "1"}, protocolMode: "modern"}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9000) {
    remote isolated function inspectSession(mcp:HttpSession? sessionValue) returns string {
        return sessionValue is mcp:HttpSession ? sessionValue.getSessionId() : "none";
    }
}
