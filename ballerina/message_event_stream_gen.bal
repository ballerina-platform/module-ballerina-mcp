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

isolated class MessageEventStreamGenerator {
    
    public isolated function init(stream<http:SseEvent, error?> eventStream) {
        self.externInit(eventStream);
    }

    private isolated function externInit(stream<http:SseEvent, error?> eventStream) = @java:Method {
        'class: "io.ballerina.stdlib.mcp.MessageEventStream",
        name: "initialize"
    } external;

    isolated function getNextData() returns record {|http:SseEvent value;|}?|error? = @java:Method {
        'class: "io.ballerina.stdlib.mcp.MessageEventStream"
    } external;

    public isolated function next() returns record {|JsonRpcMessage value;|}|error? {
        record {|http:SseEvent value;|}? recordVal = check self.getNextData();

        // If End of Stream
        if recordVal is () {
            return ();
        }

        string? data = recordVal.value.data;
        if data is () {
            return error JsonRpcMessageStreamError("Received SSE event without 'data' field in the event stream.");
        }

        json jsonData = check data.fromJsonString();
        JsonRpcMessage rpcResponse = check jsonData.cloneWithType();
        return {
            value: rpcResponse
        };
    };

    public isolated function close() returns error? {
        // check self.eventStream.close();
    }
}
