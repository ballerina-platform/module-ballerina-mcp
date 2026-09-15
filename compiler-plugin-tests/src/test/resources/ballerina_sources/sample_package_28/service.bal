// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9328) {
    remote isolated function invalidName(
            @mcp:Argument {headerName: "Bad Header"} string value) returns string => value;
}
