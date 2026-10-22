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
import ballerina/jwt;
import ballerina/log;
import ballerina/oauth2;

const BEARER_SCHEME = "bearer";
const SCP_CLAIM = "scp";
const CLIENT_ID_CLAIM = "client_id";
const AZP_CLAIM = "azp";
const OFFLINE_ACCESS_SCOPE = "offline_access";

// `offline_access` asks the authorization server for a refresh token; it is not a permission of
// this resource. The MCP authorization specification says servers SHOULD NOT advertise it in
// challenges or metadata, and requiring it would reject tokens that do not repeat it.
isolated function rejectOfflineAccess(string[] scopes, string setting) returns Error? {
    if scopes.indexOf(OFFLINE_ACCESS_SCOPE) !is () {
        return error ServerError(string `'${OFFLINE_ACCESS_SCOPE}' is not a scope of this resource; remove it ` +
            string `from ${setting}. Clients request refresh tokens from the authorization server themselves.`);
    }
}

// A scope is an RFC 6749 scope-token: one or more printable ASCII characters other than space,
// `"` and `\`. Anything else would be split or mangled in a `WWW-Authenticate` challenge.
isolated function checkScopes(string[] scopes, string setting) returns Error? {
    foreach string scope in scopes {
        if !re `[!#-\[\]-~]+`.isFullMatch(scope) {
            return error ServerError(string `'${scope}' in ${setting} is not a valid OAuth scope: a scope is one ` +
                "or more printable ASCII characters other than space, '\"' and '\\'");
        }
    }
    check rejectOfflineAccess(scopes, setting);
}


# Validates access tokens locally as signed JWTs.
public type JwtTokenValidator record {|
    # JWT validation settings. The expected issuer is the `issuer` of the enclosing
    # `mcp:AuthorizationServer`, and the expected audience is its `audience`. Set neither here.
    http:JwtValidatorConfig jwtValidatorConfig;
|};

# Validates access tokens through an OAuth 2.0 token introspection endpoint (RFC 7662).
public type IntrospectionTokenValidator record {|
    # Introspection endpoint settings. The `aud` of the introspection response must match the
    # `audience` of the enclosing `mcp:AuthorizationServer`.
    http:OAuth2IntrospectionConfig oauth2IntrospectionConfig;
|};

# An authorization server whose access tokens an MCP server accepts.
public type AuthorizationServer record {|
    # Issuer identifier of the authorization server. It is advertised in the protected resource
    # metadata, and JWT access tokens must carry it as `iss`.
    string issuer;
    # Audience that this server's access tokens carry when they are issued for this MCP server.
    # Defaults to the `resource` of the enclosing `mcp:OAuthProtectedResourceConfig`, which is what an
    # authorization server that supports resource indicators (RFC 8707) issues. Set it when the
    # authorization server uses its own identifier for the API, such as `api://<app-id>`.
    string|string[] audience?;
    # How access tokens issued by this server are validated
    JwtTokenValidator|IntrospectionTokenValidator validator;
|};

# Protects a service as an OAuth protected resource (RFC 9728), as the MCP authorization
# specification requires. The service acts as an OAuth 2.1 resource server: it publishes protected
# resource metadata, challenges unauthenticated requests with `WWW-Authenticate`, and accepts only
# bearer tokens issued for it.
public type OAuthProtectedResourceConfig record {|
    # Canonical URI of this MCP server as clients address it, such as
    # `https://mcp.example.com/mcp`. It identifies the protected resource in metadata, is the
    # default token audience, and locates the metadata document at
    # `<origin>/.well-known/oauth-protected-resource<path>`. Set it to the public URL when the
    # server runs behind a proxy.
    string 'resource;
    # Authorization servers whose access tokens are accepted, each with how its tokens are validated
    AuthorizationServer[] authorizationServers;
    # Scopes every request must carry. This is local authorization policy, not a field in the
    # protected resource metadata document. These scopes are advertised in `401` challenges and
    # combined with operation-specific scopes in `insufficient_scope` challenges.
    string[] requiredScopes = [];
    # Scopes that a broader scope grants, keyed by the broader scope, for authorization servers
    # that issue hierarchical scopes. A token granted a key also holds every scope listed for it,
    # transitively, when required and tool scopes are checked. For example,
    # `{"files:admin": ["files:write"], "files:write": ["files:read"]}` lets a token granted
    # `files:admin` call a tool that needs `files:read`.
    map<string[]> scopeHierarchy = {};
    # Scopes published in the `scopes_supported` field of protected resource metadata. This field
    # is informational and is not used to authorize requests. Defaults to `requiredScopes`; scopes
    # declared on tools are requested through `403` step-up challenges instead.
    string[] scopesSupported?;
    # Human-readable name of the server, advertised in protected resource metadata
    string resourceName?;
    # URL of developer documentation for the server, advertised in protected resource metadata
    string resourceDocumentation?;
    # URL of the server's policy on how clients may use its data, advertised in protected resource metadata
    string resourcePolicyUri?;
    # URL of the server's terms of service, advertised in protected resource metadata
    string resourceTosUri?;
|};

