// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp;

service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9340) {
    remote isolated function sessionInMiddle(string label, mcp:Session session, int count) returns string =>
        string `${label}:${session.getSessionId()}:${count}`;

    remote isolated function sessionLast(string label, mcp:Session? session) returns string =>
        string `${label}:${session is () ? "" : session.getSessionId()}`;
}
