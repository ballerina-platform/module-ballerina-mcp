// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9342) {
    remote isolated function floatHeader(@mcp:Argument {headerName: "Confidence"} float confidence)
            returns string => confidence.toString();

    remote isolated function decimalHeader(@mcp:Argument {headerName: "Ratio"} decimal ratio)
            returns string => ratio.toString();
}
