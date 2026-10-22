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

enum ApiVersion {
    V1 = "v1",
    V2 = "v2"
}

type CallerHeaders record {|
    string authorization;
    @http:Header {name: "X-Tenant-Id"}
    string tenantId?;
    string[] accept?;
|};

// Every supported @http:Header parameter shape must compile without diagnostics on an
// mcp:StreamableHttpService.
@mcp:StreamableHttpServiceConfig {
    info: {name: "sample-1", version: "1.0.0"}
}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9301) {

    @mcp:Tool {description: "single header bound by parameter name"}
    remote function tString(@http:Header string authorization, string name) returns string {
        return name + authorization;
    }

    @mcp:Tool {description: "named nilable header"}
    remote function tNamedNilable(@http:Header {name: "X-Tenant-Id"} string? tenant) returns string {
        return tenant ?: "<none>";
    }

    @mcp:Tool {description: "basic typed headers and arrays"}
    remote function tTyped(@http:Header {name: "X-Retry-Count"} int retries,
            @http:Header {name: "X-Debug"} boolean debug,
            @http:Header {name: "X-Rate"} decimal? rate,
            @http:Header {name: "X-Factor"} float factor,
            @http:Header {name: "X-Shard"} int[]? shards) returns string {
        return string `${retries}:${debug}:${rate ?: 0d}:${factor}:${(shards ?: []).length()}`;
    }

    @mcp:Tool {description: "enum and finite string headers"}
    remote function tFinite(@http:Header {name: "X-Ver"} ApiVersion ver,
            @http:Header {name: "X-Ver2"} ApiVersion? maybeVer,
            @http:Header {name: "X-Mode"} "fast"|"slow" mode) returns string {
        return string `${ver}:${maybeVer ?: ""}:${mode}`;
    }

    @mcp:Tool {description: "readonly intersection headers"}
    remote function tReadonly(@http:Header {name: "X-Tag"} readonly & string[] tags,
            @http:Header readonly & CallerHeaders hdrs) returns string {
        return hdrs.authorization + tags.length().toString();
    }

    @mcp:Tool {description: "record binding alongside the raw headers object"}
    remote function tRecord(@http:Header CallerHeaders hdrs, http:Headers rawHeaders) returns string {
        return hdrs.authorization;
    }

    @mcp:Tool {description: "raw request object alongside a tool argument"}
    remote function tRequest(http:Request request, string name) returns string {
        return name;
    }
}
