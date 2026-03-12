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

import ballerina/auth;
import ballerina/http;
import ballerina/jwt;
import ballerina/log;
import ballerina/oauth2;

public isolated function authenticateResource(http:ListenerAuthConfig[] authConfig, string header) returns
        http:Unauthorized|http:Forbidden|string? {
    return tryAuthenticate(<http:ListenerAuthConfig[]>authConfig, header);
}

isolated function getServiceAuthConfig(http:Service serviceRef) returns http:ListenerAuthConfig[]? {
    typedesc<any> serviceTypeDesc = typeof serviceRef;
    var serviceAnnotation = serviceTypeDesc.@http:ServiceConfig;
    if serviceAnnotation is () {
        return;
    }
    http:HttpServiceConfig serviceConfig = <http:HttpServiceConfig>serviceAnnotation;
    return serviceConfig?.auth;
}

isolated function getListenerAuthConfig(http:ListenerAuthConfig[] serviceAuthConfig, string[] toolScope)
                                        returns http:ListenerAuthConfig[] {
    http:ListenerAuthConfig[]|error authConfig = serviceAuthConfig.cloneWithType();
    if authConfig is http:ListenerAuthConfig[] && toolScope.length() > 0 {
        foreach http:ListenerAuthConfig config in authConfig {
            config.scopes = toolScope;
        }
        return authConfig;
    }
    if authConfig is http:ListenerAuthConfig[] {
        return authConfig;
    }
    return [];
}

isolated function tryAuthenticate(http:ListenerAuthConfig[] authConfig, string header) returns http:Unauthorized|http:Forbidden|string? {
    string scheme = extractScheme(header);
    http:Unauthorized|http:Forbidden|string? authResult = <http:Unauthorized>{};
    foreach http:ListenerAuthConfig config in authConfig {
        if scheme is http:AUTH_SCHEME_BASIC {
            if config is http:FileUserStoreConfigWithScopes {
                authResult = authenticateWithFileUserStore(config, header);
            } else if config is http:LdapUserStoreConfigWithScopes {
                authResult = authenticateWithLdapUserStoreConfig(config, header);
            } else {
                log:printDebug("Invalid auth configurations for 'Basic' scheme.");
            }
        } else if scheme is http:AUTH_SCHEME_BEARER {
            if config is http:JwtValidatorConfigWithScopes {
                authResult = authenticateWithJwtValidatorConfig(config, header);
            } else if config is http:OAuth2IntrospectionConfigWithScopes {
                authResult = authenticateWithOAuth2IntrospectionConfig(config, header);
            } else {
                log:printDebug("Invalid auth configurations for 'Bearer' scheme.");
            }
        }
        if authResult is () || authResult is http:Forbidden {
            return authResult;
        }
    }
    return authResult;
}

// Extract the scheme from `string` header.
isolated function extractScheme(string header) returns string {
    return re `\s`.split(header)[0];
}

// Defines the listener authentication handlers.
type ListenerAuthHandler http:ListenerFileUserStoreBasicAuthHandler|http:ListenerLdapUserStoreBasicAuthHandler|
                        http:ListenerJwtAuthHandler|http:ListenerOAuth2Handler;

isolated map<ListenerAuthHandler> authHandlers = {};

isolated function authenticateWithFileUserStore(http:FileUserStoreConfigWithScopes config, string header)
                                                returns http:Unauthorized|http:Forbidden|string? {
    http:ListenerFileUserStoreBasicAuthHandler handler;
    lock {
        string key = config.fileUserStoreConfig.toString();
        if authHandlers.hasKey(key) {
            handler = <http:ListenerFileUserStoreBasicAuthHandler>authHandlers.get(key);
        } else {
            handler = new (config.fileUserStoreConfig.cloneReadOnly());
            authHandlers[key] = handler;
        }
    }
    auth:UserDetails|http:Unauthorized authn = handler.authenticate(header);
    string|string[]? scopes = config?.scopes;
    if authn is auth:UserDetails {
        if scopes is string|string[] {
            http:Forbidden? authz = handler.authorize(authn, scopes);
            if authz is http:Forbidden {
                return authz;
            } 
        }
        return authn.username;
    }
    return authn;
}

isolated function authenticateWithLdapUserStoreConfig(http:LdapUserStoreConfigWithScopes config, string header)
                                                    returns http:Unauthorized|http:Forbidden|string? {
    http:ListenerLdapUserStoreBasicAuthHandler handler;
    lock {
        string key = config.ldapUserStoreConfig.toString();
        if authHandlers.hasKey(key) {
            handler = <http:ListenerLdapUserStoreBasicAuthHandler>authHandlers.get(key);
        } else {
            handler = new (config.ldapUserStoreConfig.cloneReadOnly());
            authHandlers[key] = handler;
        }
    }
    auth:UserDetails|http:Unauthorized authn = handler->authenticate(header);
    string|string[]? scopes = config?.scopes;
    if authn is auth:UserDetails {
        if scopes is string|string[] {
            http:Forbidden? authz = handler->authorize(authn, scopes);
            if authz is http:Forbidden {
                return authz;
            } 
        }
        return authn.username;
    }
    return authn;
}

isolated function authenticateWithJwtValidatorConfig(http:JwtValidatorConfigWithScopes config, 
            string header) returns http:Unauthorized|http:Forbidden|string? {
    http:ListenerJwtAuthHandler handler;
    lock {
        string key = config.jwtValidatorConfig.toString();
        if authHandlers.hasKey(key) {
            handler = <http:ListenerJwtAuthHandler>authHandlers.get(key);
        } else {
            handler = new (config.jwtValidatorConfig.cloneReadOnly());
            authHandlers[key] = handler;
        }
    }
    jwt:Payload|http:Unauthorized authn = handler.authenticate(header);
    string|string[]? scopes = config?.scopes;
    if authn is jwt:Payload {
        if scopes is string|string[] {
            http:Forbidden? authz = handler.authorize(authn, scopes);
            if authz is http:Forbidden {
                return authz;
            } 
        }
        return authn?.sub;
    } else if authn is http:Unauthorized {
        return authn;
    } else {
        panic error("Unsupported record type found.");
    }
}

isolated function authenticateWithOAuth2IntrospectionConfig(http:OAuth2IntrospectionConfigWithScopes config, string header)
                                                            returns http:Unauthorized|http:Forbidden|string? {
    http:ListenerOAuth2Handler handler;
    lock {
        string key = config.oauth2IntrospectionConfig.toString();
        if authHandlers.hasKey(key) {
            handler = <http:ListenerOAuth2Handler>authHandlers.get(key);
        } else {
            handler = new (config.oauth2IntrospectionConfig.cloneReadOnly());
            authHandlers[key] = handler;
        }
    }
    oauth2:IntrospectionResponse|http:Unauthorized|http:Forbidden auth = handler->authorize(header, config?.scopes);
    if auth is oauth2:IntrospectionResponse {
        return auth?.sub;
    } else if auth is http:Unauthorized || auth is http:Forbidden {
        return auth;
    } else {
        panic error("Unsupported record type found.");
    }
}
