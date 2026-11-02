// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcpv2;

// Diagnostics name v2 types with the document's own prefix, `mcpv2`.
service mcpv2:StreamableHttpService /basic on new mcpv2:StreamableHttpListener(9351) {
    remote isolated function twoSessions(mcpv2:HttpSession first, string label, mcpv2:HttpSession? second)
            returns string => string `${label}:${first.getSessionId()}`;

    remote isolated function requiredMeta(mcpv2:RequestMeta meta) returns string => "x";
}

service mcpv2:StreamableHttpAdvancedService /advanced on new mcpv2:StreamableHttpListener(9352) {
    remote function onListTools() returns mcpv2:ListToolsResult|mcpv2:ServerError {
        return {tools: []};
    }

    remote function onCallTool(mcpv2:CallToolParams params) returns string {
        return "x";
    }
}
