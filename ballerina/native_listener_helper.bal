import ballerina/jballerina.java;

isolated function invokeOnListTools(McpService 'service) returns ListToolsResult|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function invokeOnCallTool(McpService 'service, CallToolParams params) returns CallToolResult|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function listToolsForRemoteFunctions(McpDeclarativeService 'service, typedesc<ListToolsResult> t = <>) returns t|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function callToolForRemoteFunctions(McpDeclarativeService 'service, CallToolParams params, typedesc<CallToolResult> t = <>) returns t|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;
