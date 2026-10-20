// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9332) {
    @mcp:Tool {outputSchema: {'type: "string"}, structuredOutput: false}
    remote isolated function conflicting() returns string => "text";
}
