// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

final mcp:StreamableHttpServiceConfiguration selectedConfig = {
    info: {name: "legacy", version: "1"}, protocolMode: "legacy"
};
final record {| mcp:OutputSchema outputSchema; |} suppliedConfig = {outputSchema: {"type": "integer"}};

@mcp:StreamableHttpServiceConfig {...selectedConfig}
service mcp:StreamableHttpService /legacy on new mcp:StreamableHttpListener(9397) {
    @mcp:Tool {structuredOutput: true}
    remote isolated function legacyValue() returns any => 42;
}

service mcp:StreamableHttpService /automatic on new mcp:StreamableHttpListener(9398) {
    @mcp:Tool {...suppliedConfig, ...{}, structuredOutput: true}
    remote isolated function suppliedValue() returns any => 42;
}

service mcp:StreamableHttpService /mappingEquality on new mcp:StreamableHttpListener(9395) {
    @mcp:Tool {structuredOutput: {} != {}}
    remote isolated function anyValue() returns any => 42;
}
