// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

const boolean DISABLED_OUTPUT = false;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9395) {
    @mcp:Tool {structuredOutput: DISABLED_OUTPUT, outputSchema: {"type": "integer"}}
    remote isolated function numberValue() returns int => 42;
}
