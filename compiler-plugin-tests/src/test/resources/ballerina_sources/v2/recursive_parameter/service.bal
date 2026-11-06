// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

type TreeNode record {|
    string name;
    TreeNode[] children;
|};

// A recursive record has no generated input schema, so the tool must supply one.
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9336) {
    remote isolated function count(TreeNode node) returns int => node.children.length();

    @mcp:Tool {
        schema: {
            "type": "object",
            "properties": {"node": {"$ref": "#/$defs/TreeNode"}},
            "required": ["node"],
            "$defs": {
                "TreeNode": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "children": {"type": "array", "items": {"$ref": "#/$defs/TreeNode"}}
                    },
                    "required": ["name", "children"],
                    "additionalProperties": false
                }
            }
        }
    }
    remote isolated function countWithSchema(TreeNode node) returns int => node.children.length();
}
