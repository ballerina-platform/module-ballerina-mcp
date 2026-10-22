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

import ballerina/mcp as m;

@m:StreamableHttpServiceConfig {
    info: {name: "aliased", version: "1.0.0"},
    sessionMode: m:STATELESS
}
service m:StreamableHttpService /mcp on new m:StreamableHttpListener(9337) {
    # Uses a session in stateless mode.
    # + session - the session
    # + return - the session ID
    remote function id(m:Session session) returns string => session.getSessionId();
}