# The authenticated caller of an MCP request. Declare a parameter of this type on a tool
# function, or on `onListTools`/`onCallTool` of an advanced service, to receive it. It is nil
# when the service is not configured with `mcp:OAuthProtectedResourceConfig`.
public type AuthContext record {|
    # Subject of the access token (`sub`)
    string? subject;
    # OAuth client the token was issued to (`client_id` or `azp`)
    string? clientId;
    # Issuer of the access token
    string? issuer;
    # Scopes the access token holds: the scopes granted to it, together with the scopes they imply
    # through `scopeHierarchy`. The scopes as granted remain in `claims`.
    string[] scopes;
    # All claims of the token, or the introspection response
    map<json> claims;
    # The raw access token. Use it only for token exchange: the MCP authorization specification
    # forbids passing it through to upstream APIs.
    string token;
|};

# Validates the access tokens issued by one authorization server. The verifiers of a service
# form a chain through their `next` fields: final fields of isolated object types can be read
# without locks, which an array of verifiers could not.
isolated class TokenVerifier {
    private final string issuer;
    private final readonly & string[] audiences;
    private final string scopeKey;
    private final http:ListenerJwtAuthHandler? jwtHandler;
    private final oauth2:ListenerOAuth2Provider? introspectionProvider;
    private final TokenVerifier? next;

    isolated function init(readonly & AuthorizationServer server, string 'resource, TokenVerifier? next)
            returns Error? {
        string|string[] audience = server?.audience ?: 'resource;
        self.issuer = server.issuer;
        string[] audiences = audience is string[] ? audience : [audience];
        self.audiences = audiences.cloneReadOnly();
        self.next = next;
        JwtTokenValidator|IntrospectionTokenValidator validator = server.validator;
        if validator is JwtTokenValidator {
            http:JwtValidatorConfig jwtConfig = {...validator.jwtValidatorConfig};
            // The authorization server entry is the single place for its issuer and audience.
            if jwtConfig.audience !is () {
                return error ServerError(string `Set the audience of authorization server '${server.issuer}' ` +
                    "with 'audience' on the authorization server, not in 'jwtValidatorConfig'");
            }
            string? configuredIssuer = jwtConfig.issuer;
            if configuredIssuer is string && configuredIssuer != server.issuer {
                return error ServerError(string `The 'jwtValidatorConfig' issuer '${configuredIssuer}' does not ` +
                    string `match the authorization server issuer '${server.issuer}'`);
            }
            jwtConfig.issuer = server.issuer;
            jwtConfig.audience = audience;
            self.scopeKey = jwtConfig.scopeKey;
            self.jwtHandler = new (jwtConfig);
            self.introspectionProvider = ();
        } else {
            http:OAuth2IntrospectionConfig introspectionConfig = validator.oauth2IntrospectionConfig;
            self.scopeKey = introspectionConfig.scopeKey;
            self.jwtHandler = ();
            // The provider is used directly rather than through the HTTP handler, which reports an
            // unreachable introspection endpoint the same way as an inactive token.
            self.introspectionProvider = new (introspectionConfig);
        }
    }

    isolated function getIssuer() returns string => self.issuer;

    isolated function getScopeKey() returns string => self.scopeKey;

    isolated function getNext() returns TokenVerifier? => self.next;

    isolated function isJwt() returns boolean => self.jwtHandler !is ();

    # Validates a token, checking its signature, lifetime, issuer and audience for a JWT, or its
    # activity, issuer and audience through introspection.
    #
    # + authorizationHeader - The `Authorization` header carrying the token
    # + token - The bearer token
    # + return - The token claims or introspection response, an `IntrospectionUnavailableError` when
    # the introspection endpoint cannot be used, or another error describing why the token is rejected
    isolated function verify(string authorizationHeader, string token) returns map<json>|error {
        http:ListenerJwtAuthHandler? jwtHandler = self.jwtHandler;
        if jwtHandler is http:ListenerJwtAuthHandler {
            jwt:Payload|http:Unauthorized payload = jwtHandler.authenticate(authorizationHeader);
            if payload !is jwt:Payload {
                log:printDebug("Rejected MCP access token", issuer = self.issuer, reason = payload?.body.toString());
                return error("The access token is invalid or expired");
            }
            map<json>|error claims = payload.toJson().ensureType();
            return claims is map<json> ? claims : error("The access token is invalid");
        }

        oauth2:ListenerOAuth2Provider introspectionProvider = <oauth2:ListenerOAuth2Provider>self.introspectionProvider;
        // The provider panics on a response whose `aud` is an array, so the call is trapped.
        oauth2:IntrospectionResponse|error introspection = trap introspectionProvider.authorize(token);
        if introspection is error {
            // The endpoint could not be reached or its response could not be read: the token was
            // not judged, so this is reported as the server's failure rather than the token's.
            log:printError("MCP access token introspection failed", introspection, issuer = self.issuer);
            return error IntrospectionUnavailableError("The access token could not be validated");
        }
        if !introspection.active {
            return error("The access token is invalid or expired");
        }
        map<json>|error response = introspection.toJson().ensureType();
        if response is error {
            return error("The access token is invalid");
        }
        map<json> claims = toIntrospectionClaims(response);
        json responseIssuer = claims["iss"];
        if responseIssuer !is () && responseIssuer != self.issuer {
            log:printDebug("Rejected MCP access token from another issuer", issuer = self.issuer,
                    responseIssuer = responseIssuer.toString());
            return error("The access token was not issued by this authorization server");
        }
        if !audienceMatches(claims["aud"], self.audiences) {
            log:printDebug("Rejected MCP access token issued for another audience", issuer = self.issuer,
                    audience = claims["aud"].toString());
            return error("The access token was not issued for this resource");
        }
        return claims;
    }
}

# The introspection endpoint could not be reached, or its response could not be read.
type IntrospectionUnavailableError distinct error;

# A response that ends a request because the caller could not be authenticated.
type AuthenticationFailure http:BadRequest|http:Unauthorized|http:Forbidden|http:ServiceUnavailable;

// The oauth2 module renames some RFC 7662 response members to Ballerina field names; they are
// restored, so that claims carry the names the authorization server sent.
isolated function toIntrospectionClaims(map<json> response) returns map<json> {
    map<json> claims = {...response};
    foreach [string, string] [fieldName, memberName] in [["clientId", "client_id"], ["tokenType", "token_type"]] {
        json value = claims.removeIfHasKey(fieldName);
        if value !is () {
            claims[memberName] = value;
        }
    }
    return claims;
}

# Validates the access tokens of one MCP service and builds its authorization challenges.
# Everything it holds is fixed when the service is attached, so it is shared between requests
# without locks.
isolated class ServerAuthenticator {
    private final readonly & OAuthProtectedResourceConfig config;
    private final readonly & map<string[]> toolScopes;
    private final string metadataUrl;
    private final string metadataPath;
    private final TokenVerifier verifiers;

    isolated function init(readonly & OAuthProtectedResourceConfig config, readonly & map<string[]> toolScopes)
            returns Error? {
        AuthorizationServer[] servers = config.authorizationServers;
        if servers.length() == 0 {
            return error ServerError("At least one authorization server is required for MCP authorization");
        }
        string canonicalResource = check canonicalResourceUri(config.'resource);
        if canonicalResource != config.'resource {
            return error ServerError(string `MCP auth resource '${config.'resource}' is not canonical; ` +
                string `use '${canonicalResource}'`);
        }
        foreach [string, string?] [setting, url] in [
            ["resourceDocumentation", config.resourceDocumentation],
            ["resourcePolicyUri", config.resourcePolicyUri],
            ["resourceTosUri", config.resourceTosUri]
        ] {
            if url is string {
                UrlParts|Error parsedUrl = parseAbsoluteUrl(url);
                if parsedUrl is Error {
                    return error ServerError(string `Invalid '${setting}': ${parsedUrl.message()}`, parsedUrl);
                }
            }
        }
        check checkScopes(config.requiredScopes, "requiredScopes");
        check checkScopes(config.scopesSupported ?: [], "scopesSupported");
        foreach [string, string[]] [broaderScope, impliedScopes] in config.scopeHierarchy.entries() {
            check checkScopes([broaderScope, ...impliedScopes], "scopeHierarchy");
            if impliedScopes.length() == 0 {
                return error ServerError(string `The scopeHierarchy entry for '${broaderScope}' lists no scopes`);
            }
        }
        foreach [string, string[]] [toolName, scopes] in toolScopes.entries() {
            check checkScopes(scopes, string `the '@mcp:Tool' scopes of '${toolName}'`);
        }
        string[] issuers = [];
        int introspectionServers = 0;
        foreach AuthorizationServer server in servers {
            if issuers.indexOf(server.issuer) !is () {
                return error ServerError(string `Authorization server '${server.issuer}' is configured more than once`);
            }
            issuers.push(server.issuer);
            if server.validator is IntrospectionTokenValidator {
                introspectionServers += 1;
            }
        }
        // An opaque token does not say who issued it, so it could only be routed by offering it to
        // every introspection server, disclosing it to servers that did not issue it.
        if introspectionServers > 1 {
            return error ServerError("Only one authorization server can use 'oauth2IntrospectionConfig': opaque " +
                "tokens do not name their issuer, so they cannot be routed safely. Use JWT access tokens, or a " +
                "separate MCP service for each authorization server that issues opaque tokens");
        }
        UrlParts resourceParts = check parseAbsoluteUrl(config.'resource);
        string resourcePath = resourcePathForWellKnownUrl(resourceParts.path);
        self.config = config;
        self.toolScopes = toolScopes;
        self.metadataPath = resourcePath;
        self.metadataUrl = resourceParts.origin + PROTECTED_RESOURCE_METADATA_PATH + resourcePath;

        // Built from the last server to the first, so the chain keeps the configured order.
        TokenVerifier? verifiers = ();
        int index = servers.length() - 1;
        while index >= 0 {
            verifiers = check new TokenVerifier(config.authorizationServers[index], config.'resource, verifiers);
            index -= 1;
        }
        self.verifiers = <TokenVerifier>verifiers;
    }

    # Returns the path, relative to the well-known prefix, that serves this resource's metadata.
    #
    # + return - The resource path, or an empty string for a resource at the origin root
    isolated function getMetadataPath() returns string => self.metadataPath;

    # Builds the protected resource metadata document (RFC 9728) for this resource.
    #
    # + return - The metadata document
    isolated function getMetadata() returns readonly & ProtectedResourceMetadata {
        string[] scopesSupported = self.config.scopesSupported ?: self.config.requiredScopes;
        ProtectedResourceMetadata metadata = {
            'resource: self.config.'resource,
            authorization_servers: from AuthorizationServer server in self.config.authorizationServers
                select server.issuer,
            bearer_methods_supported: ["header"]
        };
        if scopesSupported.length() > 0 {
            metadata.scopes_supported = scopesSupported;
        }
        string? resourceName = self.config.resourceName;
        if resourceName is string {
            metadata.resource_name = resourceName;
        }
        foreach [string, string?] [name, value] in [
            ["resource_documentation", self.config.resourceDocumentation],
            ["resource_policy_uri", self.config.resourcePolicyUri],
            ["resource_tos_uri", self.config.resourceTosUri]
        ] {
            if value is string {
                metadata[name] = value;
            }
        }
        return metadata.cloneReadOnly();
    }

    # Authenticates a request from its `Authorization` header and checks the scopes every
    # request requires.
    #
    # + headers - Request headers
    # + return - The authenticated caller, a `400` challenge when the `Authorization` header is
    # malformed, a `401` challenge when the request carries no valid bearer token, a `403`
    # challenge when the token lacks the required scopes, or `503` when the token could not be
    # validated because the introspection endpoint is unavailable
    isolated function authenticate(http:Headers headers)
            returns readonly & AuthContext|AuthenticationFailure {
        string[]|http:HeaderNotFoundError authorizationHeaders = headers.getHeaders(AUTHORIZATION_HEADER);
        if authorizationHeaders is http:HeaderNotFoundError {
            // RFC 6750 section 3.1: a request without credentials gets a challenge without an error code.
            return self.unauthorized();
        }
        if authorizationHeaders.length() != 1 {
            return self.invalidRequest("Exactly one Authorization header is allowed");
        }
        string authorizationHeader = authorizationHeaders[0].trim();
        int? separator = authorizationHeader.indexOf(" ");
        if separator is () || authorizationHeader.substring(0, separator).toLowerAscii() != BEARER_SCHEME {
            return self.unauthorized();
        }
        string token = authorizationHeader.substring(separator + 1).trim();
        if token == "" {
            return self.invalidRequest("The bearer token is empty");
        }

        // The token has already been parsed and trimmed here. Give the JWT handler a canonical
        // header so that it does not interpret otherwise-valid whitespace differently.
        [map<json>, TokenVerifier]|error verified = self.verify("Bearer " + token, token);
        if verified is IntrospectionUnavailableError {
            // No `invalid_token`: the token was not judged, so the client should keep it and retry.
            return <http:ServiceUnavailable>{body: createJsonRpcError(INTERNAL_ERROR, verified.message())};
        }
        if verified is error {
            return self.unauthorized("invalid_token", verified.message());
        }
        readonly & AuthContext authContext =
                createAuthContext(verified[0], token, verified[1], self.config.scopeHierarchy);
        if missing(authContext.scopes, self.config.requiredScopes).length() > 0 {
            return self.insufficientScope([]);
        }
        return authContext;
    }

    # Checks that the caller holds the scopes declared for a tool with `@mcp:Tool`.
    #
    # + authContext - The authenticated caller
    # + toolName - Name of the tool being called
    # + return - A `403` challenge when scopes are missing, otherwise nil
    isolated function authorizeTool(AuthContext authContext, string toolName) returns http:Forbidden? {
        string[]? toolScopes = self.toolScopes[toolName];
        if toolScopes is () || missing(authContext.scopes, toolScopes).length() == 0 {
            return;
        }
        return self.insufficientScope(toolScopes);
    }

    # Creates the `403` challenge that asks the client to obtain a token with more scopes.
    #
    # + scopes - Scopes the operation needs in addition to the scopes every request requires
    # + return - The `403 Forbidden` response
    isolated function insufficientScope(string[] scopes) returns http:Forbidden {
        string[] challengeScopes = union(self.config.requiredScopes, scopes);
        return insufficientScopeResponse(challengeScopes, self.metadataUrl);
    }

    private isolated function unauthorized(string? errorCode = (), string? description = ()) returns http:Unauthorized {
        string challenge = bearerChallenge(self.metadataUrl, self.config.requiredScopes, errorCode, description);
        return {
            headers: {[WWW_AUTHENTICATE_HEADER]: challenge},
            body: createJsonRpcError(INVALID_REQUEST, description ?: "Authorization required")
        };
    }

    // RFC 6750 section 3.1: a malformed request is answered with 400 and `invalid_request`.
    private isolated function invalidRequest(string description) returns http:BadRequest => {
        headers: {
            [WWW_AUTHENTICATE_HEADER]: bearerChallenge(self.metadataUrl, self.config.requiredScopes, "invalid_request",
                    description)
        },
        body: createJsonRpcError(INVALID_REQUEST, description)
    };

    // A token is only ever given to the one authorization server that could have issued it, so a
    // token is never disclosed to another server. A JWT goes to the server named in its (yet
    // unverified) `iss`, whichever way that server's tokens are validated; a JWT naming no
    // configured server, or no issuer at all, is rejected here. An opaque token carries no issuer,
    // so it goes to the introspection server, of which there is at most one.
    private isolated function verify(string authorizationHeader, string token)
            returns [map<json>, TokenVerifier]|error {
        [jwt:Header, jwt:Payload]|jwt:Error decoded = jwt:decode(token);
        TokenVerifier? verifier = self.verifiers;
        if decoded is jwt:Error {
            while verifier is TokenVerifier {
                if !verifier.isJwt() {
                    return [check verifier.verify(authorizationHeader, token), verifier];
                }
                verifier = verifier.getNext();
            }
            return error("The access token is invalid");
        }
        string? tokenIssuer = decoded[1].iss;
        if tokenIssuer is () {
            return error("The access token does not name its issuer");
        }
        while verifier is TokenVerifier {
            if verifier.getIssuer() == tokenIssuer {
                return [check verifier.verify(authorizationHeader, token), verifier];
            }
            verifier = verifier.getNext();
        }
        return error("The access token was not issued by a trusted authorization server");
    }
}

isolated function createAuthContext(map<json> claims, string token, TokenVerifier verifier,
        readonly & map<string[]> scopeHierarchy) returns readonly & AuthContext {
    json subject = claims["sub"];
    json clientId = claims[CLIENT_ID_CLAIM] ?: claims[AZP_CLAIM];
    return {
        subject: subject is string ? subject : (),
        clientId: clientId is string ? clientId : (),
        // The configured issuer is authoritative: a JWT must name it, and an introspection response
        // naming another issuer is rejected.
        issuer: verifier.getIssuer(),
        // Expanded once here, so every scope check, including those in handlers, sees implied scopes.
        scopes: expandScopes(grantedScopes(claims, verifier.getScopeKey()), scopeHierarchy).cloneReadOnly(),
        claims: claims.cloneReadOnly(),
        token
    };
}

# Creates the `403` challenge for an operation that needs more scopes (RFC 6750 section 3.1).
#
# + scopes - Scopes the operation needs
# + metadataUrl - URL of the protected resource metadata, if the service publishes it
# + return - The `403 Forbidden` response
isolated function insufficientScopeResponse(string[] scopes, string? metadataUrl) returns http:Forbidden => {
    headers: {
        [WWW_AUTHENTICATE_HEADER]: bearerChallenge(metadataUrl, scopes, "insufficient_scope",
                "The access token does not grant the scopes this operation requires")
    },
    body: createJsonRpcError(INVALID_REQUEST, "Insufficient scope")
};

# Builds a `Bearer` challenge for the `WWW-Authenticate` header (RFC 6750, RFC 9728 section 5.1).
#
# + metadataUrl - URL of the protected resource metadata
# + scopes - Scopes to request
# + errorCode - OAuth error code
# + description - Human-readable error description
# + return - The challenge
isolated function bearerChallenge(string? metadataUrl, string[] scopes, string? errorCode = (),
        string? description = ()) returns string {
    string[] authParams = [];
    if errorCode is string {
        authParams.push(string `error="${quoteAuthParam(errorCode)}"`);
    }
    if description is string {
        authParams.push(string `error_description="${quoteAuthParam(description)}"`);
    }
    if scopes.length() > 0 {
        authParams.push(string `scope="${quoteAuthParam(string:'join(" ", ...scopes))}"`);
    }
    if metadataUrl is string {
        authParams.push(string `resource_metadata="${quoteAuthParam(metadataUrl)}"`);
    }
    return authParams.length() == 0 ? "Bearer" : "Bearer " + string:'join(", ", ...authParams);
}

isolated function quoteAuthParam(string value) returns string =>
    re `"`.replaceAll(re `\\`.replaceAll(value, "\\\\"), "\\\"");

# Returns the scopes granted to a token. Scopes are read from the configured scope claim, then
# from `scp`, either as a space-separated string or as an array.
#
# + claims - Token claims or introspection response
# + scopeKey - Configured scope claim
# + return - The granted scopes
isolated function grantedScopes(map<json> claims, string scopeKey) returns string[] {
    json scopeClaim = claims[scopeKey] ?: claims[SCP_CLAIM];
    if scopeClaim is string {
        return re `\s+`.split(scopeClaim.trim()).filter(scope => scope != "");
    }
    if scopeClaim is json[] {
        string[] scopes = [];
        foreach json scope in scopeClaim {
            if scope is string {
                scopes.push(scope);
            }
        }
        return scopes;
    }
    return [];
}

isolated function audienceMatches(json audience, readonly & string[] expectedAudiences) returns boolean {
    if audience is string {
        return expectedAudiences.indexOf(audience) !is ();
    }
    if audience is json[] {
        foreach json entry in audience {
            if entry is string && expectedAudiences.indexOf(entry) !is () {
                return true;
            }
        }
    }
    return false;
}

isolated function missing(string[] granted, string[] required) returns string[] {
    string[] missingScopes = [];
    foreach string scope in required {
        if granted.indexOf(scope) is () {
            missingScopes.push(scope);
        }
    }
    return missingScopes;
}

# Adds to granted scopes every scope they imply through a scope hierarchy, transitively. The
# granted scopes come first, followed by the implied ones in the order they are reached. Cycles
# make their scopes equivalent.
#
# + granted - Scopes granted to the access token
# + scopeHierarchy - Scopes implied by each broader scope
# + return - The granted and implied scopes
isolated function expandScopes(string[] granted, readonly & map<string[]> scopeHierarchy) returns string[] {
    string[] scopes = [...granted];
    int next = 0;
    while next < scopes.length() {
        foreach string impliedScope in scopeHierarchy[scopes[next]] ?: [] {
            if scopes.indexOf(impliedScope) is () {
                scopes.push(impliedScope);
            }
        }
        next += 1;
    }
    return scopes;
}

isolated function union(string[] first, string[] second) returns string[] {
    string[] result = [...first];
    foreach string scope in second {
        if result.indexOf(scope) is () {
            result.push(scope);
        }
    }
    return result;
}

# Holds the protected resource metadata of the MCP services attached to one listener, keyed by
# the resource path appended to the well-known prefix.
isolated class ProtectedResourceMetadataRegistry {
    private map<readonly & ProtectedResourceMetadata> documents = {};

    isolated function add(string path, readonly & ProtectedResourceMetadata metadata) returns Error? {
        lock {
            if self.documents.hasKey(path) {
                return error ServerError(string `Protected resource metadata is already published for '${
                    metadata.'resource}' on this listener`);
            }
            self.documents[path] = metadata;
        }
    }

    isolated function remove(string path) {
        lock {
            _ = self.documents.removeIfHasKey(path);
        }
    }

    isolated function get(string path) returns (readonly & ProtectedResourceMetadata)? {
        lock {
            return self.documents[path];
        }
    }
}

# Creates the service that publishes protected resource metadata under
# `/.well-known/oauth-protected-resource`.
#
# + registry - Metadata documents of the services attached to the listener
# + host - Virtual host on which the metadata service is published
# + return - The metadata service
isolated function createProtectedResourceMetadataService(ProtectedResourceMetadataRegistry registry, string host)
        returns http:Service {
    return @http:ServiceConfig {
        host,
        cors: {allowOrigins: ["*"], allowMethods: ["GET"]}
    } isolated service object {
        isolated resource function get [string... path]() returns ProtectedResourceMetadata|http:NotFound {
            string resourcePath = path.length() == 0 ? "" : "/" + string:'join("/", ...path);
            ProtectedResourceMetadata? metadata = registry.get(resourcePath);
            return metadata ?: http:NOT_FOUND;
        }
    };
}

# Creates the `403` challenge for an `InsufficientScopeError` returned by a tool or handler.
#
# + authenticator - The service's authenticator, if the service uses an `mcp:OAuthProtectedResourceConfig`
# + scopeError - The error carrying the scopes the operation needs
# + return - The `403 Forbidden` response, or `500` when the error names an invalid scope
isolated function insufficientScopeFor(ServerAuthenticator? authenticator, InsufficientScopeError scopeError)
        returns http:Forbidden|http:InternalServerError {
    string[] scopes = scopeError.detail().scopes;
    // A scope that cannot appear in a challenge is a defect in the tool, not in the caller's token.
    Error? invalidScope = checkScopes(scopes, "an InsufficientScopeError");
    if invalidScope is Error {
        log:printError("Tool requested an invalid scope", invalidScope);
        return <http:InternalServerError>{
            body: createJsonRpcError(INTERNAL_ERROR, "Invalid scope requested by the tool")
        };
    }
    return authenticator is ServerAuthenticator ? authenticator.insufficientScope(scopes)
        : insufficientScopeResponse(scopes, ());
}

# Returns the principal a session is bound to: the issuer, the client and the subject of the token.
# A user signed in through two clients is two principals, so neither client can use the other's
# sessions. The key is a JSON array with `null` for a component the token does not name, so a
# subject and a client with the same identifier, or identifiers of different issuers, cannot collide.
#
# + authContext - The authenticated caller
# + return - The principal, or nil when the token names neither a client nor a subject
isolated function principalOf(AuthContext authContext) returns string? {
    string? clientId = authContext.clientId;
    string? subject = authContext.subject;
    if clientId is () && subject is () {
        return;
    }
    return [authContext.issuer, clientId, subject].toJsonString();
}

# Returns whether a caller may use a session.
#
# + owner - Principal that created the session, if it was created by an authenticated caller
# + authContext - The authenticated caller of the current request
# + return - `true` when the session is unowned or owned by the caller
isolated function isSessionOwner(string? owner, AuthContext? authContext) returns boolean =>
    owner is () || (authContext is AuthContext && principalOf(authContext) == owner);
