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

import ballerina/jwt;

# Client authentication method names, as they appear in authorization server metadata.
# `client_secret_basic` and `client_secret_post` are covered by `ClientSecretAuthMethod`.
const METHOD_PRIVATE_KEY_JWT = "private_key_jwt";
const METHOD_NONE = "none";
# The `error` parameter value a resource server uses to report a scope deficiency.
const ERROR_INSUFFICIENT_SCOPE = "insufficient_scope";

# Grant type used by this module.
const GRANT_CLIENT_CREDENTIALS = "client_credentials";
const GRANT_AUTHORIZATION_CODE = "authorization_code";

# Validates an `OAuthConfig`.
#
# + config - The configuration to validate
# + return - An `OAuthConfigError` describing the first problem found, or `()` if usable
isolated function validateConfig(OAuthConfig config) returns Error? {
    ClientCredentialsGrant|AuthorizationCodeGrant grant = config.grant;
    if grant is ClientCredentialsGrant {
        return validateClientCredentialsConfig(grant.clientConfig);
    }
    check validateAuthorizationCodeConfig(grant);
}

isolated function validateClientCredentialsConfig(ClientCredentialsClientConfig oauthClient)
        returns Error? {
    if oauthClient is PreRegisteredClientCredentialsConfig {
        if oauthClient.clientId.trim() == "" {
            return error OAuthConfigError("'clientId' must not be empty.");
        }
        check validateHttpsUrl(oauthClient.issuer, "issuer", false, false);
        check validateClientAuthentication(oauthClient.clientAuth);
        return;
    }

    check validateHttpsUrl(oauthClient.url, "url", true, true);
    check validateClientAuthentication(oauthClient.clientAuth);
    return;
}

isolated function validateAuthorizationCodeConfig(AuthorizationCodeGrant grant) returns Error? {
    AuthorizationCodeClientConfig oauthClient = grant.clientConfig;
    if oauthClient is PreRegisteredAuthorizationCodeConfig {
        if oauthClient.clientId.trim() == "" {
            return error OAuthConfigError("'clientId' must not be empty.");
        }
        check validateHttpsUrl(oauthClient.issuer, "issuer", false, false);
    } else {
        check validateHttpsUrl(oauthClient.url, "url", true, true);
    }
    ClientAuth? clientAuth = oauthClient?.clientAuth;
    if clientAuth is ClientAuth {
        check validateClientAuthentication(clientAuth);
    }
    check validateRedirectUri(grant.redirectUri);
}

isolated function validateRedirectUri(string redirectUri) returns Error? {
    UrlParts|Error parsed = parseAbsoluteUrl(redirectUri);
    if parsed is Error {
        return error OAuthConfigError("'redirectUri' must be an absolute HTTP or HTTPS URL.", parsed);
    }
    if parsed.scheme == "https" {
        return;
    }
    string authority = parsed.origin.substring("http://".length());
    if authority == "localhost" || authority.startsWith("localhost:") ||
            authority == "127.0.0.1" || authority.startsWith("127.0.0.1:") ||
            authority == "[::1]" || authority.startsWith("[::1]:") {
        return;
    }
    return error OAuthConfigError(
        "'redirectUri' must use HTTPS unless it addresses a loopback interface.");
}

# Validates an HTTPS configuration URL.
#
# + value - URL to validate
# + fieldName - Configuration field used in error messages
# + requirePath - Whether the URL must identify a non-root path
# + allowQuery - Whether a query component is allowed
# + return - An `OAuthConfigError` if the URL is invalid, or `()`
isolated function validateHttpsUrl(string value, string fieldName, boolean requirePath,
        boolean allowQuery)
        returns Error? {
    UrlParts|Error parsed = parseAbsoluteUrl(value);
    if parsed is Error {
        return error OAuthConfigError(string `'${fieldName}' must be an absolute HTTPS URL.`, parsed);
    }
    if parsed.scheme != "https" {
        return error OAuthConfigError(string `'${fieldName}' must use HTTPS. Found '${value}'.`);
    }
    if requirePath && (parsed.path == "" || parsed.path == "/") {
        return error OAuthConfigError(string `'${fieldName}' must include a non-root document path. ` +
            string `Found '${value}'.`);
    }
    if !allowQuery && parsed.query != "" {
        return error OAuthConfigError(string `'${fieldName}' must not include a query component. ` +
            string `Found '${value}'.`);
    }
}

# Validates token endpoint client authentication configuration.
#
# + clientAuth - Client authentication configuration to validate
# + return - An `OAuthConfigError` if the configuration is invalid, or `()`
isolated function validateClientAuthentication(ClientAuth clientAuth) returns Error? {
    if clientAuth is ClientSecretConfig {
        if clientAuth.clientSecret == "" {
            return error OAuthConfigError("'clientSecret' must not be empty.");
        }
        return;
    }
    jwt:SigningAlgorithm algorithm = clientAuth.signatureConfig.algorithm;
    if algorithm != jwt:RS256 && algorithm != jwt:RS384 && algorithm != jwt:RS512 {
        return error OAuthConfigError(string `'private_key_jwt' requires an RSA signing algorithm. ` +
            string `Found '${algorithm}'.`);
    }
    var keyConfig = clientAuth.signatureConfig?.config;
    if keyConfig is () || keyConfig is string {
        return error OAuthConfigError(
            "'private_key_jwt' requires asymmetric private key or key store configuration.");
    }
    string? keyId = clientAuth?.keyId;
    if keyId is string && keyId.trim() == "" {
        return error OAuthConfigError("'keyId' must not be empty when provided.");
    }
}

