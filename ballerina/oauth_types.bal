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

import ballerina/crypto;
import ballerina/http;
import ballerina/jwt;

# Client authentication method names for a shared secret, as registered by OpenID Connect
# Core 1.0 section 9 and referenced by RFC 8414's `token_endpoint_auth_methods_supported`.
public enum ClientSecretAuthMethod {
    # The secret is sent as HTTP Basic authentication.
    CLIENT_SECRET_BASIC = "client_secret_basic",
    # The secret is sent as parameters in the request body.
    CLIENT_SECRET_POST = "client_secret_post"
}

# Represents client authentication using a shared secret.
#
# + clientSecret - The client secret
# + authMethod - How the secret is sent to the token endpoint
public type ClientSecretConfig record {|
    string clientSecret;
    ClientSecretAuthMethod authMethod = CLIENT_SECRET_BASIC;
|};

# Represents client authentication using a signed JWT assertion (RFC 7523 section 2.2).
#
# + signatureConfig - Signing key for the assertion
# + keyId - `kid` header of the assertion, used by the authorization server to select the
# matching key from the published key set
public type PrivateKeyJwtConfig record {|
    jwt:IssuerSignatureConfig signatureConfig;
    string keyId?;
|};

# Client authentication method names for mutual TLS, as registered by RFC 8705 section 2.
public enum MutualTlsAuthMethod {
    # The certificate is issued by a certificate authority the authorization server trusts,
    # and is bound to the client by a subject or subject alternative name (RFC 8705 section 2.1).
    TLS_CLIENT_AUTH = "tls_client_auth",
    # The certificate is self-signed and registered with the authorization server, for
    # example in the `jwks` or `jwks_uri` of a Client ID Metadata Document (RFC 8705 section 2.2).
    SELF_SIGNED_TLS_CLIENT_AUTH = "self_signed_tls_client_auth"
}

# Represents client authentication using a mutual TLS client certificate (RFC 8705 section 2).
# The certificate is presented only on connections to the token endpoint.
#
# + key - Client certificate and its private key
# + authMethod - How the authorization server binds the certificate to the client
public type MutualTlsConfig record {|
    crypto:KeyStore|http:CertKey key;
    MutualTlsAuthMethod authMethod;
|};

# Represents how the client authenticates itself at the token endpoint.
public type ClientAuth ClientSecretConfig|PrivateKeyJwtConfig|MutualTlsConfig;

# Represents how a client identified by a Client ID Metadata Document authenticates. A shared
# secret cannot be established through a metadata document.
public type CimdClientAuth PrivateKeyJwtConfig|MutualTlsConfig;

# Represents a client that was registered directly with one authorization server. Its
# credentials are bound to that server, which must be listed in the protected resource
# metadata.
#
# + clientId - Client identifier issued by the authorization server
# + issuer - Issuer identifier of the authorization server that registered the client
# + clientAuth - How the client authenticates at the token endpoint. Omit for a public client
public type PreRegisteredClientConfig record {|
    string clientId;
    string issuer;
    ClientAuth clientAuth?;
|};

# Represents a client identified by a Client ID Metadata Document. The document URL is the
# client identifier, and the authorization server is taken from the protected resource
# metadata.
#
# A CIMD client uses `private_key_jwt` or mutual TLS; the authorization server obtains the
# corresponding public key or certificate from the metadata document.
#
# + url - HTTPS URL of the Client ID Metadata Document
# + clientAuth - Key or certificate used to authenticate at the token endpoint. Omit for a
# public client
public type CimdClientConfig record {|
    string url;
    CimdClientAuth clientAuth?;
|};

# Represents the client configurations supported by the authorization code and identity
# assertion grants.
public type OAuthClientConfig PreRegisteredClientConfig|CimdClientConfig;

# Represents a pre-registered client using the client credentials grant, which requires
# client authentication.
#
# + clientAuth - How the client authenticates at the token endpoint
public type PreRegisteredClientCredentialsConfig record {|
    *PreRegisteredClientConfig;
    ClientAuth clientAuth;
|};

# Represents a client identified by a Client ID Metadata Document and using the client
# credentials grant, which requires client authentication.
#
# + clientAuth - Key or certificate used to authenticate the client at the token endpoint
public type CimdClientCredentialsConfig record {|
    *CimdClientConfig;
    CimdClientAuth clientAuth;
|};

# Represents the client configurations supported by the client credentials grant.
public type ClientCredentialsClientConfig
    PreRegisteredClientCredentialsConfig|CimdClientCredentialsConfig;

# Represents the client credentials grant, used for access on the client's own behalf.
#
# + clientConfig - Client identity, registration mode, and token endpoint authentication
public type ClientCredentialsGrant record {|
    ClientCredentialsClientConfig clientConfig;
|};

