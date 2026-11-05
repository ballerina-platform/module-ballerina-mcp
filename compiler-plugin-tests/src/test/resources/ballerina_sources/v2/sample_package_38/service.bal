// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9338) {
    # Lists the items.
    # + 'limit - The maximum number of items
    remote isolated function listItems(int 'limit) returns int => 'limit;
}
