// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/test;

// ---------------------------------------------------------------------------
// Implementation — verifies new fields: title, description, websiteUrl, icons
// ---------------------------------------------------------------------------

@test:Config {}
function testImplementation() {
    Implementation impl = {
        name: "my-server",
        title: "My Server",
        version: "1.0.0",
        description: "An MCP server",
        websiteUrl: "https://example.com",
        icons: [
            {mimeType: "image/png", data: "icon16", size: 16},
            {mimeType: "image/svg+xml", data: "<svg/>"}
        ]
    };
    test:assertEquals(impl.title, "My Server");
    test:assertEquals(impl.description, "An MCP server");
    test:assertEquals(impl.websiteUrl, "https://example.com");
    Icon[] icons = impl.icons ?: [];
    test:assertEquals(icons.length(), 2);
    test:assertEquals(icons[0].size, 16);
}

// ---------------------------------------------------------------------------
// ClientCapabilities — verifies new fields: elicitation, tasks
// Note: task types are defined for protocol compatibility but server-side
// task execution is not yet supported.
// ---------------------------------------------------------------------------

@test:Config {}
function testClientCapabilities() {
    ClientCapabilities capabilities = {
        sampling: {context: {}, tools: {}},
        elicitation: {form: {}, url: {}},
        tasks: {
            list: {},
            cancel: {},
            requests: {
                sampling: {createMessage: {}},
                elicitation: {create: {}}
            }
        }
    };
    test:assertTrue(capabilities.elicitation?.form != ());
    test:assertTrue(capabilities.elicitation?.url != ());
    test:assertTrue(capabilities.tasks?.list != ());
    test:assertTrue(capabilities.tasks?.cancel != ());
    test:assertTrue(capabilities.tasks?.requests?.sampling?.createMessage != ());
    test:assertTrue(capabilities.tasks?.requests?.elicitation?.create != ());
}

// ---------------------------------------------------------------------------
// ServerCapabilities — verifies new tasks field
// ---------------------------------------------------------------------------

@test:Config {}
function testServerCapabilities() {
    ServerCapabilities capabilities = {
        tools: {listChanged: true},
        tasks: {
            list: {},
            cancel: {},
            requests: {tools: {call: {}}}
        }
    };
    test:assertEquals(capabilities.tools?.listChanged, true);
    test:assertTrue(capabilities.tasks?.list != ());
    test:assertTrue(capabilities.tasks?.requests?.tools?.call != ());
}

// ---------------------------------------------------------------------------
// ResourceLink — verifies new type field and inherited Resource fields
// ---------------------------------------------------------------------------

@test:Config {}
function testResourceLink() {
    ResourceLink link = {
        name: "report",
        uri: "file:///report.pdf",
        'type: "resource_link",
        mimeType: "application/pdf",
        description: "Generated report",
        size: 8192
    };
    test:assertEquals(link.'type, "resource_link");
    test:assertEquals(link.mimeType, "application/pdf");
    test:assertEquals(link.size, 8192);
}

// ---------------------------------------------------------------------------
// ContentBlock union — verifies all five member types are assignable
// ---------------------------------------------------------------------------

@test:Config {}
function testContentBlockUnion() {
    ContentBlock text = {'type: "text", text: "Hello"};
    ContentBlock image = {'type: "image", data: "base64", mimeType: "image/png"};
    ContentBlock audio = {'type: "audio", data: "base64", mimeType: "audio/mpeg"};
    ContentBlock resLink = {'type: "resource_link", name: "f", uri: "file:///f.txt"};
    ContentBlock embedded = {'type: "resource", 'resource: {uri: "file:///f.txt", text: "content"}};

    test:assertTrue(text is TextContent);
    test:assertTrue(image is ImageContent);
    test:assertTrue(audio is AudioContent);
    test:assertTrue(resLink is ResourceLink);
    test:assertTrue(embedded is EmbeddedResource);
}

// ---------------------------------------------------------------------------
// ToolDefinition — verifies new fields: title, icons, execution, outputSchema
// Note: execution.taskSupport describes protocol capability; server-side task
// execution is not yet supported.
// ---------------------------------------------------------------------------

@test:Config {}
function testToolDefinition() {
    ToolDefinition tool = {
        name: "calculate",
        title: "Calculate",
        description: "Performs a calculation",
        inputSchema: {
            'type: "object",
            properties: {"x": {}, "y": {}},
            required: ["x", "y"]
        },
        outputSchema: {
            'type: "object",
            properties: {"result": {}}
        },
        execution: {taskSupport: "optional"},
        icons: [{mimeType: "image/png", data: "icon", size: 32}]
    };
    test:assertEquals(tool.title, "Calculate");
    test:assertEquals(tool.outputSchema?.'type, "object");
    test:assertEquals(tool.execution?.taskSupport, "optional");
    test:assertEquals((tool.icons ?: [])[0].size, 32);
}

// ---------------------------------------------------------------------------
// CallToolParams — verifies name and arguments fields
// ---------------------------------------------------------------------------

@test:Config {}
function testCallToolParams() {
    CallToolParams withArgs = {
        name: "tool_with_args",
        arguments: {"input": "data"}
    };
    CallToolParams withoutArgs = {name: "sync_tool"};
    test:assertEquals(withArgs.name, "tool_with_args");
    test:assertEquals(withoutArgs.arguments, ());
}

// ---------------------------------------------------------------------------
// CallToolResult — verifies structuredContent and ResourceLink in content
// ---------------------------------------------------------------------------

@test:Config {}
function testCallToolResult() {
    CallToolResult result = {
        content: [
            {'type: "text", text: "Summary"},
            {'type: "resource_link", name: "output", uri: "file:///out.json"}
        ],
        structuredContent: {"value": 42}
    };
    test:assertEquals(result.content.length(), 2);
    test:assertTrue(result.content[1] is ResourceLink);
    test:assertTrue(result.structuredContent != ());
    test:assertEquals(result.isError, ());
}

// ---------------------------------------------------------------------------
// JsonRpcResponseTypes — verifies ServerResult union membership
// ---------------------------------------------------------------------------

@test:Config {}
function testJsonRpcResponseTypes() {
    CallToolResult toolResult = {content: [{'type: "text", text: "done"}]};
    JsonRpcResponse resultResponse = {jsonrpc: "2.0", id: 1, result: toolResult};
    JsonRpcError errorResponse = {
        jsonrpc: "2.0",
        id: (),
        'error: {code: INTERNAL_ERROR, message: "Internal error"}
    };

    JsonRpcMessage r1 = resultResponse;
    JsonRpcMessage r2 = errorResponse;
    test:assertTrue(r1 is JsonRpcResponse);
    test:assertTrue(r2 is JsonRpcError);
    test:assertEquals(errorResponse.'error.code, -32603);
}