# Supplies the values an Identity Assertion Provider needs to obtain an ID-JAG for one
# Resource Authorization Server token request.
#
# + audience - Issuer identifier of the Resource Authorization Server; this must be the
# `aud` claim of the ID-JAG
# + resource - Canonical MCP Resource Identifier; when present in the ID-JAG, this must be
# its `resource` claim
# + clientId - Client identifier used with the Resource Authorization Server; this must be
# the ID-JAG's `client_id` claim
# + scopes - Scopes requested for the MCP access token
public type IdentityAssertionContext readonly & record {|
    string audience;
    string 'resource;
    string clientId;
    string[] scopes;
|};

# Obtains a fresh Identity Assertion JWT Authorization Grant (ID-JAG). The application can
# use its existing OpenID Connect session and call `exchangeIdTokenForIdJag`, or integrate a
# provider-specific exchange directly.
#
# The provider is called while the client holds its authorization lock: other requests on
# the same client wait until it returns, and it must not call the same client.
public type IdentityAssertionProvider isolated function (IdentityAssertionContext context)
    returns string|error;

# Represents the Identity Assertion JWT Authorization Grant used by Enterprise-Managed
# Authorization. The resulting ID-JAG is exchanged at the Resource Authorization Server for
# an MCP access token.
#
# + clientConfig - Client identity, registration mode, and token endpoint authentication at
# the Resource Authorization Server
# + assertionProvider - Callback that obtains a fresh ID-JAG for each access-token exchange
public type IdentityAssertionGrant record {|
    OAuthClientConfig clientConfig;
    IdentityAssertionProvider assertionProvider;
|};

# Represents the parameters returned to the client's redirect URI.
#
# + code - Authorization code returned after approval
# + state - State value echoed by the authorization server
# + iss - Authorization server issuer returned according to RFC 9207
# + error - OAuth authorization error returned instead of a code
# + errorDescription - Human-readable description accompanying `error`
public type AuthorizationCallbackParams record {|
    string code?;
    string state?;
    string iss?;
    string 'error?;
    string errorDescription?;
|};

# Directs the user to an authorization URL, for example by printing it or opening a browser.
public type AuthorizationRedirectHandler isolated function (string authorizationUrl) returns error?;

# Waits for the authorization response and returns its redirect parameters.
public type AuthorizationCallbackHandler isolated function () returns AuthorizationCallbackParams|error;

# Represents the authorization code grant. PKCE with `S256` is always used.
#
# + clientConfig - Client identity, registration mode, and optional token endpoint authentication
# + redirectUri - Redirect URI registered for the client
# + redirectHandler - Directs the user to the generated authorization URL
# + callbackHandler - Waits for and returns the authorization response parameters
public type AuthorizationCodeGrant record {|
    OAuthClientConfig clientConfig;
    string redirectUri;
    AuthorizationRedirectHandler redirectHandler;
    AuthorizationCallbackHandler callbackHandler;
|};

# Represents the configuration for MCP authorization (OAuth 2.1).
#
# + grant - How the access token is obtained
# + scopes - Scopes to request. Used only when the `WWW-Authenticate` challenge carries none
# and the protected resource metadata advertises no `scopes_supported`
public type OAuthConfig record {|
    ClientCredentialsGrant|AuthorizationCodeGrant|IdentityAssertionGrant grant;
    string[] scopes?;
|};

# Configures the enterprise Identity Provider (OpenID Provider) used by the token exchange
# helpers, such as `exchangeIdTokenForIdJag`. This registration is independent of the client
# registration represented by `IdentityAssertionGrant.clientConfig`.
#
# + issuer - Issuer identifier of the Identity Provider
# + clientId - Client identifier registered with the Identity Provider
# + clientAuth - Token endpoint authentication, when required by the Identity Provider
# + secureSocket - SSL/TLS related options
# + proxy - Proxy server settings
# + timeout - Maximum time (in seconds) to wait for metadata and token endpoint responses
# + httpVersion - HTTP protocol version used for metadata and token endpoint requests
public type IdentityProviderConfig record {|
    string issuer;
    string clientId;
    ClientAuth clientAuth?;
    http:ClientSecureSocket secureSocket?;
    http:ProxyConfig proxy?;
    decimal timeout = 30;
    http:HttpVersion httpVersion = http:HTTP_1_1;
|};

