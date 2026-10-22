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

// sessionMode declared via the transport-specific @mcp:StreamableHttpServiceConfig annotation
// must be honored by the plugin: a Session parameter under STATELESS is an error (MCP_104).
@mcp:StreamableHttpServiceConfig {
    info: {name: "sample-7", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9307) {

    @mcp:Tool {description: "session param under stateless transport config"}
    remote function badSession(mcp:Session session, string name) returns string {
        return name;
    }
}
