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

# Configuration options for initializing an MCP listener.
public type ListenerConfiguration record {|
    *http:ListenerConfiguration;
|};

# A server listener for handling MCP service requests.
public isolated class Listener {
    private http:Listener httpListener;
    private DispatcherService[] dispatcherServices = [];

    # Initializes the Listener.
    #
    # + listenTo - Either a port number (int) or an existing http:Listener.
    # + config - Listener configuration.
    # + return - Error? if listener initialization fails.
    public function init(int|http:Listener listenTo, *ListenerConfiguration config) returns Error? {
        if listenTo is http:Listener {
            self.httpListener = listenTo;
        } else {
            http:Listener|error httpListener = new (listenTo, config);
            if httpListener is error {
                return error("Failed to initialize HTTP listener: " + httpListener.message());
            }
            self.httpListener = httpListener;
        }
    }

    # Attaches an MCP service to the listener under the specified path(s).
    #
    # + mcpService - Service to attach.
    # + name - Path(s) to mount the service on (string or string array).
    # + return - Error? if attachment fails.
    public isolated function attach(Service|AdvancedService mcpService, string[]|string? name = ()) returns Error? {
        DispatcherService dispatcherService = new ();
        check addMcpServiceToDispatcher(dispatcherService, mcpService);
        lock {
            error? result = self.httpListener.attach(dispatcherService, name.cloneReadOnly());
            if result is error {
                return error("Failed to attach MCP service: " + result.message());
            }
            self.dispatcherServices.push(dispatcherService);
        }
    }

    # Detaches the MCP service from the listener.
    #
    # + mcpService - Service to detach.
    # + return - Error? if detachment fails.
    public isolated function detach(Service|AdvancedService mcpService) returns Error? {
        lock {
            foreach [int, DispatcherService] [index, dispatcherService] in self.dispatcherServices.enumerate() {
                Service|AdvancedService|Error attachedService = getMcpServiceFromDispatcher(dispatcherService);
                if attachedService === mcpService {
                    error? result = self.httpListener.detach(dispatcherService);
                    if result is error {
                        return error("Failed to detach MCP service: " + result.message());
                    }
                    _ = self.dispatcherServices.remove(index);
                    break;
                }
            }
        }
    }

    # Starts the listener (begin accepting connections).
    #
    # + return - Error? if starting fails.
    public isolated function 'start() returns Error? {
        lock {
            error? result = self.httpListener.start();
            if result is error {
                return error("Failed to start MCP listener: " + result.message());
            }
        }
    }

    # Gracefully stops the listener (completes active requests before shutting down).
    #
    # + return - Error? if graceful stop fails.
    public isolated function gracefulStop() returns Error? {
        lock {
            error? result = self.httpListener.gracefulStop();
            if result is error {
                return error("Failed to gracefully stop MCP listener: " + result.message());
            }
        }
    }

    # Immediately stops the listener (terminates all connections).
    #
    # + return - Error? if immediate stop fails.
    public isolated function immediateStop() returns Error? {
        lock {
            error? result = self.httpListener.immediateStop();
            if result is error {
                return error("Failed to immediately stop MCP listener: " + result.message());
            }
        }
    }
}
