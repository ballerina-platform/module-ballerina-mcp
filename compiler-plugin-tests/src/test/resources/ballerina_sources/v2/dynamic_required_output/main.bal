// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;

public function main() returns error? {
    mcp:StreamableHttpService dynamicService = service object {
        @mcp:Tool {schema: {'type: "object"}, structuredOutput: true}
        remote isolated function anyValue() returns any => 42;
    };
    mcp:StreamableHttpListener policyListener = check new (9399);
    check policyListener.attach(dynamicService, "/mcp");
}

service class RequiredService {
    *mcp:StreamableHttpService;

    @mcp:Tool {schema: {'type: "object"}, structuredOutput: true}
    remote isolated function anyValue() returns any => 42;
}

function createRequiredService() returns mcp:StreamableHttpService {
    return service object {
        @mcp:Tool {schema: {'type: "object"}, structuredOutput: true}
        remote isolated function anyValue() returns any => 42;
    };
}
