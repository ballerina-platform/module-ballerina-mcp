// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/test;

@test:Config {}
function testDefaultStructuredOutputPolicyIsAutomatic() {
    McpToolConfig inlineConfig = {};
    McpToolConfig copiedConfig = {...inlineConfig};
    test:assertEquals(inlineConfig.structuredOutput, ());
    test:assertEquals(copiedConfig.structuredOutput, ());
}

@test:Config {}
function testRequiredStructuredOutputFailsBeforeAttachment() returns error? {
    StreamableHttpService invalidService = service object {
        @Tool {description: "Requires a schema", schema: {'type: "object"}, structuredOutput: true}
        remote isolated function anyValue() returns any => 42;
    };
    StreamableHttpListener policyListener = check new (9391);
    Error? attachmentError = policyListener.attach(invalidService, "/policy");
    test:assertTrue(attachmentError is ServerError);
    if attachmentError is ServerError {
        test:assertTrue(attachmentError.message().includes("anyValue"));
        test:assertTrue(attachmentError.message().includes("output schema"));
    }
    StreamableHttpService validService = service object {
        @Tool {description: "Automatic output", schema: {'type: "object"}}
        remote isolated function anyValue() returns any => 42;
    };
    check policyListener.attach(validService, "/policy");
    check policyListener.immediateStop();
}

@test:Config {}
function testDisabledStructuredOutputRejectsSuppliedSchema() returns error? {
    StreamableHttpService conflictingService = service object {
        @Tool {description: "Conflicting output", schema: {'type: "object"},
            outputSchema: {"type": "integer"}, structuredOutput: false}
        remote isolated function numberValue() returns int => 42;
    };
    StreamableHttpListener policyListener = check new (9394);
    Error? attachmentError = policyListener.attach(conflictingService, "/policy");
    test:assertTrue(attachmentError is ServerError);
    if attachmentError is ServerError {
        test:assertTrue(attachmentError.message().includes("numberValue"));
        test:assertTrue(attachmentError.message().includes("structuredOutput: false"));
    }
    check policyListener.immediateStop();
}
