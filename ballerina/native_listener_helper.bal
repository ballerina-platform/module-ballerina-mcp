import ballerina/jballerina.java;

isolated function invokeOnListTools(AdvancedService 'service) returns ListToolsResult|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function invokeOnCallTool(AdvancedService 'service, CallToolParams params) returns CallToolResult|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function listToolsForRemoteFunctions(Service 'service, typedesc<ListToolsResult> t = <>) returns t|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;

isolated function callToolForRemoteFunctions(Service 'service, CallToolParams params, typedesc<CallToolResult> t = <>) returns t|error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.McpServiceMethodHelper"
} external;
