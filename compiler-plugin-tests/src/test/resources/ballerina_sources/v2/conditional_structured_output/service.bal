// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

const boolean LEGACY = true;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9343) {
    // The policy is false, although its first token is a constant whose value is true.
    @mcp:Tool {structuredOutput: LEGACY ? false : true}
    remote isolated function anyValue() returns any => 42;
}
