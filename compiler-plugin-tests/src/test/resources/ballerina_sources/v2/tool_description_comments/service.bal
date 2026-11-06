// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9340) {
    @mcp:Tool {
        description: "Lists the items" // trailing note
    }
    remote isolated function listItems() returns string => "";

    @mcp:Tool {
        description: "Finds " + // joined
            "items",
        scopes: ["read"]
    }
    remote isolated function findItems() returns string => "";

    # First line
    # Second line
    @mcp:Tool {}
    remote isolated function multiLine() returns string => "";
}
