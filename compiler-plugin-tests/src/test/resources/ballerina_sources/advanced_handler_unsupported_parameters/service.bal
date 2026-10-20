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
import ballerina/mcp;

@mcp:StreamableHttpServiceConfig {
    info: {name: "subscribe-extra-parameter", version: "1.0.0"}
}
service mcp:StreamableHttpAdvancedService /extra on new mcp:StreamableHttpListener(9343) {
    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params)
            returns mcp:CallToolResult|mcp:InputRequiredResult|mcp:ServerError {
        return {resultType: "complete", content: []};
    }

    remote isolated function onSubscribe(mcp:SubscriptionFilter notifications, mcp:HttpSession? session)
            returns stream<mcp:JsonRpcNotification, error?>|mcp:ServerError {
        return new stream<mcp:JsonRpcNotification, error?>();
    }
}

@mcp:StreamableHttpServiceConfig {
    info: {name: "subscribe-without-filter", version: "1.0.0"}
}
service mcp:StreamableHttpAdvancedService /noFilter on new mcp:StreamableHttpListener(9344) {
    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params)
            returns mcp:CallToolResult|mcp:InputRequiredResult|mcp:ServerError {
        return {resultType: "complete", content: []};
    }

    remote isolated function onSubscribe(http:Headers headers)
            returns stream<mcp:JsonRpcNotification, error?>|mcp:ServerError {
        return new stream<mcp:JsonRpcNotification, error?>();
    }
}

// The first page is listed without a cursor, so the cursor must be nilable.
@mcp:StreamableHttpServiceConfig {
    info: {name: "required-cursor", version: "1.0.0"}
}
service mcp:StreamableHttpAdvancedService /requiredCursor on new mcp:StreamableHttpListener(9345) {
    remote isolated function onListTools(mcp:Cursor cursor) returns mcp:ListToolsResult|mcp:ServerError {
        return {tools: []};
    }

    remote isolated function onCallTool(mcp:CallToolParams params)
            returns mcp:CallToolResult|mcp:InputRequiredResult|mcp:ServerError {
        return {resultType: "complete", content: []};
    }
}
