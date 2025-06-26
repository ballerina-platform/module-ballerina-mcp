
// listener Listener mcpListener = check new (9090, serverConfigs = {
//     serverInfo: {
//         name: "MCP Server",
//         version: "1.0.0"
//     },
//     options: {capabilities: {}}
// });

// service /mcp on mcpListener {
//     remote isolated function onListTools() returns ListToolsResult|error {
//         return {
//             tools: [
//                 {
//                     name: "single-greet",
//                     description: "Greet the user once",
//                     inputSchema: {
//                         'type: "object",
//                         properties: {
//                             "name": {"type": "string", "description": "Name to greet"}
//                         },
//                         required: ["name"]
//                     }
//                 },
//                 {
//                     name: "multi-greet",
//                     description: "Greet the user multiple times with delay in between.",
//                     inputSchema: {
//                         'type: "object",
//                         properties: {
//                             "name": {"type": "string", "description": "Name to greet"}
//                         },
//                         required: ["name"]
//                     }
//                 }
//             ]
//         };
//     }

//     remote isolated function onCallTool(CallToolParams params) returns CallToolResult|error {
//         string name = check (params.arguments["name"]).cloneWithType();
//         if params.name == "single-greet" {
//             // Note: Can do any external function calls here,
//             TextContent textContent = {
//                 'type: "text",
//                 text: string `Hey ${name}! Welcome to itsuki's world!`
//             };
//             return {
//                 content: [textContent]
//             };
//         } else if params.name == "multi-greet" {
//             // Note: Can do any external function calls here,
//             TextContent textContent = {
//                 'type: "text",
//                 text: string `Hey ${name}! Hope you enjoy your day!`
//             };
//             return {
//                 content: [textContent]
//             };
//         } else {
//             return error("Unknown tool: " + params.name);
//         }
//     }
// }

listener Listener basicListener = check new (9092, serverInfo = {name: "Basic MCP Server", version: "1.0.0"});

isolated service Service /mcp on basicListener {
    @McpTool {
        description: "Add two numbers",
        schema: {
            'type: "object",
            properties: {
                "a": {"type": "integer", "description": "First number"},
                "b": {"type": "integer", "description": "Second number"}
            },
            required: ["a", "b"]
        }
    }
    remote function add(int a, int b) returns int {
        return a + b;
    }

    @McpTool
    remote function add1(int a, int b) returns int {
        return a + b;
    }
}
