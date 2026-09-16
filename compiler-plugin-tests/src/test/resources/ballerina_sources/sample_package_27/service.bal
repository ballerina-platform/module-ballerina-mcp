// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9327) {
    remote isolated function invalidType(
            @mcp:Argument {headerName: "Tags"} string[] tags) returns string => tags.toString();
}
