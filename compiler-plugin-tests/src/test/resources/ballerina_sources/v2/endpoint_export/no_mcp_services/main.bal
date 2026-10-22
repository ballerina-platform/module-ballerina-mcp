import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);
