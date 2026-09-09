// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/mcp;
import ballerina/test;

const int CONFIGURED_LIMIT = 7;

type Opts record {|
    boolean verbose = false;
|};

isolated int callCount = 0;

isolated function nextCallCount() returns int {
    lock {
        callCount += 1;
        return callCount;
    }
}

@mcp:StreamableHttpServiceConfig {
    info: {name: "parameter-default-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(8783) {

    @mcp:Tool {description: "Echoes a city and a defaultable unit"}
    isolated remote function withDefaultableString(string city, string unit = "celsius") returns string {
        return string `city=${city} unit=${unit}`;
    }

    @mcp:Tool {description: "Echoes a defaultable int"}
    isolated remote function withDefaultableInt(int maxCount = 10) returns string {
        return string `maxCount=${maxCount}`;
    }

    @mcp:Tool {description: "Echoes a nilable defaultable int"}
    isolated remote function withNilableDefaultable(int? maxCount = 6) returns string {
        return maxCount is () ? "maxCount=()" : string `maxCount=${maxCount}`;
    }

    @mcp:Tool {description: "Echoes defaultable structured values"}
    isolated remote function withStructuredDefaults(Opts opts = {verbose: true}, string[] tags = ["a"])
            returns string {
        return string `verbose=${opts.verbose} tags=${tags.toString()}`;
    }

    @mcp:Tool {description: "Defaults from a module-level constant"}
    isolated remote function withConstDefault(int maxCount = CONFIGURED_LIMIT) returns string {
        return string `maxCount=${maxCount}`;
    }

    @mcp:Tool {description: "Default derived from a preceding argument"}
    isolated remote function withDerivedDefault(int a, int b = a + 1) returns string {
        return string `a=${a} b=${b}`;
    }

    @mcp:Tool {description: "Chained defaults derived from preceding arguments"}
    isolated remote function withChainedDefaults(int a, int b = a * 2, int c = a + b) returns string {
        return string `a=${a} b=${b} c=${c}`;
    }

    @mcp:Tool {description: "Default is evaluated by calling a function"}
    isolated remote function withCalledDefault(int n = nextCallCount()) returns string {
        return string `n=${n}`;
    }

    @mcp:Tool {description: "Defaultable parameter followed by an injected meta"}
    isolated remote function withDefaultBeforeMeta(string city, string unit = "celsius",
            mcp:Meta? meta = ()) returns string {
        return string `city=${city} unit=${unit} meta=${meta is () ? "()" : "present"}`;
    }
}

final http:Client parameterDefaultClient = check new ("http://localhost:8783");

@test:Config
function testOmittedDefaultableStringUsesDeclaredDefault() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withDefaultableString", {city: "Colombo"});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "city=Colombo unit=celsius");
}

@test:Config
function testSuppliedDefaultableStringOverridesDefault() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withDefaultableString",
            {city: "Colombo", unit: "fahrenheit"});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "city=Colombo unit=fahrenheit");
}

@test:Config
function testOmittedDefaultableIntUsesDeclaredDefault() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withDefaultableInt");
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "maxCount=10");
}

@test:Config
function testNullForDefaultableNonNilableParameterIsRejected() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withDefaultableInt", {maxCount: ()});
    test:assertEquals(response.statusCode, http:STATUS_OK);
    [boolean, string] [isError, message] = check getToolError(check response.getJsonPayload());
    test:assertTrue(isError);
    test:assertEquals(message, "invalid value for argument 'maxCount': expected a value, found null");
}

@test:Config
function testOmittedNilableDefaultableUsesDeclaredDefault() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withNilableDefaultable");
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "maxCount=6");
}

@test:Config
function testNullForNilableDefaultableBindsNil() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withNilableDefaultable", {maxCount: ()});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "maxCount=()");
}

@test:Config
function testOmittedStructuredDefaultsUseDeclaredDefaults() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withStructuredDefaults");
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "verbose=true tags=[\"a\"]");
}

@test:Config
function testOmittedConstDefaultUsesConstantValue() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withConstDefault");
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "maxCount=7");
}

@test:Config
function testDefaultDerivedFromPrecedingArgument() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withDerivedDefault", {a: 10});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "a=10 b=11");
}

@test:Config
function testOmittedMiddleDefaultWithSuppliedLaterArgument() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withChainedDefaults", {a: 3, c: 50});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "a=3 b=6 c=50");
}

@test:Config
function testChainedDefaultsUseSuppliedIntermediateArgument() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withChainedDefaults", {a: 3, b: 100});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "a=3 b=100 c=103");
}

@test:Config
function testCalledDefaultIsEvaluatedPerCall() returns error? {
    http:Response first = check callTool(parameterDefaultClient, "withCalledDefault");
    http:Response second = check callTool(parameterDefaultClient, "withCalledDefault");
    string firstText = check getRawTextResult(check first.getJsonPayload());
    string secondText = check getRawTextResult(check second.getJsonPayload());
    test:assertNotEquals(firstText, secondText,
            msg = "a default expression must be re-evaluated on every call that omits the argument");
}

@test:Config
function testSuppliedArgumentSkipsDefaultEvaluation() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withCalledDefault", {n: 99});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()), "n=99");
}

@test:Config
function testDefaultableParameterBeforeInjectedMeta() returns error? {
    http:Response response = check callTool(parameterDefaultClient, "withDefaultBeforeMeta", {city: "Colombo"});
    test:assertEquals(check getRawTextResult(check response.getJsonPayload()),
            "city=Colombo unit=celsius meta=()");
}
