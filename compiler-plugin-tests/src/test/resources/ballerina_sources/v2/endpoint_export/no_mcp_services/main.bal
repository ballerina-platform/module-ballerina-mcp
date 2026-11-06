import ballerina/mcp.v2 as mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);
