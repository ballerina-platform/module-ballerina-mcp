import ballerina/mcp;
@mcp:StreamableHttpServiceConfig {info: {name: "session-test", version: "1"}, protocolMode: "modern"}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9000) {
    remote isolated function inspectSession(mcp:Session? sessionValue) returns string {
        return sessionValue is mcp:Session ? sessionValue.getSessionId() : "none";
    }
}