# Returns the metadata name of a client authentication method.
#
# + clientAuth - The configured client authentication, or `()` for a public client
# + return - The name as it appears in `token_endpoint_auth_methods_supported`
isolated function clientAuthMethodName(ClientAuth? clientAuth) returns string {
    if clientAuth is ClientSecretConfig {
        return clientAuth.authMethod;
    }
    if clientAuth is PrivateKeyJwtConfig {
        return METHOD_PRIVATE_KEY_JWT;
    }
    return METHOD_NONE;
}

# Checks that the authorization server accepts the configured client authentication method.
#
# + grant - Configured grant and token endpoint authentication
# + metadata - Validated authorization server metadata
# + return - An `OAuthConfigError` if the method is not supported, or `()`
isolated function validateGrantAndClientAuthSupported(ClientCredentialsGrant|AuthorizationCodeGrant grant,
        AuthorizationServerMetadata metadata) returns Error? {
    string expectedGrant = grant is ClientCredentialsGrant
        ? GRANT_CLIENT_CREDENTIALS
        : GRANT_AUTHORIZATION_CODE;
    // RFC 8414 section 2 defaults omitted grant types to authorization_code and implicit.
    string[] advertisedGrantTypes = metadata.grant_types_supported ?:
        [GRANT_AUTHORIZATION_CODE, "implicit"];
    if advertisedGrantTypes.indexOf(expectedGrant) is () {
        return error OAuthConfigError(string `Authorization server '${metadata.issuer}' does not ` +
            string `advertise support for the '${expectedGrant}' grant.`);
    }
    if grant is AuthorizationCodeGrant {
        string[]? responseTypes = metadata.response_types_supported;
        if responseTypes is () || responseTypes.indexOf("code") is () {
            return error OAuthConfigError(string `Authorization server '${metadata.issuer}' does not ` +
                string `advertise support for the 'code' response type.`);
        }
        string[]? pkceMethods = metadata.code_challenge_methods_supported;
        if pkceMethods is () || pkceMethods.indexOf("S256") is () {
            return error OAuthConfigError(string `Authorization server '${metadata.issuer}' does not ` +
                string `advertise support for the PKCE 'S256' challenge method.`);
        }
    }
    ClientAuth? clientAuth = grantClientAuth(grant);
    string[]? advertisedMethods = metadata.token_endpoint_auth_methods_supported;
    // RFC 8414 section 2 defaults an omitted token_endpoint_auth_methods_supported value
    // to client_secret_basic.
    string[] supported = advertisedMethods ?: [CLIENT_SECRET_BASIC];
    string configured = clientAuthMethodName(clientAuth);
    if supported.indexOf(configured) is () {
        return error OAuthConfigError(string `Authorization server '${metadata.issuer}' does not ` +
            string `support the '${configured}' client authentication method. It supports: ` +
            string `${string:'join(", ", ...supported)}.`);
    }
    string[]? algorithms = metadata.token_endpoint_auth_signing_alg_values_supported;
    // RFC 8414 section 2 requires this metadata whenever either JWT client
    // authentication method is advertised, even when the current client uses a
    // different authentication method.
    if (supported.indexOf(METHOD_PRIVATE_KEY_JWT) is int ||
            supported.indexOf("client_secret_jwt") is int) &&
            (algorithms is () || algorithms.length() == 0) {
        return error OAuthConfigError(string `Authorization server '${metadata.issuer}' advertises ` +
            string `JWT client authentication without any client assertion signing algorithms.`);
    }
    if clientAuth is PrivateKeyJwtConfig && algorithms is string[] {
        string configuredAlgorithm = clientAuth.signatureConfig.algorithm;
        if algorithms.indexOf(configuredAlgorithm) is () {
            return error OAuthConfigError(string `Authorization server '${metadata.issuer}' does not ` +
                string `support the configured client assertion signing algorithm ` +
                string `'${configuredAlgorithm}'. It supports: ${string:'join(", ", ...algorithms)}.`);
        }
    }
    return;
}

isolated function grantClientAuth(ClientCredentialsGrant|AuthorizationCodeGrant grant)
        returns ClientAuth? {
    if grant is ClientCredentialsGrant {
        return grant.clientConfig.clientAuth;
    }
    return grant.clientConfig?.clientAuth;
}

# Resolves the client identifier to use with an authorization server. A Client ID Metadata
# Document URL is used only when the server advertises support for it.
#
# + oauthClient - Client registration and authentication configuration
# + metadata - Validated authorization server metadata
# + return - The client identifier, or an `OAuthConfigError` if it cannot be used with this server
isolated function resolveClientId(ClientCredentialsClientConfig|AuthorizationCodeClientConfig oauthClient,
        AuthorizationServerMetadata metadata)
        returns string|Error {
    if oauthClient is PreRegisteredClientCredentialsConfig ||
            oauthClient is PreRegisteredAuthorizationCodeConfig {
        return oauthClient.clientId;
    }
    boolean cimdSupported = metadata.client_id_metadata_document_supported ?: false;
    if !cimdSupported {
        return error OAuthConfigError(string `Authorization server '${metadata.issuer}' does not ` +
            string `advertise 'client_id_metadata_document_supported', so the Client ID ` +
            string `Metadata Document at '${oauthClient.url}' cannot be used.`);
    }
    return oauthClient.url;
}
