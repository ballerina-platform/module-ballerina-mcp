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

// A raw http:Headers parameter is a transport-specific property and is not accessible in the
// transport-agnostic mcp:Service (MCP_109).
@mcp:ServiceConfig {
    info: {name: "sample-8", version: "1.0.0"}
}
service mcp:Service /mcp on new mcp:StreamableHttpListener(9308) {

    @mcp:Tool {description: "raw headers object on the transport-agnostic service"}
    remote function badRaw(http:Headers headers, string name) returns string {
        return name;
    }
}
