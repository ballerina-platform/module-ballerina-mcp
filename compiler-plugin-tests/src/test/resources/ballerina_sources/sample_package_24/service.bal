import ballerina/mcp;
type OptionalSession mcp:Session?;
const string PROTOCOL_MODE = "modern";
@mcp:StreamableHttpServiceConfig {
    info: {name: "alias-test", version: "1"}, protocolMode: PROTOCOL_MODE, sessionMode: mcp:STATELESS
}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9000) {
    remote isolated function inspectSession(OptionalSession sessionValue) returns string {
        return sessionValue is mcp:Session ? sessionValue.getSessionId() : "none";
    }
    isolated function localHelper(OptionalSession sessionValue) returns boolean => sessionValue is ();
}
