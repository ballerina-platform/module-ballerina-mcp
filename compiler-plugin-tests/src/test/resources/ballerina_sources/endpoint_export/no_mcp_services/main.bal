import ballerina/mcp;

listener mcp:Listener mcpListener = check new (9090);
