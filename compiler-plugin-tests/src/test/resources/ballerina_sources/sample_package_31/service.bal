// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/http;
import ballerina/mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9331) {
    remote isolated function conflictingBindings(
            @http:Header @mcp:Argument {headerName: "Value"} string value) returns string => value;
}
