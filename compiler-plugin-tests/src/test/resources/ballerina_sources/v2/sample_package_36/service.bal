// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9336) {
    # Uses "quotes" and \ slashes, and matches ^\w+$
    remote isolated function getItem(string id) returns string => id;

    # Reads C:\temp\items and matches ^\d+$
    @mcp:Tool {}
    remote isolated function listItems() returns string => "";
}
