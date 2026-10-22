import ballerina/mcp.v2 as mcp;
@mcp:StreamableHttpServiceConfig {info: {name: "session-test", version: "1"}, protocolMode: "auto"}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9000) {
    remote isolated function inspectSession(mcp:HttpSession? sessionValue) returns string {
        return sessionValue is mcp:HttpSession ? sessionValue.getSessionId() : "none";
    }
}
