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

// Header parameters must be string/int/float/decimal/boolean based (MCP_108).
@mcp:StreamableHttpServiceConfig {
    info: {name: "sample-5", version: "1.0.0"}
}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9305) {

    @mcp:Tool {description: "xml is not a valid header param type"}
    remote function badXml(@http:Header xml payload) returns string {
        return payload.toString();
    }
}