# Represents the HTTP settings for metadata and token endpoint requests. This configures how
# those requests are made; it is unrelated to `OAuthConfig`, which configures the OAuth client
# itself (client ID, grant, credentials).
#
# + secureSocket - SSL/TLS related options
# + proxy - Proxy server settings
# + timeout - Maximum time(in seconds) to wait for a response before the request times out
# + httpVersion - HTTP protocol version supported by the client
type AuthHttpConfig record {|
    http:ClientSecureSocket secureSocket?;
    http:ProxyConfig proxy?;
    decimal timeout = 30;
    http:HttpVersion httpVersion = http:HTTP_1_1;
|};

# Represents a parsed `Bearer` challenge from a `WWW-Authenticate` response header.
#
# + resourceMetadata - URL of the protected resource metadata document
# + scope - Scopes required for the challenged request
# + errorCode - Value of the `error` parameter, such as `insufficient_scope`
# + errorDescription - Description accompanying `errorCode`
type BearerChallenge record {|
    string resourceMetadata?;
    string scope?;
    string errorCode?;
    string errorDescription?;
|};

# Represents an OAuth 2.0 Protected Resource Metadata document (RFC 9728).
#
# + resource - Canonical URI of the protected resource, sent as the `resource` parameter on
# token requests
# + authorization_servers - Issuer identifiers of authorization servers that can issue
# tokens for this resource
# + scopes_supported - Scopes understood by this resource
# + bearer_methods_supported - Supported ways of presenting a bearer token
# + resource_name - Human readable name of the resource
type ProtectedResourceMetadata record {
    string 'resource;
    string[] authorization_servers;
    string[] scopes_supported?;
    string[] bearer_methods_supported?;
    string resource_name?;
};

# Represents an OAuth 2.0 Authorization Server Metadata document (RFC 8414), which also
# covers OpenID Provider metadata.
#
# + issuer - Issuer identifier
# + authorization_endpoint - Endpoint used to start an authorization code flow
# + token_endpoint - Token endpoint URL
# + scopes_supported - Supported scopes
# + response_types_supported - Supported authorization response types
# + grant_types_supported - Supported `grant_type` values
# + token_endpoint_auth_methods_supported - Supported client authentication methods
# + token_endpoint_auth_signing_alg_values_supported - Signing algorithms accepted for a
# client assertion
# + client_id_metadata_document_supported - Whether the server accepts an HTTPS URL as the
# `client_id`
# + code_challenge_methods_supported - PKCE challenge methods accepted by the server
# + authorization_response_iss_parameter_supported - Whether authorization responses include
# the RFC 9207 `iss` parameter
# + authorization_grant_profiles_supported - Authorization grant profiles implemented by a
# Resource Authorization Server
# + mtls_endpoint_aliases - Endpoints a client using mutual TLS uses in preference to the
# conventional ones (RFC 8705 section 5)
type AuthorizationServerMetadata record {
    string issuer;
    string authorization_endpoint?;
    string token_endpoint;
    string[] scopes_supported?;
    string[] response_types_supported;
    string[] grant_types_supported?;
    string[] token_endpoint_auth_methods_supported?;
    string[] token_endpoint_auth_signing_alg_values_supported?;
    boolean client_id_metadata_document_supported?;
    string[] code_challenge_methods_supported?;
    boolean authorization_response_iss_parameter_supported?;
    string[] authorization_grant_profiles_supported?;
    MtlsEndpointAliases mtls_endpoint_aliases?;
};

# Represents the `mtls_endpoint_aliases` authorization server metadata (RFC 8705 section 5).
#
# + token_endpoint - Token endpoint to use when authenticating with mutual TLS
type MtlsEndpointAliases record {
    string token_endpoint?;
};

// Minimal issuer metadata required by discovery.
type IssuerMetadata record {
    string issuer;
    string token_endpoint;
};

// Identity Provider metadata used for token exchange. Optional capabilities are checked when advertised.
type IdentityProviderMetadata record {
    string issuer;
    string token_endpoint;
    string[] grant_types_supported?;
    string[] token_endpoint_auth_methods_supported?;
    string[] token_endpoint_auth_signing_alg_values_supported?;
    string[] identity_chaining_requested_token_types_supported?;
    MtlsEndpointAliases mtls_endpoint_aliases?;
};

# Represents a successful response from the token endpoint.
#
# + access_token - The issued access token
# + token_type - Token type, normally `Bearer`
# + expires_in - Lifetime of the access token in seconds
# + refresh_token - Refresh token, when issued
# + scope - Scopes granted
type TokenResponse record {
    string access_token;
    string token_type;
    int expires_in?;
    string refresh_token?;
    string scope?;
};

// RFC 8693 token exchange response (section 2.2.1).
type TokenExchangeResponse record {
    string access_token;
    string issued_token_type;
    string token_type;
    int expires_in?;
    string scope?;
};
