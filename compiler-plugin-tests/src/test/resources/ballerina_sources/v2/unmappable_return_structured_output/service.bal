// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9335) {
    @mcp:Tool {structuredOutput: true}
    remote isolated function retAny() returns any => "x";
}
