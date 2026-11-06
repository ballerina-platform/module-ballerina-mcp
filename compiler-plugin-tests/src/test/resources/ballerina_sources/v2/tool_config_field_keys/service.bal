// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9339) {
    # Generated description
    @mcp:Tool {
        description: "Commented scopes",
        schema: {"type": "object", "properties": {"commented": {}}},
        // Admins only
        scopes: ["commented"]
    }
    remote isolated function commented() returns string => "";

    # Generated description
    @mcp:Tool {
        "description": "String scopes",
        "schema": {"type": "object", "properties": {"string": {}}},
        "scopes": ["string"]
    }
    remote isolated function stringKey() returns string => "";

    # Generated description
    @mcp:Tool {
        'description: "Quoted scopes",
        'schema: {"type": "object", "properties": {"quoted": {}}},
        'scopes: ["quoted"]
    }
    remote isolated function quotedKey() returns string => "";
}
