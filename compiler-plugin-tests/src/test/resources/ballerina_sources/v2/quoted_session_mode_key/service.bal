// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

@mcp:StreamableHttpServiceConfig {
    info: {name: "string-key", version: "1.0.0"},
    "sessionMode": mcp:STATELESS
}
service mcp:StreamableHttpService /string on new mcp:StreamableHttpListener(9341) {
    remote function stringKey(mcp:HttpSession session, string name) returns string => name;
}

@mcp:StreamableHttpServiceConfig {
    info: {name: "quoted-key", version: "1.0.0"},
    'sessionMode: mcp:STATELESS
}
service mcp:StreamableHttpService /quoted on new mcp:StreamableHttpListener(9342) {
    remote function quotedKey(mcp:HttpSession session, string name) returns string => name;
}
