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

import ballerina/time;

# Seconds subtracted from a token lifetime, so that a token is treated as expired before
# the authorization server would reject it.
const int TOKEN_CLOCK_SKEW = 30;

# Represents what one discovery pass learned about a server.
#
# + metadata - Validated authorization server metadata
# + resourceUri - Canonical resource identifier declared by the protected resource metadata,
# sent as the `resource` parameter on every token request
# + resourceScopes - `scopes_supported` advertised by the protected resource
# + clientId - Client identifier resolved for this authorization server
type DiscoveredContext record {|
    readonly & AuthorizationServerMetadata metadata;
    string resourceUri;
    readonly & string[] resourceScopes;
    string clientId;
|};

# Stores the tokens held for one MCP server. Reads are internally locked, so a caller can
# obtain a usable token without holding a lock.
isolated class TokenStore {
    private string accessToken = "";
    private string refreshToken = "";
    private int expiryTime = -1;
    private string[] grantedScopes = [];

    # Returns the stored access token, or an empty string if none is held.
    #
    # + return - The access token, or `""`
    isolated function getAccessToken() returns string {
        lock {
            return self.accessToken;
        }
    }

    isolated function getRefreshToken() returns string? {
        lock {
            return self.refreshToken == "" ? () : self.refreshToken;
        }
    }

    # Returns the scopes granted to the current token. Used to compute the scope set for a
    # step-up request, which includes the challenge's scopes alongside previously granted
    # scopes.
    #
    # + return - Scopes granted to the current token
    isolated function getGrantedScopes() returns string[] {
        lock {
            return self.grantedScopes.clone();
        }
    }

    # Reports whether a token has been recorded, including an expired token retained for
    # scope-preserving renewal.
    #
    # + return - `true` if a token has been recorded
    isolated function hasToken() returns boolean {
        lock {
            return self.accessToken != "";
        }
    }

    # Returns the stored access token if it is still usable. Validity and the value are read
    # under one lock, so a concurrent refresh or clear cannot separate the two operations.
    #
    # + return - The usable access token, or `()` if a new token is needed
    isolated function getValidAccessToken() returns string? {
        lock {
            if self.accessToken == "" {
                return ();
            }
            if self.expiryTime >= 0 {
                [int, decimal] now = time:utcNow();
                if now[0] >= self.expiryTime {
                    return ();
                }
            }
            // No lifetime was given: use the token until the server rejects it.
            return self.accessToken;
        }
    }

    # Records a token response.
    #
    # + response - The token response to record
    # + requestedScopes - Scopes sent in the token request, used when the response omits
    # `scope`
    # + preserveRefreshToken - Retain the previous refresh token when a refresh response omits one
    isolated function update(TokenResponse response, string[] requestedScopes,
            boolean preserveRefreshToken = false) {
        lock {
            self.accessToken = response.access_token;
            string? responseRefreshToken = response?.refresh_token;
            if responseRefreshToken is string {
                self.refreshToken = responseRefreshToken;
            } else if !preserveRefreshToken {
                self.refreshToken = "";
            }
            string? responseScope = response?.scope;
            self.grantedScopes = responseScope is string
                ? splitScopes(responseScope)
                : requestedScopes.clone();

            int? lifetime = response?.expires_in;
            if lifetime is int {
                [int, decimal] now = time:utcNow();
                int clockSkew = lifetime < TOKEN_CLOCK_SKEW * 2 ? lifetime / 2 : TOKEN_CLOCK_SKEW;
                self.expiryTime = now[0] + lifetime - clockSkew;
            } else {
                self.expiryTime = -1;
            }
        }
    }

    # Discards everything held, so that the next request starts a fresh authorization.
    isolated function clear() {
        lock {
            self.accessToken = "";
            self.refreshToken = "";
            self.expiryTime = -1;
            self.grantedScopes = [];
        }
    }
}

# Caches the discovered context for one MCP server.
isolated class MetadataStore {
    private DiscoveredContext? context = ();

    # Returns the cached context, or nil if discovery has not run.
    #
    # + return - The context, or `()`
    isolated function get() returns (readonly & DiscoveredContext)? {
        lock {
            DiscoveredContext? current = self.context;
            return current is () ? () : current.cloneReadOnly();
        }
    }

    # Records a discovered context.
    #
    # + context - The context to cache
    isolated function set(readonly & DiscoveredContext context) {
        lock {
            self.context = context;
        }
    }

    # Discards the cached context.
    isolated function clear() {
        lock {
            self.context = ();
        }
    }
}

