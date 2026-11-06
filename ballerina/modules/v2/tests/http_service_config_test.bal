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

// `mcp:HttpServiceConfig` mirrors `http:HttpServiceConfig` field by field. Spreading one into the
// other only compiles while both have the same fields, so a setting added to the HTTP module and not
// mirrored here fails this file's compilation, and `toHttpServiceConfig` covers the other direction.
isolated function fromHttpServiceConfig(http:HttpServiceConfig httpConfig) returns HttpServiceConfig =>
    {...httpConfig};

@test:Config {}
function testHttpServiceConfigMirrorsHttpModule() returns error? {
    http:HttpServiceConfig httpConfig = {
        cors: {allowOrigins: ["https://app.example.com"]},
        mediaTypeSubtypePrefix: "vnd.example",
        treatNilableAsOptional: false,
        laxDataBinding: true,
        auth: [{jwtValidatorConfig: {issuer: "https://login.example.com"}}]
    };
    HttpServiceConfig mcpConfig = fromHttpServiceConfig(httpConfig);
    test:assertEquals(mcpConfig.cors.allowOrigins, ["https://app.example.com"]);

    // Every setting reaches the dispatcher unchanged, including plain HTTP listener auth. The records
    // hold a `typedesc` field, so they are compared field by field rather than as values.
    http:HttpServiceConfig dispatcherConfig =
            toHttpServiceConfig({info: {name: "x", version: "1"}, httpConfig: mcpConfig}, ());
    test:assertEquals(dispatcherConfig.cors, httpConfig.cors);
    test:assertEquals(dispatcherConfig.mediaTypeSubtypePrefix, "vnd.example");
    test:assertFalse(dispatcherConfig.treatNilableAsOptional);
    test:assertTrue(dispatcherConfig.laxDataBinding);
    test:assertEquals(dispatcherConfig.auth, httpConfig.auth);
}
