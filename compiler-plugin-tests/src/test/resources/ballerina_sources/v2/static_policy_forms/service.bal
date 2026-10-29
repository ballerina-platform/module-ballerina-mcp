// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

const POLICY_CONFIG = {structuredOutput: true};
const boolean DISABLED = false;
const boolean structuredOutput = true;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9396) {
    @mcp:Tool {...POLICY_CONFIG}
    remote isolated function spreadValue() returns any => 42;

    @mcp:Tool {structuredOutput: !DISABLED}
    remote isolated function expressionValue() returns any => 42;

    @mcp:Tool {structuredOutput}
    remote isolated function shorthandValue() returns any => 42;
}
