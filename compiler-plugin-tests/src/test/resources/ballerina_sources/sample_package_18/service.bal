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

import ballerina/mcp;

@mcp:ServiceConfig {
    info: {name: "sample-18", version: "1.0.0"}
}
service mcp:Service /mcp on new mcp:StreamableHttpListener(9318) {

    @mcp:Tool {description: "metadata can be injected between tool arguments"}
    remote function metaInMiddle(string name, mcp:Meta? meta, string greeting) returns string {
        if meta is mcp:Meta {
            return string `${greeting}, ${name}!`;
        }
        return string `${greeting}, ${name}! no-meta`;
    }
}
