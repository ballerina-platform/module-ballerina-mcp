// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcp;
import ballerina/test;

// Capture attach results without failing module startup for deliberately invalid services.
listener PolicyProbeListener policyProbe = new;

class PolicyProbeListener {
    private map<boolean> outcomes = {};

    public function attach(mcp:StreamableHttpService serviceValue, string[]|string? name = ()) returns error? {
        mcp:StreamableHttpListener actualListener = check new (listenTo = 9394);
        mcp:Error? attachmentError = actualListener.attach(mcpService = serviceValue, name = name);
        check actualListener.immediateStop();
        string key = name is string[] ? string:'join("/", ...name) : name ?: "";
        lock {
            self.outcomes[key] = attachmentError is mcp:ServerError;
        }
    }

    public function result(string name) returns boolean? {
        lock {
            return self.outcomes[name];
        }
    }
    public function detach(mcp:StreamableHttpService serviceValue) returns error? {}
    public function 'start() returns error? {}
    public function gracefulStop() returns error? {}
    public function immediateStop() returns error? {}
}

function selectPolicyValue(boolean? policy) returns boolean? => policy;
function selectPolicyMode(mcp:ProtocolMode mode) returns mcp:ProtocolMode => mode;

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcp:StreamableHttpService /legacyAutomaticWithoutSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(())}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcp:StreamableHttpService /legacyAutomaticWithSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(()), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcp:StreamableHttpService /legacyRequiredWithoutSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true)}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcp:StreamableHttpService /legacyRequiredWithSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcp:StreamableHttpService /legacyDisabledWithoutSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false)}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcp:StreamableHttpService /legacyDisabledWithSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcp:StreamableHttpService /autoAutomaticWithoutSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(())}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcp:StreamableHttpService /autoAutomaticWithSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(()), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcp:StreamableHttpService /autoRequiredWithoutSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true)}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcp:StreamableHttpService /autoRequiredWithSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcp:StreamableHttpService /autoDisabledWithoutSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false)}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcp:StreamableHttpService /autoDisabledWithSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcp:StreamableHttpService /modernAutomaticWithoutSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(())}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcp:StreamableHttpService /modernAutomaticWithSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(()), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcp:StreamableHttpService /modernRequiredWithoutSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true)}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcp:StreamableHttpService /modernRequiredWithSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcp:StreamableHttpService /modernDisabledWithoutSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false)}
    remote isolated function anyValue() returns any => 42;
}

@mcp:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcp:StreamableHttpService /modernDisabledWithSchema on policyProbe {
    @mcp:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@test:Config {}
function testRuntimePolicyValidationFollowsProtocolMode() {
    map<boolean> expectedFailures = {
        legacyAutomaticWithoutSchema: false,
        legacyAutomaticWithSchema: false,
        legacyRequiredWithoutSchema: false,
        legacyRequiredWithSchema: false,
        legacyDisabledWithoutSchema: false,
        legacyDisabledWithSchema: false,
        autoAutomaticWithoutSchema: false,
        autoAutomaticWithSchema: false,
        autoRequiredWithoutSchema: true,
        autoRequiredWithSchema: false,
        autoDisabledWithoutSchema: false,
        autoDisabledWithSchema: true,
        modernAutomaticWithoutSchema: false,
        modernAutomaticWithSchema: false,
        modernRequiredWithoutSchema: true,
        modernRequiredWithSchema: false,
        modernDisabledWithoutSchema: false,
        modernDisabledWithSchema: true
    };
    foreach var [name, expectedFailure] in expectedFailures.entries() {
        test:assertEquals(actual = policyProbe.result(name), expected = expectedFailure, msg = name);
    }
}
