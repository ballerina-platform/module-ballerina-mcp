// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

final record {| boolean structuredOutput; |} unstructured = {structuredOutput: false};

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9337) {
    # Returns the item.
    # Reads it from the store.
    @mcp:Tool {...unstructured}
    remote isolated function getItem(string id) returns string => id;
}
