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
import ballerina/log;
import ballerina/time;

// Default values of mock authorization server.
public int HTTPS_SERVER_PORT = 9445;
int TOKEN_VALIDITY_PERIOD = 3600; // in seconds

// Credentials of the mock authorization server.
string USERNAME = "admin";
string PASSWORD = "admin";

string[] accessTokenStore = ["56ede317-4511-44b4-8579-a08f094ee8c5"];

// The mock authorization server, which is capable of issuing access tokens with related to the grant type and
// also of refreshing the already-issued access tokens. Also, capable of introspection the access tokens.
listener http:Listener sts1 = new (HTTPS_SERVER_PORT, {
    secureSocket: {
        key: {
            certFile: "tests/resources/certFiles/public.crt",
            keyFile: "tests/resources/certFiles/private.key"
        }
    }
});

service /oauth2 on sts1 {

    function init() {
        log:printInfo("STS started on port: " + HTTPS_SERVER_PORT.toString() + " (HTTPS)");
    }

    resource function post introspect(http:Request req) returns json|http:Unauthorized|http:BadRequest {
        var authorizationHeader = req.getHeader("Authorization");
        if authorizationHeader is string {
            if isAuthorizedIntrospectionClient(authorizationHeader) {
                var payload = req.getTextPayload();
                if payload is string {
                    string[] params = re `&`.split(payload);
                    string token = "";
                    string tokenTypeHint = "";
                    foreach string param in params {
                        if param.includes("token=") {
                            // Extract everything after "token="
                            int? idx = param.indexOf("=");
                            if idx is int {
                                token = param.substring(idx + 1);
                            }
                        } else if param.includes("token_type_hint=") {
                            int? idx = param.indexOf("=");
                            if idx is int {
                                tokenTypeHint = param.substring(idx + 1);
                            }
                        }
                    }
                    return prepareIntrospectionResponse(token, tokenTypeHint);
                }
                string description = "The request is malformed and failed to retrieve the text payload.";
                return createInvalidRequest(description);
            }
            string description = "Client authentication failed due to unknown client.";
            return createInvalidClient(description);
        }
        string description = "Client authentication failed since no client authentication included.";
        return createInvalidClient(description);
    }
}

function prepareIntrospectionResponse(string accessToken, string tokenTypeHint) returns json {
    [int, decimal] currentTime = time:utcNow();
    foreach string token in accessTokenStore {
        if token == accessToken {
            json response = {
                "active": true,
                "scope": "read write dolphin",
                "client_id": "l238j323ds-23ij4",
                "username": "jdoe",
                "token_type": "token_type",
                "exp": currentTime[0] + TOKEN_VALIDITY_PERIOD,
                "iat": 1419350238,
                "nbf": 1419350238,
                "sub": "Z5O3upPC88QrAjx00dis",
                "aud": "https://protected.example.net/resource",
                "iss": "https://server.example.com/",
                "jti": "JlbmMiOiJBMTI4Q0JDLUhTMjU2In",
                "extension_field": "twenty-seven",
                "scp": "admin"
            };
            return response;
        }
    }
    json response = {"active": false};
    return response;
}

function isAuthorizedIntrospectionClient(string authorizationHeader) returns boolean {
    string usernamePassword = USERNAME + ":" + PASSWORD;
    string expectedAuthorizationHeader = "Basic " + usernamePassword.toBytes().toBase64();
    return authorizationHeader == expectedAuthorizationHeader;
}

function createInvalidClient(string description) returns http:Unauthorized =>
    {
        body: {
            "error": "invalid_client",
            "error_description": description
        }
    };

function createUnauthorizedClient(string description) returns http:Unauthorized =>
    {
        body: {
            "error": "unauthorized_client",
            "error_description": description
        }
    };

function createInvalidRequest(string description) returns http:BadRequest =>
    {
        body: {
            "error": "invalid_request",
            "error_description": description
        }
    };