# Acquires and holds access tokens for one MCP server. The authorization server is
# discovered on first use, and the token is refreshed or re-acquired when no longer usable.
isolated class ClientOAuthProvider {
    private final string serverUrl;
    // Held as immutable values so that isolated methods can read them without a lock.
    private final readonly & OAuthConfig config;
    private final readonly & AuthHttpConfig clientConfig;
    private final ClientObserver? observer;
    private final TokenStore tokens;
    private final MetadataStore metadataStore;

    # Creates a provider for one MCP server.
    #
    # + serverUrl - URL of the MCP server, used to derive the well-known metadata locations
    # + config - Authorization configuration
    # + clientConfig - HTTP settings for metadata and token endpoint requests
    # + return - A `OAuthConfigError` if the configuration is unusable, or `()`
    isolated function init(string serverUrl, OAuthConfig config,
            AuthHttpConfig clientConfig = {}, ClientObserver? observer = ()) returns Error? {
        check validateConfig(config);
        self.serverUrl = check canonicalResourceUri(serverUrl);
        self.config = config.cloneReadOnly();
        self.clientConfig = clientConfig.cloneReadOnly();
        self.observer = observer;
        self.tokens = new;
        self.metadataStore = new;
    }

    # Reports whether this provider uses the client credentials grant.
    #
    # + return - `true` when configured with the client credentials grant
    isolated function usesClientCredentialsGrant() returns boolean {
        return self.config.grant is ClientCredentialsGrant;
    }

    # Returns an `Authorization` header value, acquiring or refreshing a token if needed.
    # Acquisition is performed under a lock and re-checked on entry, so concurrent callers
    # produce one token request rather than one each.
    #
    # + challenge - Challenge from the rejected request, whose scopes are authoritative
    # + return - The header value, or an `Error`
    isolated function getAuthorizationHeader(BearerChallenge? challenge = ())
            returns string|Error {
        string? cached = self.tokens.getValidAccessToken();
        if challenge is () && cached is string {
            return "Bearer " + cached;
        }
        // A mutable value cannot be carried into a lock.
        readonly & BearerChallenge? pinned = challenge is () ? () : challenge.cloneReadOnly();
        lock {
            string? current = self.tokens.getValidAccessToken();
            if pinned is () && current is string {
                return "Bearer " + current;
            }
            check self.acquire(pinned);
            return "Bearer " + self.tokens.getAccessToken();
        }
    }

    # Returns an authorization header only if one can be produced without starting the flow.
    # The first request goes out unauthenticated, since the challenge it provokes is what
    # names the protected resource metadata document.
    #
    # + return - The header value, `()` if the flow has not started yet, or an `Error` if a
    # refresh was attempted and failed
    isolated function tryGetAuthorizationHeader() returns string?|Error {
        string? cached = self.tokens.getValidAccessToken();
        if cached is string {
            return "Bearer " + cached;
        }
        if self.metadataStore.get() is () {
            return ();
        }
        return self.getAuthorizationHeader();
    }

    # Returns a cached authorization header without starting or refreshing a flow.
    #
    # + return - The header value, or `()` if no usable token is cached
    isolated function peekAuthorizationHeader() returns string? {
        string? cached = self.tokens.getValidAccessToken();
        return cached is string ? "Bearer " + cached : ();
    }

    # Acquires a token.
    #
    # + challenge - Challenge that triggered this acquisition, if any
    # + return - An `Error` if no token could be obtained
    isolated function acquire(readonly & BearerChallenge? challenge) returns Error? {
        readonly & DiscoveredContext context = check self.resolveContext(challenge);
        string[] scopes = self.selectScopes(challenge, context);
        readonly & (ClientCredentialsGrant|AuthorizationCodeGrant) grant = self.config.grant;
        if grant is readonly & ClientCredentialsGrant {
            TokenResponse response = check requestClientCredentialsToken(context.clientId,
                    grant.clientConfig.clientAuth, context.metadata, context.resourceUri, scopes,
                    self.clientConfig, self.observer);
            self.tokens.update(response, scopes);
            notifyClientObserver(self.observer, {
                eventType: TOKEN_ACQUIRED,
                eventTarget: AUTHORIZATION_SERVER,
                eventUrl: context.metadata.token_endpoint,
                eventMessage: "Client credentials token acquired"
            });
            return;
        }

        string? refreshToken = self.tokens.getRefreshToken();
        if refreshToken is string && self.scopesAlreadyGranted(scopes) {
            TokenResponse|Error refreshed = refreshAccessToken(grantClientAuth(grant),
                    context.metadata, context.clientId, refreshToken, context.resourceUri, scopes,
                    self.clientConfig, self.observer);
            if refreshed is TokenResponse {
                self.tokens.update(refreshed, scopes, preserveRefreshToken = true);
                notifyClientObserver(self.observer, {
                    eventType: TOKEN_ACQUIRED,
                    eventTarget: AUTHORIZATION_SERVER,
                    eventUrl: context.metadata.token_endpoint,
                    eventMessage: "Access token refreshed"
                });
                return;
            }
            if !(refreshed is OAuthInvalidGrantError) {
                return refreshed;
            }
            self.tokens.clear();
        }
        return self.authorizeInteractively(grant, context, scopes);
    }

    isolated function authorizeInteractively(readonly & AuthorizationCodeGrant grant,
            readonly & DiscoveredContext context, string[] scopes) returns Error? {
        [string, PendingAuthorization] [authorizationUrl, pending] = check buildAuthorizationRequest(
                grant, context.clientId, context.metadata, context.resourceUri, scopes);

        string authorizationEndpoint = context.metadata.authorization_endpoint ?: context.metadata.issuer;
        notifyClientObserver(self.observer, {
            eventType: AUTHORIZATION_REDIRECT,
            eventTarget: USER_AGENT,
            eventUrl: authorizationEndpoint,
            eventMessage: "Authorization URL generated"
        });

        AuthorizationRedirectHandler redirectHandler = grant.redirectHandler;
        error? redirectResult = redirectHandler(authorizationUrl);
        if redirectResult is error {
            return error OAuthAuthorizationError(
                "The redirect handler failed to direct the user to the authorization URL.",
                redirectResult);
        }

        AuthorizationCallbackHandler callbackHandler = grant.callbackHandler;
        AuthorizationCallbackParams|error params = callbackHandler();
        if params is error {
            return error OAuthAuthorizationError(
                "The callback handler failed to return the authorization response.", params);
        }
        notifyClientObserver(self.observer, {
            eventType: AUTHORIZATION_CALLBACK,
            eventTarget: USER_AGENT,
            eventUrl: grant.redirectUri,
            eventMessage: "Authorization callback received; parameters redacted"
        });
        TokenResponse response = check completeAuthorization(grantClientAuth(grant),
                context.metadata, pending, params, self.clientConfig, self.observer);
        self.tokens.update(response, scopes);
        notifyClientObserver(self.observer, {
            eventType: TOKEN_ACQUIRED,
            eventTarget: AUTHORIZATION_SERVER,
            eventUrl: context.metadata.token_endpoint,
            eventMessage: "Authorization code token acquired"
        });
    }

    # Returns the discovered context for this server, discovering it if needed.
    #
    # + challenge - Challenge naming the protected resource metadata document, if any
    # + return - The context, or an `Error`
    isolated function resolveContext(readonly & BearerChallenge? challenge)
            returns (readonly & DiscoveredContext)|Error {
        (readonly & DiscoveredContext)? cached = self.metadataStore.get();
        if cached is readonly & DiscoveredContext && !signalsMetadataChange(challenge) {
            return cached;
        }
        self.metadataStore.clear();

        string[] candidates = check self.selectResourceMetadataUrls(challenge);
        ProtectedResourceMetadata resourceMetadata =
            check discoverProtectedResourceMetadata(candidates, self.serverUrl, self.clientConfig, self.observer);

        ClientCredentialsGrant|AuthorizationCodeGrant grant = self.config.grant;
        ClientCredentialsClientConfig|AuthorizationCodeClientConfig oauthClient = grant.clientConfig;
        string issuer = check selectAuthorizationServer(oauthClient, resourceMetadata, self.serverUrl);
        AuthorizationServerMetadata metadata =
            check discoverAuthorizationServerMetadata(issuer, self.clientConfig, self.observer);
        string clientId = check resolveClientId(oauthClient, metadata);
        check validateGrantAndClientAuthSupported(grant, metadata);

        // Credentials and tokens issued by one authorization server are not valid with
        // another, so a change of issuer discards whatever is held.
        if cached is readonly & DiscoveredContext && cached.metadata.issuer != metadata.issuer {
            self.tokens.clear();
        }

        readonly & DiscoveredContext context = {
            metadata: metadata.cloneReadOnly(),
            // Authoritative for the `resource` parameter.
            resourceUri: resourceMetadata.'resource,
            resourceScopes: (resourceMetadata.scopes_supported ?: []).cloneReadOnly(),
            clientId: clientId
        };
        self.metadataStore.set(context);
        return context;
    }

    # Determines where to fetch protected resource metadata from. A challenge naming the
    # document takes precedence over the well-known locations.
    #
    # + challenge - Challenge that may name the document
    # + return - Candidate URLs in priority order, or an `Error`
    isolated function selectResourceMetadataUrls(readonly & BearerChallenge? challenge)
            returns string[]|Error {
        if challenge is readonly & BearerChallenge {
            string? named = challenge.resourceMetadata;
            if named is string {
                return [named];
            }
        }
        return buildProtectedResourceMetadataUrls(self.serverUrl);
    }

    # Selects the scopes to request. A challenge scope is authoritative and is unioned with
    # previously granted scopes, per the Step-Up Authorization Flow. A renewal preserves
    # the current token's scopes. On first acquisition, `scopes_supported` wins, then
    # configuration is used as a final fallback.
    #
    # + challenge - Challenge that triggered this acquisition, if any
    # + context - Discovered authorization context
    # + return - The scopes to request
    isolated function selectScopes(readonly & BearerChallenge? challenge,
            readonly & DiscoveredContext context) returns string[] {
        if challenge is readonly & BearerChallenge {
            string? challenged = challenge.scope;
            if challenged is string {
                return unionScopes(self.tokens.getGrantedScopes(), splitScopes(challenged));
            }
        }
        string[] grantedScopes = self.tokens.getGrantedScopes();
        if self.tokens.hasToken() {
            return grantedScopes;
        }
        if context.resourceScopes.length() > 0 {
            return context.resourceScopes.clone();
        }
        return (self.config?.scopes ?: []).clone();
    }

    isolated function scopesAlreadyGranted(string[] requested) returns boolean {
        if requested.length() == 0 {
            return true;
        }
        string[] granted = self.tokens.getGrantedScopes();
        foreach string scope in requested {
            if granted.indexOf(scope) is () {
                return false;
            }
        }
        return true;
    }
}

