// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

const boolean REQUIRE_STRUCTURED = true;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9390) {
    @mcp:Tool {structuredOutput: REQUIRE_STRUCTURED}
    remote isolated function anyValue() returns any => 42;
}
