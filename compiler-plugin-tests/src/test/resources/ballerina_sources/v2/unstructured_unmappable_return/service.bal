// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

// Recursive records cannot be mapped to an output schema.
type TreeNode record {|
    string name;
    TreeNode[] children;
|};

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9333) {
    @mcp:Tool {structuredOutput: false}
    remote isolated function tree() returns TreeNode => {name: "root", children: []};
}
