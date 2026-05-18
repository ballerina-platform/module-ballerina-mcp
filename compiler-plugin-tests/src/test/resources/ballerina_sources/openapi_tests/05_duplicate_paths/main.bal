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

listener mcp:Listener listenerOne = new (9097);
listener mcp:Listener listenerTwo = new (9098);

@mcp:ServiceConfig {
    info: {
        name: "Service One",
        version: "1.0.0"
    },
    sessionMode: mcp:STATELESS
}
service mcp:Service /api on listenerOne {
    @mcp:Tool
    remote function ping() returns string {
        return "pong";
    }
}

@mcp:ServiceConfig {
    info: {
        name: "Service Two",
        version: "1.0.0"
    },
    sessionMode: mcp:STATELESS
}
service mcp:Service /api on listenerTwo {
    @mcp:Tool
    remote function pong() returns string {
        return "ping";
    }
}
