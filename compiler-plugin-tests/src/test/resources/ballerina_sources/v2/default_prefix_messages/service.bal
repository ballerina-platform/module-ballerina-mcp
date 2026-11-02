// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2;

// Diagnostics name v2 types with the document's default prefix, `v2`.
service v2:StreamableHttpService /basic on new v2:StreamableHttpListener(9361) {
    remote isolated function twoSessions(v2:HttpSession first, string label, v2:HttpSession? second)
            returns string => string `${label}:${first.getSessionId()}`;

    remote isolated function requiredMeta(v2:RequestMeta meta) returns string => "x";
}

service v2:StreamableHttpAdvancedService /advanced on new v2:StreamableHttpListener(9362) {
    remote function onListTools() returns v2:ListToolsResult|v2:ServerError {
        return {tools: []};
    }

    remote function onCallTool(v2:CallToolParams params) returns string {
        return "x";
    }
}
