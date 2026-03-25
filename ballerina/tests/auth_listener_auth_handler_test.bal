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
import ballerina/test;

const string BEARER_HEADER_1 = "Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJPbmxpbmUgSldUIEJ1aWxkZXIiL" +
                "CJpYXQiOjE3NzM2NzM5OTgsImV4cCI6bnVsbCwiYXVkIjoiIiwic3ViIjoiZDg4YyIsInNjb3BlIjoiZ2V0X3dlYXRoZXJf" +
                "Zm9yZWNhc3QgcmVhZF93ZWF0aGVyX2ZvcmVjYXN0In0.CA_9_kAUsWxSXJ5Lv531_-lq8mfvrodmBXVZvVfPVLs";
const string BEARER_HEADER_2 = "Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJPbmxpbmUgSldUIEJ1aWxkZXIiLCJpYXQiOjE3" +
                "NzM2NzM5OTgsImV4cCI6MjIxNTUyMzU5OCwiYXVkIjoiIiwic3ViIjoiZDg4YyIsInNjb3BlIjoiZ2V0X3dlYXRoZXJfZm9yZWNhc3Q" +
                "gcmVhZF93ZWF0aGVyX2ZvcmVjYXN0In0.FRstJOV8Ay9QK8WT18_2rdoaAI78kmgfsOk_qz2Dsa4";
const string TRUSTSTORE_PATH = "tests/resources/certFiles/ballerinaTruststore.p12";

@test:Config {}
isolated function testGetListenerAuthConfig() {
    http:JwtValidatorConfigWithScopes authListenerConfig =
        {
            jwtValidatorConfig: {
                username: "d88c",
                signatureConfig: {
                    jwksConfig: {
                        url: "http://localhost:9763/t/carbon.super/oauth2/jwks"
                    }
                }
            },
            scopes: ["get_weather_forecast", "read_weather_forecast"]
        };
    http:ListenerAuthConfig[] result = getListenerAuthConfig([authListenerConfig], ["get", "write"]);
    http:JwtValidatorConfigWithScopes jwtValidatorConfigWithScopes = <http:JwtValidatorConfigWithScopes>result[0];
    test:assertTrue(jwtValidatorConfigWithScopes.scopes == ["get","write"]);
}

@test:Config {}
isolated function testTokenExpired() {
    http:JwtValidatorConfigWithScopes authListenerConfig =
        {
            jwtValidatorConfig: {
                username: "d88c"
            },
            scopes: ["get_weather_forecast", "read_weather_forecast"]
        };
    http:Unauthorized|http:Forbidden|string? result = authenticateResource([authListenerConfig], BEARER_HEADER_1);
    test:assertTrue(result is http:Unauthorized);
    if result is http:Unauthorized {
        http:Unauthorized value = <http:Unauthorized>result;
        test:assertTrue(value?.body.toString().startsWith("JWT validation failed."));
    }
}

@test:Config {}
isolated function testValidJwtToken() {
    http:JwtValidatorConfigWithScopes authListenerConfig =
        {
            jwtValidatorConfig: {
                username: "d88c"
            },
            scopes: ["get_weather_forecast", "read_weather_forecast"]
        };
    http:Unauthorized|http:Forbidden|string? result = authenticateResource([authListenerConfig], BEARER_HEADER_2);
    test:assertEquals(result, "d88c");
}

@test:Config {}
function testListenerOAuth2HandlerAuthSuccess() {
    http:OAuth2IntrospectionConfigWithScopes authListenerConfig =
        {
            oauth2IntrospectionConfig: {
                url: "https://localhost:" + HTTPS_SERVER_PORT.toString() + "/oauth2/introspect",
                tokenTypeHint: "access_token",
                clientConfig: {
                    customHeaders: {"Authorization": "Basic YWRtaW46YWRtaW4="},
                    secureSocket: {
                        cert: "tests/resources/certFiles/public.crt"
                    }
                }
            },
            scopes: ["write", "update"]
        };
    string oauth2Token = "56ede317-4511-44b4-8579-a08f094ee8c5";
    string headerValue = http:AUTH_SCHEME_BEARER + " " + oauth2Token;
    http:Unauthorized|http:Forbidden|string? auth1 = authenticateResource([authListenerConfig], headerValue);
    test:assertEquals(auth1, "Z5O3upPC88QrAjx00dis");
}

@test:Config {}
function testFileUserStore() {
    http:FileUserStoreConfigWithScopes authListenerConfig = {
            fileUserStoreConfig: {},
            scopes: ["read", "write"]
        };
    string basicAuthToken = "YWRtaW46YWRtaW4=";
    string headerValue = http:AUTH_SCHEME_BASIC + " " + basicAuthToken;
    http:Unauthorized|http:Forbidden|string? auth1 = authenticateResource([authListenerConfig], headerValue);
    test:assertEquals(auth1, "admin");
}
