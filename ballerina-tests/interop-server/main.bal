import ballerina/mcp;

configurable int interopPort = ?;
listener mcp:StreamableHttpListener interopListener = new (interopPort);

@mcp:StreamableHttpServiceConfig {info: {name: "ballerina-interop", version: "1.4.0"}}
service mcp:StreamableHttpService /mcp on interopListener {
    remote isolated function add(int firstValue, int secondValue) returns int => firstValue + secondValue;
}

@mcp:StreamableHttpServiceConfig {info: {name: "ballerina-stateful-interop", version: "1.4.0"}}
service mcp:StreamableHttpService /stateful on interopListener {
    remote isolated function sessionIdentity(mcp:Session sessionValue) returns string => sessionValue.getSessionId();
}

@mcp:StreamableHttpServiceConfig {info: {name: "ballerina-modern-interop", version: "1.4.0"}, protocolMode: "modern"}
service mcp:ProtocolService /modern on interopListener {
    remote isolated function onListTools() returns mcp:ProtocolListToolsResult => {
        tools: [{name: "scalar", inputSchema: {'type: "object"}, outputSchema: {"type": "integer"}}]
    };
    remote isolated function onCallTool(mcp:CallToolParams callParams) returns mcp:ProtocolCallToolResult => {
        content: [{'type: "text", text: "42"}], structuredContent: 42
    };
}
