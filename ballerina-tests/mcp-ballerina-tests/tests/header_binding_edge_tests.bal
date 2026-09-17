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

// A nilable field binds to nil when the header is absent; an optional field is left out entirely.
type NilableFieldHeaders record {|
    string authorization;
    @http:Header {name: "X-Tenant-Id"}
    string? tenantId;
|};

type RequiredFieldHeaders record {|
    @http:Header {name: "X-Required"}
    string required;
|};

type ReadonlyHeaders readonly & record {|
    string authorization;
    int retries;
|};

@mcp:StreamableHttpConfig {
    info: {name: "header-binding-edge-test-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
isolated service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(8783) {

    @mcp:Tool {description: "Binds fractional header types"}
    isolated remote function readFractions(@http:Header {name: "X-Ratio"} float ratio,
            @http:Header {name: "X-Amount"} decimal amount) returns string {
        return ratio.toString() + ":" + amount.toString();
    }

    @mcp:Tool {description: "Binds a record whose field is nilable rather than optional"}
    isolated remote function readNilableField(@http:Header NilableFieldHeaders hdrs) returns string {
        return hdrs.authorization + ":" + (hdrs.tenantId ?: "<nil>");
    }

    @mcp:Tool {description: "Binds a nilable record of headers"}
    isolated remote function readNilableRecord(@http:Header RequiredFieldHeaders? hdrs) returns string {
        return hdrs is () ? "<no-record>" : hdrs.required;
    }

    @mcp:Tool {description: "Binds a record whose required header may be missing"}
    isolated remote function readRequiredRecord(@http:Header RequiredFieldHeaders hdrs) returns string {
        return hdrs.required;
    }

    @mcp:Tool {description: "Binds a readonly record of headers"}
    isolated remote function readReadonlyRecord(@http:Header ReadonlyHeaders hdrs) returns string {
        return hdrs.authorization + ":" + hdrs.retries.toString();
    }

    @mcp:Tool {description: "Binds a nilable readonly header array"}
    isolated remote function readNilableTags(@http:Header {name: "X-Tag"} (readonly & string[])? tags)
            returns string {
        return tags is () ? "<none>" : string:'join(",", ...tags);
    }

    @mcp:Tool {description: "Receives the request metadata of the tool call"}
    isolated remote function readMeta(mcp:RequestMetaObject? meta) returns string {
        return meta is () ? "<no-meta>" : (meta.progressToken ?: "<no-token>").toString();
    }
}

final mcp:StreamableHttpClient edgeHeaderClient = check new ("http://localhost:8783/mcp");
final http:Client rawEdgeHeaderClient = check new ("http://localhost:8783");

@test:Config
function testEdgeHeaderBindingClientInit() returns error? {
    _ = check edgeHeaderClient->connect({name: "edge-header-test-client", version: "1.0.0"});
}

@test:Config {dependsOn: [testEdgeHeaderBindingClientInit]}
function testFractionalHeaderTypesAreConverted() returns error? {
    mcp:CallToolResult result = check edgeHeaderClient->callTool({name: "readFractions"},
        {"X-Ratio": "0.25", "X-Amount": "10.50"});
    test:assertEquals(check getTextResult(result), "0.25:10.50");
}

@test:Config {dependsOn: [testEdgeHeaderBindingClientInit]}
function testFractionalHeaderConversionFailure() returns error? {
    json payload = check rawCallTool(rawEdgeHeaderClient, "readFractions",
        {"X-Ratio": "not-a-number", "X-Amount": "1.0"});
    string message = check getRawErrorMessage(payload);
    test:assertTrue(message.includes("header binding failed for parameter 'X-Ratio'"),
        msg = "unexpected error: " + message);
}

@test:Config {dependsOn: [testEdgeHeaderBindingClientInit]}
function testNilableRecordFieldBindsToNilWhenAbsent() returns error? {
    mcp:CallToolResult present = check edgeHeaderClient->callTool({name: "readNilableField"},
        {"authorization": "Bearer token", "X-Tenant-Id": "acme"});
    test:assertEquals(check getTextResult(present), "Bearer token:acme");

    mcp:CallToolResult absent = check edgeHeaderClient->callTool({name: "readNilableField"},
        {"authorization": "Bearer token"});
    test:assertEquals(check getTextResult(absent), "Bearer token:<nil>");
}

@test:Config {dependsOn: [testEdgeHeaderBindingClientInit]}
function testNilableRecordBindsToNilWhenRequiredHeaderIsMissing() returns error? {
    mcp:CallToolResult absent = check edgeHeaderClient->callTool({name: "readNilableRecord"});
    test:assertEquals(check getTextResult(absent), "<no-record>");

    mcp:CallToolResult present = check edgeHeaderClient->callTool({name: "readNilableRecord"},
        {"X-Required": "value"});
    test:assertEquals(check getTextResult(present), "value");
}

@test:Config {dependsOn: [testEdgeHeaderBindingClientInit]}
function testRequiredRecordHeaderIsReported() returns error? {
    json payload = check rawCallTool(rawEdgeHeaderClient, "readRequiredRecord", {});
    string message = check getRawErrorMessage(payload);
    test:assertTrue(message.includes("no header value found for 'X-Required'"),
        msg = "unexpected error: " + message);
}

@test:Config {dependsOn: [testEdgeHeaderBindingClientInit]}
function testReadonlyRecordOfHeaders() returns error? {
    mcp:CallToolResult result = check edgeHeaderClient->callTool({name: "readReadonlyRecord"},
        {"authorization": "Bearer token", "retries": "3"});
    test:assertEquals(check getTextResult(result), "Bearer token:3");
}

@test:Config {dependsOn: [testEdgeHeaderBindingClientInit]}
function testNilableReadonlyHeaderArray() returns error? {
    mcp:CallToolResult absent = check edgeHeaderClient->callTool({name: "readNilableTags"});
    test:assertEquals(check getTextResult(absent), "<none>");

    json payload = check rawCallTool(rawEdgeHeaderClient, "readNilableTags", {"X-Tag": ["a", "b"]});
    test:assertEquals(check getRawTextResult(payload), "a,b");
}

@test:Config {dependsOn: [testEdgeHeaderBindingClientInit]}
function testRequestMetadataParameterBinding() returns error? {
    mcp:CallToolResult withToken = check edgeHeaderClient->callTool({
        name: "readMeta",
        _meta: {progressToken: "token-1"}
    });
    test:assertEquals(check getTextResult(withToken), "token-1");

    mcp:CallToolResult withoutMeta = check edgeHeaderClient->callTool({name: "readMeta"});
    test:assertEquals(check getTextResult(withoutMeta), "<no-meta>");
}
