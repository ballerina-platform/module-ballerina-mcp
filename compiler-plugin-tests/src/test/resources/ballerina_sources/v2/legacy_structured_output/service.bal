// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

@mcp:StreamableHttpServiceConfig {info: {name: "legacy", version: "1"}, protocolMode: "legacy"}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9392) {
    @mcp:Tool {structuredOutput: true}
    remote isolated function anyValue() returns any => 42;
}
