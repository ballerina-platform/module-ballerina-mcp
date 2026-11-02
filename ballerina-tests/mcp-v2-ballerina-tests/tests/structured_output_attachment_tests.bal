// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
// Licensed under the Apache License, Version 2.0.

import ballerina/mcp.v2 as mcpv2;
import ballerina/test;

// Capture attach results without failing module startup for deliberately invalid services.
listener PolicyProbeListener policyProbe = new;

class PolicyProbeListener {
    private map<boolean> outcomes = {};

    public function attach(mcpv2:StreamableHttpService serviceValue, string[]|string? name = ()) returns error? {
        mcpv2:StreamableHttpListener actualListener = check new (listenTo = 9394);
        mcpv2:Error? attachmentError = actualListener.attach(mcpService = serviceValue, name = name);
        check actualListener.immediateStop();
        string key = name is string[] ? string:'join("/", ...name) : name ?: "";
        lock {
            self.outcomes[key] = attachmentError is mcpv2:ServerError;
        }
    }

    public function result(string name) returns boolean? {
        lock {
            return self.outcomes[name];
        }
    }
    public function detach(mcpv2:StreamableHttpService serviceValue) returns error? {}
    public function 'start() returns error? {}
    public function gracefulStop() returns error? {}
    public function immediateStop() returns error? {}
}

function selectPolicyValue(boolean? policy) returns boolean? => policy;
function selectPolicyMode(mcpv2:ProtocolMode mode) returns mcpv2:ProtocolMode => mode;

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcpv2:StreamableHttpService /legacyAutomaticWithoutSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(())}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcpv2:StreamableHttpService /legacyAutomaticWithSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(()), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcpv2:StreamableHttpService /legacyRequiredWithoutSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true)}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcpv2:StreamableHttpService /legacyRequiredWithSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcpv2:StreamableHttpService /legacyDisabledWithoutSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false)}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("legacy")}
service mcpv2:StreamableHttpService /legacyDisabledWithSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcpv2:StreamableHttpService /autoAutomaticWithoutSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(())}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcpv2:StreamableHttpService /autoAutomaticWithSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(()), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcpv2:StreamableHttpService /autoRequiredWithoutSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true)}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcpv2:StreamableHttpService /autoRequiredWithSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcpv2:StreamableHttpService /autoDisabledWithoutSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false)}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("auto")}
service mcpv2:StreamableHttpService /autoDisabledWithSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcpv2:StreamableHttpService /modernAutomaticWithoutSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(())}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcpv2:StreamableHttpService /modernAutomaticWithSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(()), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcpv2:StreamableHttpService /modernRequiredWithoutSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true)}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcpv2:StreamableHttpService /modernRequiredWithSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(true), outputSchema: {"type": "integer"}}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcpv2:StreamableHttpService /modernDisabledWithoutSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
        structuredOutput: selectPolicyValue(false)}
    remote isolated function anyValue() returns any => 42;
}

@mcpv2:StreamableHttpServiceConfig {info: {name: "policy", version: "1"}, protocolMode: selectPolicyMode("modern")}
service mcpv2:StreamableHttpService /modernDisabledWithSchema on policyProbe {
    @mcpv2:Tool {description: "Runtime policy", schema: {'type: "object"},
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
