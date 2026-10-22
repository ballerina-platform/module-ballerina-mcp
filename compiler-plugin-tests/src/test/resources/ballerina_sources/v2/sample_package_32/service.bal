// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

type Confirmation record {|
    boolean confirmed;
|};

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9332) {
    remote isolated function deleteFile(string path, mcp:Context context) returns string|mcp:InputRequiredResult {
        Confirmation? confirmation = context.acceptedContent("confirm");
        if confirmation is () {
            return {
                inputRequests: {
                    "confirm": mcp:elicitForm(string `Delete ${path}?`,
                            {properties: {confirmed: {'type: "boolean"}}, required: ["confirmed"]})
                }
            };
        }
        return confirmation.confirmed ? "deleted" : "kept";
    }
}
