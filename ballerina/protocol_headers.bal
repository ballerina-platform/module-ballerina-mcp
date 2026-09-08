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
import ballerina/jballerina.java;

isolated function encodeProtocolHeader(string headerValue) returns string = @java:Method {
    'class: "io.ballerina.stdlib.mcp.ProtocolHeaders"
} external;

isolated function decodeProtocolHeader(string headerValue) returns string|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.ProtocolHeaders"
} external;

isolated function toolParameterHeaders(JsonSchema toolSchema, record {} toolArguments) returns map<string>|Error = @java:Method {
    'class: "io.ballerina.stdlib.mcp.ProtocolHeaders"
} external;

isolated function validateToolHeaders(JsonSchema toolSchema, record {} toolArguments, http:Headers requestHeaders)
        returns Error? {
    map<string> expectedHeaders = check toolParameterHeaders(toolSchema, toolArguments);
    foreach var [headerName, expectedValue] in expectedHeaders.entries() {
        string[]|http:HeaderNotFoundError headerValues = requestHeaders.getHeaders(headerName);
        if headerValues is error || headerValues.length() != 1 {
            return error("Missing or duplicate mirrored tool header: " + headerName);
        }
        string decodedValue = check decodeProtocolHeader(headerValues[0]);
        string decodedExpected = check decodeProtocolHeader(expectedValue);
        if decodedValue != decodedExpected {
            return error("Mirrored tool header does not match arguments: " + headerName);
        }
    }
}
