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

// Positional int port.
listener mcp:Listener positionalListener = new (9090);

// Named-arg `listenTo`.
listener mcp:Listener namedArgListener = new (listenTo = 9091);

// mcp:Listener wrapping an http:Listener variable.
listener http:Listener httpListenerForIndirection = new (9092);
listener mcp:Listener indirectionListener = new (httpListenerForIndirection);

// http:Listener with named `host` argument.
listener http:Listener httpListenerNamedHost = new (9093, host = "127.0.0.1");
listener mcp:Listener namedHostListener = new (httpListenerNamedHost);

// http:Listener with mapping-style config (host inside the record).
listener http:Listener httpListenerMappingHost = new (9094, {host: "127.0.0.2"});
listener mcp:Listener mappingHostListener = new (httpListenerMappingHost);

// mcp:Listener taking the default http:Listener.
listener mcp:Listener defaultHttpListener = new (check http:getDefaultListener());

@mcp:ServiceConfig {info: {name: "S", version: "1.0.0"}, sessionMode: mcp:STATELESS}
service mcp:Service /positional on positionalListener {
    @mcp:Tool remote function ping() returns string => "pong";
}

@mcp:ServiceConfig {info: {name: "S", version: "1.0.0"}, sessionMode: mcp:STATELESS}
service mcp:Service /named_arg on namedArgListener {
    @mcp:Tool remote function ping() returns string => "pong";
}

@mcp:ServiceConfig {info: {name: "S", version: "1.0.0"}, sessionMode: mcp:STATELESS}
service mcp:Service /indirection on indirectionListener {
    @mcp:Tool remote function ping() returns string => "pong";
}

@mcp:ServiceConfig {info: {name: "S", version: "1.0.0"}, sessionMode: mcp:STATELESS}
service mcp:Service /named_host on namedHostListener {
    @mcp:Tool remote function ping() returns string => "pong";
}

@mcp:ServiceConfig {info: {name: "S", version: "1.0.0"}, sessionMode: mcp:STATELESS}
service mcp:Service /mapping_host on mappingHostListener {
    @mcp:Tool remote function ping() returns string => "pong";
}

@mcp:ServiceConfig {info: {name: "S", version: "1.0.0"}, sessionMode: mcp:STATELESS}
service mcp:Service /default_listener on defaultHttpListener {
    @mcp:Tool remote function ping() returns string => "pong";
}
