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

type AttachedService record {|
    DispatcherService dispatcherService;
    # Path of the service's protected resource metadata, when the service uses an `mcp:OAuthProtectedResourceConfig`
    string? metadataPath;
|};

# A Streamable HTTP transport listener for handling MCP service requests.
public isolated class StreamableHttpListener {
    private http:Listener httpListener;
    private AttachedService[] attachedServices = [];
    private final ProtectedResourceMetadataRegistry metadataRegistry = new;
    private boolean metadataServiceAttached = false;

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
    public isolated function attach(StreamableHttpService|StreamableHttpAdvancedService mcpService,
            string[]|string? name = ()) returns Error? {
        StreamableHttpConfiguration serviceConfig = getServiceConfiguration(mcpService);
        if serviceConfig.protocolMode == "modern" && requiresLegacySession(mcpService) {
            return error DispatcherError("Modern MCP services cannot require mcp:HttpSession; use explicit application state");
        }
        CacheHints cacheHints = serviceConfig.cacheHints;
        if (cacheHints.discover?.ttlMs ?: 0) < 0 || (cacheHints.listTools?.ttlMs ?: 0) < 0 {
            return error DispatcherError("Cache hint ttlMs must be non-negative");
        }
        ServerAuthenticator? authenticator = check createServerAuthenticator(mcpService, serviceConfig);
        http:HttpServiceConfig httpServiceConfig = toHttpServiceConfig(serviceConfig, authenticator);
        final DispatcherService dispatcherService = getDispatcherService(httpServiceConfig, authenticator);
        check addMcpServiceToDispatcher(dispatcherService, mcpService);
        lock {
            string? metadataPath = authenticator is ServerAuthenticator ? authenticator.getMetadataPath() : ();
            if authenticator is ServerAuthenticator && metadataPath is string {
                check self.metadataRegistry.add(metadataPath, authenticator.getMetadata());
                error? metadataResult = self.attachMetadataService();
                if metadataResult is error {
                    self.metadataRegistry.remove(metadataPath);
                    return error("Failed to publish protected resource metadata: " + metadataResult.message());
                }
            }
            error? result = self.httpListener.attach(dispatcherService, name.cloneReadOnly());
            if result is error {
                if metadataPath is string {
                    self.metadataRegistry.remove(metadataPath);
                }
                return error("Failed to attach MCP service: " + result.message());
            }
            self.attachedServices.push({dispatcherService, metadataPath});
        }
    }

    # Detaches the MCP service from the listener.
    #
    # + mcpService - Service to detach.
    # + return - Error? if detachment fails.
    public isolated function detach(StreamableHttpService|StreamableHttpAdvancedService mcpService) returns Error? {
        lock {
            foreach [int, AttachedService] [index, attachedService] in self.attachedServices.enumerate() {
                StreamableHttpService|StreamableHttpAdvancedService|Error attachedMcpService =
                        getMcpServiceFromDispatcher(attachedService.dispatcherService);
                if attachedMcpService === mcpService {
                    error? result = self.httpListener.detach(attachedService.dispatcherService);
                    if result is error {
                        return error("Failed to detach MCP service: " + result.message());
                    }
                    string? metadataPath = attachedService.metadataPath;
                    if metadataPath is string {
                        self.metadataRegistry.remove(metadataPath);
                    }
                    _ = self.attachedServices.remove(index);
                    break;
                }
            }
        }
    }

    // The metadata of every protected service on this listener is served by one well-known
    // service, attached together with the first protected service.
    private isolated function attachMetadataService() returns error? {
        lock {
            if self.metadataServiceAttached {
                return;
            }
            check self.httpListener.attach(createProtectedResourceMetadataService(self.metadataRegistry),
                    PROTECTED_RESOURCE_METADATA_PATH);
            self.metadataServiceAttached = true;
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

isolated function createServerAuthenticator(StreamableHttpService|StreamableHttpAdvancedService mcpService,
        StreamableHttpConfiguration serviceConfig) returns ServerAuthenticator|Error? {
    readonly & map<string[]> toolScopes = getToolScopes(mcpService);
    OAuthProtectedResourceConfig|http:ListenerAuthConfig[]? authConfig = serviceConfig.httpConfig.auth;
    if authConfig is OAuthProtectedResourceConfig {
        // Protected resource metadata is published per listener and path, not per virtual host, so
        // services on different hosts could not each publish their own.
        if serviceConfig.httpConfig.host != DEFAULT_HTTP_SERVICE_HOST {
            return error DispatcherError(
                "'httpConfig.host' cannot be combined with an 'mcp:OAuthProtectedResourceConfig'");
        }
        return new ServerAuthenticator(authConfig.cloneReadOnly(), toolScopes);
    }
    // Fail closed rather than serve tools whose declared scopes nothing enforces.
    if toolScopes.length() > 0 {
        return error DispatcherError("Tools declare scopes with '@mcp:Tool', which requires an " +
            "'mcp:OAuthProtectedResourceConfig' in 'httpConfig.auth' to enforce them");
    }
    if requiresAuthContext(mcpService) {
        return error DispatcherError("A non-nilable 'mcp:AuthContext' parameter requires an " +
            "'mcp:OAuthProtectedResourceConfig' in 'httpConfig.auth'; declare it as 'mcp:AuthContext?' otherwise");
    }
    return;
}

// Builds the HTTP configuration of the dispatcher that serves an MCP service. Plain HTTP
// listener authentication is handed to the HTTP module; MCP authorization is enforced by the
// service's authenticator, so the HTTP module is given no authentication settings for it.
isolated function toHttpServiceConfig(StreamableHttpConfiguration serviceConfig, ServerAuthenticator? authenticator)
        returns http:HttpServiceConfig {
    // Every setting carries over except `auth`, which is wider than the HTTP module's.
    HttpServiceConfig {auth: authConfig, ...settings} = serviceConfig.httpConfig;
    http:HttpServiceConfig httpServiceConfig = {...settings};
    string[] exposedHeaders = httpServiceConfig.cors.exposeHeaders;
    if authenticator is ServerAuthenticator && exposedHeaders.indexOf(WWW_AUTHENTICATE_HEADER) is () {
        // Browser-based clients read the challenge to discover the authorization server.
        http:CorsConfig cors = {...httpServiceConfig.cors};
        cors.exposeHeaders = [...exposedHeaders, WWW_AUTHENTICATE_HEADER];
        httpServiceConfig.cors = cors;
    }
    if authConfig is http:ListenerAuthConfig[] {
        httpServiceConfig.auth = authConfig;
    }
    return httpServiceConfig;
}
