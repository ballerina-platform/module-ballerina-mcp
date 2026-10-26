// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/http;
import ballerina/mcp.v2 as mcp;

class Thing {
    string name = "x";
}

// Recursive records cannot be mapped to an output schema.
type TreeNode record {|
    string name;
    TreeNode[] children;
|};

// Return types with no JSON Schema leave a tool unstructured, as in the 1.x API, instead of failing the build.
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9334) {
    remote isolated function retAny() returns any => "x";

    remote isolated function retObject() returns Thing|error => new;

    remote isolated function retHttpResponse() returns http:Response => new;

    remote isolated function retStream() returns stream<int, error?> => [1].toStream();

    remote isolated function retTree() returns TreeNode => {name: "root", children: []};

    @mcp:Tool {description: "explicit schema", schema: {"type": "object"}}
    remote isolated function retAnnotatedAny() returns any => "x";

    remote isolated function retString() returns string|error => "x";
}
