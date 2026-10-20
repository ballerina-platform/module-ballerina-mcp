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

import ballerina/jballerina.java;

# The input of one round of a basic service tool call: the input responses and request state the
# client sent back on a continuation. Declare it as a tool parameter to have it injected. It is
# empty on the first round and on legacy calls.
public readonly class Context {
    private final map<InputResponse> inputResponses;
    private final string? state;

    isolated function init(map<InputResponse> & readonly inputResponses = {}, string? requestState = ()) {
        self.inputResponses = inputResponses;
        self.state = requestState;
    }

    # Returns the request state the tool returned in the previous round.
    #
    # + return - The request state, as the plain text the tool wrote, or `()` if there is none
    public isolated function requestState() returns string? => self.state;

    # Returns the user's answer to an elicitation.
    #
    # + key - The key of the input request
    # + return - The answer, or `()` if the elicitation was not answered
    public isolated function elicitResult(string key) returns ElicitResult? => self.inputResponses[key];

    # Returns the content the user submitted for a form elicitation.
    #
    # + key - The key of the input request
    # + contentType - The type to convert the content to
    # + return - The content as `contentType`, or `()` if the answer is missing, was not accepted,
    # or does not convert to `contentType`
    public isolated function acceptedContent(string key, typedesc<map<anydata>> contentType = <>)
            returns contentType? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.Context"
    } external;
}

# Builds a form elicitation.
#
# + message - The message to show the user
# + schema - The form schema describing the fields to collect, or a record type whose form schema is
# generated at compile time from its fields and their doc comments
# + return - The input request
public isolated function elicitForm(string message, FormSchema|typedesc<record {}> schema) returns ElicitRequest {
    // The compiler plugin replaces a record type with its form schema, so a typedesc never arrives here.
    if schema is typedesc {
        panic error Error("The form schema of a record type is generated at compile time");
    }
    return {params: {message, requestedSchema: schema.clone()}};
}

# Builds a URL elicitation, which asks the user to open a URL for an out-of-band step.
# Accepting it only means the user agreed to open the URL.
#
# + message - The message to show the user
# + url - The absolute URL the user should open
# + return - The input request
public isolated function elicitUrl(string message, string url) returns ElicitRequest =>
    {params: {mode: "url", message, url}};
