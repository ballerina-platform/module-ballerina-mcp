// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9330) {
    @mcp:Tool {schema: {'type: "object", properties: {value: {'type: "string"}}}}
    remote isolated function explicitSchema(
            @mcp:Argument {headerName: "Value"} string value) returns string => value;
}