# Reports whether a challenge indicates the protected resource metadata may have changed,
# per RFC 9728 section 5.2, in which case it is retrieved again.
#
# A scope challenge is excluded. It carries the metadata URL only for consistency with a
# 401, and reports a scope deficiency rather than a change of metadata.
#
# + challenge - Challenge from the rejected request, if any
# + return - `true` if the metadata is to be retrieved again
isolated function signalsMetadataChange(readonly & BearerChallenge? challenge) returns boolean {
    if challenge is () || challenge?.resourceMetadata is () {
        return false;
    }
    return challenge?.errorCode != ERROR_INSUFFICIENT_SCOPE;
}

# Selects an authorization server listed in protected resource metadata.
#
# Pre-registered credentials are bound to their configured issuer, which must appear in the
# resource metadata. A portable CIMD client selects the first advertised issuer as a
# deterministic default.
#
# + oauthClient - Client registration whose issuer binding determines selection
# + resourceMetadata - Protected resource metadata for the MCP server
# + serverUrl - Canonical URI of the MCP server, for the error message
# + return - Issuer identifier of the selected authorization server, or a `OAuthDiscoveryError`
# if none is listed
isolated function selectAuthorizationServer(
        ClientCredentialsClientConfig|AuthorizationCodeClientConfig oauthClient,
        ProtectedResourceMetadata resourceMetadata, string serverUrl) returns string|Error {
    string[] servers = resourceMetadata.authorization_servers;
    if servers.length() == 0 {
        return error OAuthDiscoveryError(string `Protected resource metadata for '${serverUrl}' ` +
            string `lists no authorization servers.`);
    }
    if oauthClient is PreRegisteredClientCredentialsConfig ||
            oauthClient is PreRegisteredAuthorizationCodeConfig {
        if servers.indexOf(oauthClient.issuer) is () {
            return error OAuthDiscoveryError(string `Protected resource metadata for '${serverUrl}' does ` +
                string `not list the configured authorization server issuer '${oauthClient.issuer}'.`);
        }
        return oauthClient.issuer;
    }
    return servers[0];
}

# Splits a space delimited scope string.
#
# + scopeValue - The scope string
# + return - The individual scopes
isolated function splitScopes(string scopeValue) returns string[] {
    string[] scopes = [];
    foreach string part in re `\s+`.split(scopeValue) {
        string trimmed = part.trim();
        if trimmed != "" {
            scopes.push(trimmed);
        }
    }
    return scopes;
}

# Unions two scope sets, preserving order.
#
# + existing - The base scope set
# + additional - Scopes to add
# + return - The union
isolated function unionScopes(string[] existing, string[] additional) returns string[] {
    string[] combined = existing.clone();
    foreach string scope in additional {
        if combined.indexOf(scope) is () {
            combined.push(scope);
        }
    }
    return combined;
}
