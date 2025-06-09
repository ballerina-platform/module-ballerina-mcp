// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
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

public type ServerOptions record {|
    *ProtocolOptions;
    ServerCapabilities capabilities?;
    string instructions?;
|};

# A server listener for handling MCP service requests.
public class Listener {
    private http:Listener httpListener;
    private DispatcherService dispatcherService;

    # Initializes the Listener.
    # 
    # + listenTo - Either a port number (int) or an existing http:Listener.
    # + config - Optional listener configuration.
    # + return - error? if listener initialization fails.
    public function init(int|http:Listener listenTo, ServerConfiguration serverConfigs, *ListenerConfiguration config) returns error? {
        if listenTo is http:Listener {
            self.httpListener = listenTo;
        } else {          
            self.httpListener = check new (listenTo, config);
        }
        self.dispatcherService = dispatcherService;
        self.dispatcherService.setServerConfigs(serverConfigs);
    }

    # Attaches an MCP service to the listener under the specified path(s).
    # 
    # + mcpService - Service to attach.
    # + name - Path(s) to mount the service on (string or string array).
    # + return - error? if attachment fails.
    public isolated function attach(McpService mcpService, string[]|string? name = ()) returns error? {
        check self.httpListener.attach(self.dispatcherService, name);
        self.dispatcherService.addServiceRef(mcpService);
    }

    # Detaches the MCP service from the listener.
    # 
    # + mcpService - Service to detach.
    # + return - error? if detachment fails.
    public isolated function detach(McpService mcpService) returns error? {
        check self.httpListener.detach(self.dispatcherService);
        self.dispatcherService.removeServiceRef();
    }

    # Starts the listener (begin accepting connections).
    # 
    # + return - error? if starting fails.
    public isolated function 'start() returns error? {
        check self.httpListener.start();
    }

    # Gracefully stops the listener (completes active requests before shutting down).
    # 
    # + return - error? if graceful stop fails.
    public isolated function gracefulStop() returns error? {
        check self.httpListener.gracefulStop();
    }

    # Immediately stops the listener (terminates all connections).
    # 
    # + return - error? if immediate stop fails.
    public isolated function immediateStop() returns error? {
        check self.httpListener.immediateStop();
    }
}
