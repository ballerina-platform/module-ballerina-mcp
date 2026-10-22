// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9341) {
    remote isolated function twoSessions(mcp:Session first, string label, mcp:Session? second)
            returns string => string `${label}:${first.getSessionId()}`;
}
