// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9329) {
    remote isolated function duplicateNames(
            @mcp:Argument {headerName: "Region"} string first,
            @mcp:Argument {headerName: "region"} string second) returns string => first + second;
}
