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
import ballerina/time;
import ballerina/uuid;

isolated service class DispatcherService {
    *http:Service;
}

isolated function getDispatcherService(http:HttpServiceConfig httpServiceConfig) returns DispatcherService {
    return @http:ServiceConfig {
        ...httpServiceConfig
    } isolated service object {
        private map<Session> sessionMap = {};
        private ServiceConfiguration? cachedServiceConfig = ();
        private map<Task> taskStore = {};
        private map<CallToolResult & readonly> taskResultStore = {};
        private map<string> taskSessionMap = {};

        isolated resource function delete .(http:Headers headers) returns http:BadRequest|http:Ok|Error {
            http:authenticateResource(self, "delete", []);
            ServiceConfiguration config = check self.getCachedServiceConfiguration();
            SessionMode sessionMode = config.sessionMode;

            if sessionMode == STATELESS {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_REQUEST, "Session deletion not supported in stateless mode")
                };
            }

            string? sessionId = getSessionIdFromHeaders(headers);
            if sessionId is () {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_REQUEST, "Missing session ID header")
                };
            }

            lock {
                if !self.sessionMap.hasKey(sessionId) {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST, string `Invalid session ID: ${sessionId}`)
                    };
                }

                _ = self.sessionMap.remove(sessionId);
            }

            return <http:Ok>{
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    result: {
                        message: string `Session ${sessionId} deleted successfully`
                    }
                }
            };
        }

        isolated resource function post .(@http:Payload JsonRpcMessage request, http:Headers headers)
                returns http:BadRequest|http:NotAcceptable|http:UnsupportedMediaType|http:Accepted|http:Ok|Error {
            http:authenticateResource(self, "post", []);
            http:NotAcceptable|http:UnsupportedMediaType? headerValidationError = validateRequiredHeaders(headers);
            if headerValidationError !is () {
                return headerValidationError;
            }

            if request is JsonRpcRequest {
                return self.processJsonRpcRequest(request, headers);
            }

            if request is JsonRpcNotification {
                return self.processJsonRpcNotification(request);
            }

            return <http:BadRequest>{
                body: createJsonRpcError(INVALID_REQUEST, "Unsupported request type")
            };
        }

        private isolated function getCachedServiceConfiguration() returns ServiceConfiguration|Error {
            lock {
                if self.cachedServiceConfig is () {
                    Service|AdvancedService mcpService = check getMcpServiceFromDispatcher(self);
                    self.cachedServiceConfig = getServiceConfiguration(mcpService);
                }
                return <ServiceConfiguration>self.cachedServiceConfig.clone();
            }
        }

        private isolated function processJsonRpcRequest(JsonRpcRequest request, http:Headers headers)
            returns http:BadRequest|http:Ok|Error {
            match request.method {
                REQUEST_INITIALIZE => {
                    return self.handleInitializeRequest(request, headers);
                }
                REQUEST_LIST_TOOLS => {
                    return self.handleListToolsRequest(request, headers);
                }
                REQUEST_CALL_TOOL => {
                    return self.handleCallToolRequest(request, headers);
                }
                REQUEST_LIST_TASKS => {
                    return self.handleListTasksRequest(request, headers);
                }
                REQUEST_GET_TASK => {
                    return self.handleGetTaskRequest(request, headers);
                }
                REQUEST_GET_TASK_RESULT => {
                    return self.handleGetTaskResultRequest(request, headers);
                }
                REQUEST_CANCEL_TASK => {
                    return self.handleCancelTaskRequest(request, headers);
                }
                _ => {
                    return <http:BadRequest>{
                        body: createJsonRpcError(METHOD_NOT_FOUND, "Method not found", request.id)
                    };
                }
            }
        }

        private isolated function processJsonRpcNotification(JsonRpcNotification notification)
            returns http:Accepted|http:BadRequest {
            if notification.method == NOTIFICATION_INITIALIZED {
                return http:ACCEPTED;
            }

            return <http:BadRequest>{
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    'error: {
                        code: METHOD_NOT_FOUND,
                        message: "Unknown notification method"
                    }
                }
            };
        }

        private isolated function handleInitializeRequest(JsonRpcRequest jsonRpcRequest, http:Headers headers)
            returns http:BadRequest|http:Ok|Error {
            RequestId? id = jsonRpcRequest.id;
            InitializeRequest|error initRequest = jsonRpcRequest.cloneWithType();
            if initRequest is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_REQUEST,
                            string `Invalid request: ${initRequest.message()}`, id)
                };
            }

            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_INITIALIZE);

            string requestedVersion = initRequest.params.protocolVersion;
            string protocolVersion = self.selectProtocolVersion(requestedVersion);

            InitializeResult & readonly initResult = {
                protocolVersion: protocolVersion,
                capabilities: (serviceConfig.options?.capabilities ?: {
                    tools: {}
                }).cloneReadOnly(),
                serverInfo: serviceConfig.info.cloneReadOnly()
            };

            if effectiveSessionMode == STATELESS {
                return <http:Ok>{
                    body: {
                        jsonrpc: JSONRPC_VERSION,
                        id: id,
                        result: initResult
                    }
                };
            }

            string? existingSessionId = getSessionIdFromHeaders(headers);

            lock {
                // If there's an existing session ID and it's already in the map, return error
                if existingSessionId is string && self.sessionMap.hasKey(existingSessionId) {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST,
                                string `Session already initialized: ${existingSessionId}`, id)
                    };
                }

                string newSessionId = uuid:createRandomUuid();
                Session session = new (newSessionId);
                self.sessionMap[newSessionId] = session;

                return <http:Ok>{
                    headers: {[SESSION_ID_HEADER]: newSessionId},
                    body: {
                        jsonrpc: JSONRPC_VERSION,
                        id: id,
                        result: initResult
                    }
                };
            }
        }

        private isolated function handleListToolsRequest(JsonRpcRequest request, http:Headers headers)
            returns http:BadRequest|http:Ok|Error {
            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_LIST_TOOLS);

            string? sessionId = ();

            if effectiveSessionMode == STATEFUL {
                sessionId = getSessionIdFromHeaders(headers);
                if sessionId is () {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST,
                                "Missing session ID header", request.id)
                    };
                }

                lock {
                    if !self.sessionMap.hasKey(sessionId) {
                        return <http:BadRequest>{
                            body: createJsonRpcError(INVALID_REQUEST,
                                    string `Invalid session ID: ${sessionId}`, request.id)
                        };
                    }
                }
            }

            ListToolsResult|error listToolsResult = self.executeOnListTools();
            if listToolsResult is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INTERNAL_ERROR,
                            string `Failed to list tools: ${listToolsResult.message()}`, request.id)
                };
            }

            JsonRpcResponse responseBody = {
                jsonrpc: JSONRPC_VERSION,
                id: request.id,
                result: listToolsResult.cloneReadOnly()
            };

            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: responseBody
            };
        }

        private isolated function handleCallToolRequest(JsonRpcRequest request, http:Headers headers)
            returns http:BadRequest|http:Ok|Error {
            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_CALL_TOOL);

            string? sessionId = ();

            if effectiveSessionMode == STATEFUL {
                sessionId = getSessionIdFromHeaders(headers);
                if sessionId is () {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST,
                                "Missing session ID header", request.id)
                    };
                }

                lock {
                    if !self.sessionMap.hasKey(sessionId) {
                        return <http:BadRequest>{
                            body: createJsonRpcError(INVALID_REQUEST,
                                    string `Invalid session ID: ${sessionId}`, request.id)
                        };
                    }
                }
            }

            CallToolParams|error params = request.params.cloneWithType();
            if params is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Invalid parameters: ${params.message()}`, request.id)
                };
            }

            Session? session;
            lock {
                session = sessionId is string ? self.sessionMap[sessionId] : ();
            }

            if params.task !is () {
                return self.handleTaskAugmentedToolCall(request, params, session, sessionId);
            }

            CallToolResult|error callToolResult = self.executeOnCallTool(params, session);
            if callToolResult is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INTERNAL_ERROR,
                            string `Failed to call tool '${params.name}': ${callToolResult.message()}`, request.id)
                };
            }

            JsonRpcResponse responseBody = {
                jsonrpc: JSONRPC_VERSION,
                id: request.id,
                result: callToolResult.cloneReadOnly()
            };

            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: responseBody
            };
        }

        private isolated function handleTaskAugmentedToolCall(
            JsonRpcRequest request, CallToolParams params, Session? session, string? sessionId
        ) returns http:Ok|Error {
            string taskId = uuid:createRandomUuid();
            string createdAt = time:utcToString(time:utcNow());
            int ttl = params.task?.ttl ?: 3600000;

            lock {
                self.taskStore[taskId] = {
                    taskId: taskId,
                    status: TASK_STATUS_WORKING,
                    ttl: ttl,
                    createdAt: createdAt,
                    lastUpdatedAt: createdAt
                };
                if sessionId is string {
                    self.taskSessionMap[taskId] = sessionId;
                }
            }

            _ = start self.executeTaskAsync(taskId, params.cloneReadOnly(), session, ttl, createdAt);

            CreateTaskResult & readonly createTaskResult = {
                task: {
                    taskId: taskId,
                    status: TASK_STATUS_WORKING,
                    ttl: ttl,
                    createdAt: createdAt,
                    lastUpdatedAt: createdAt
                }
            };
            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: request.id,
                    result: createTaskResult
                }
            };
        }

        private isolated function executeTaskAsync(string taskId, CallToolParams & readonly params,
                Session? session, int ttl, string createdAt) {
            CallToolResult|error callToolResult = self.executeOnCallTool(params, session);
            string completedAt = time:utcToString(time:utcNow());

            if callToolResult is error {
                lock {
                    self.taskStore[taskId] = {
                        taskId: taskId,
                        status: TASK_STATUS_FAILED,
                        statusMessage: callToolResult.message(),
                        ttl: ttl,
                        createdAt: createdAt,
                        lastUpdatedAt: completedAt
                    };
                }
                return;
            }

            CallToolResult & readonly readonlyResult = callToolResult.cloneReadOnly();
            lock {
                self.taskStore[taskId] = {
                    taskId: taskId,
                    status: TASK_STATUS_COMPLETED,
                    ttl: ttl,
                    createdAt: createdAt,
                    lastUpdatedAt: completedAt
                };
                self.taskResultStore[taskId] = readonlyResult;
            }
        }

        private isolated function handleListTasksRequest(JsonRpcRequest request, http:Headers headers)
                returns http:BadRequest|http:Ok|Error {
            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_LIST_TASKS);

            string? sessionId = ();
            if effectiveSessionMode == STATEFUL {
                sessionId = getSessionIdFromHeaders(headers);
                if sessionId is () {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST, "Missing session ID header", request.id)
                    };
                }
                lock {
                    if !self.sessionMap.hasKey(sessionId) {
                        return <http:BadRequest>{
                            body: createJsonRpcError(INVALID_REQUEST,
                                    string `Invalid session ID: ${sessionId}`, request.id)
                        };
                    }
                }
            }

            Task[] taskList;
            lock {
                if sessionId is string {
                    Task[] filtered = [];
                    foreach Task t in self.taskStore {
                        if self.taskSessionMap[t.taskId] == sessionId {
                            filtered.push(t);
                        }
                    }
                    taskList = filtered.clone();
                } else {
                    taskList = self.taskStore.toArray().clone();
                }
            }

            ListTasksResult result = {tasks: taskList};
            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: request.id,
                    result: result.cloneReadOnly()
                }
            };
        }

        private isolated function handleGetTaskRequest(JsonRpcRequest request, http:Headers headers)
                returns http:BadRequest|http:Ok|Error {
            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_GET_TASK);

            string? sessionId = ();
            if effectiveSessionMode == STATEFUL {
                sessionId = getSessionIdFromHeaders(headers);
                if sessionId is () {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST, "Missing session ID header", request.id)
                    };
                }
                lock {
                    if !self.sessionMap.hasKey(sessionId) {
                        return <http:BadRequest>{
                            body: createJsonRpcError(INVALID_REQUEST,
                                    string `Invalid session ID: ${sessionId}`, request.id)
                        };
                    }
                }
            }

            GetTaskParams|error params = request.params.cloneWithType();
            if params is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Invalid parameters: ${params.message()}`, request.id)
                };
            }

            Task? task;
            lock {
                task = self.taskStore[params.taskId].clone();
                if task !is () && sessionId is string && self.taskSessionMap[params.taskId] != sessionId {
                    task = ();
                }
            }
            if task is () {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Task not found: ${params.taskId}`, request.id)
                };
            }

            GetTaskResult|error result = task.cloneWithType();
            if result is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INTERNAL_ERROR,
                            string `Failed to build task result: ${result.message()}`, request.id)
                };
            }
            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: request.id,
                    result: result.cloneReadOnly()
                }
            };
        }

        private isolated function handleGetTaskResultRequest(JsonRpcRequest request, http:Headers headers)
                returns http:BadRequest|http:Ok|Error {
            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_GET_TASK_RESULT);

            string? sessionId = ();
            if effectiveSessionMode == STATEFUL {
                sessionId = getSessionIdFromHeaders(headers);
                if sessionId is () {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST, "Missing session ID header", request.id)
                    };
                }
                lock {
                    if !self.sessionMap.hasKey(sessionId) {
                        return <http:BadRequest>{
                            body: createJsonRpcError(INVALID_REQUEST,
                                    string `Invalid session ID: ${sessionId}`, request.id)
                        };
                    }
                }
            }

            GetTaskResultParams|error params = request.params.cloneWithType();
            if params is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Invalid parameters: ${params.message()}`, request.id)
                };
            }

            Task? task;
            (CallToolResult & readonly)? toolResult;
            lock {
                task = self.taskStore[params.taskId].clone();
                if task !is () && sessionId is string && self.taskSessionMap[params.taskId] != sessionId {
                    task = ();
                }
                toolResult = task !is () ? self.taskResultStore[params.taskId] : ();
            }

            if task is () {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Task not found: ${params.taskId}`, request.id)
                };
            }
            if toolResult is () {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Result not yet available for task: ${params.taskId}`, request.id)
                };
            }
            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: request.id,
                    result: toolResult
                }
            };
        }

        private isolated function handleCancelTaskRequest(JsonRpcRequest request, http:Headers headers)
                returns http:BadRequest|http:Ok|Error {
            ServiceConfiguration serviceConfig = check self.getCachedServiceConfiguration();
            SessionMode effectiveSessionMode = determineEffectiveSessionMode(serviceConfig, headers, REQUEST_CANCEL_TASK);

            string? sessionId = ();
            if effectiveSessionMode == STATEFUL {
                sessionId = getSessionIdFromHeaders(headers);
                if sessionId is () {
                    return <http:BadRequest>{
                        body: createJsonRpcError(INVALID_REQUEST, "Missing session ID header", request.id)
                    };
                }
                lock {
                    if !self.sessionMap.hasKey(sessionId) {
                        return <http:BadRequest>{
                            body: createJsonRpcError(INVALID_REQUEST,
                                    string `Invalid session ID: ${sessionId}`, request.id)
                        };
                    }
                }
            }

            CancelTaskParams|error params = request.params.cloneWithType();
            if params is error {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Invalid parameters: ${params.message()}`, request.id)
                };
            }

            Task? task;
            lock {
                task = self.taskStore[params.taskId].clone();
                if task !is () && sessionId is string && self.taskSessionMap[params.taskId] != sessionId {
                    task = ();
                }
            }
            if task is () {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Task not found: ${params.taskId}`, request.id)
                };
            }
            if task.status == TASK_STATUS_COMPLETED || task.status == TASK_STATUS_FAILED || task.status == TASK_STATUS_CANCELLED {
                return <http:BadRequest>{
                    body: createJsonRpcError(INVALID_PARAMS,
                            string `Task cannot be cancelled in status: ${task.status}`, request.id)
                };
            }

            string cancelledTaskId = task.taskId;
            string? statusMsg = task.statusMessage;
            int? progressPct = task.progressPercent;
            int? pollInterval = task.pollInterval;
            int? taskTtl = task.ttl;
            string taskCreatedAt = task.createdAt;
            string cancelledAt = time:utcToString(time:utcNow());
            lock {
                self.taskStore[params.taskId] = {
                    taskId: cancelledTaskId,
                    status: TASK_STATUS_CANCELLED,
                    statusMessage: statusMsg,
                    progressPercent: progressPct,
                    pollInterval: pollInterval,
                    ttl: taskTtl,
                    createdAt: taskCreatedAt,
                    lastUpdatedAt: cancelledAt
                };
            }

            CancelTaskResult & readonly result = {
                taskId: cancelledTaskId,
                status: TASK_STATUS_CANCELLED,
                statusMessage: statusMsg,
                progressPercent: progressPct,
                pollInterval: pollInterval,
                ttl: taskTtl,
                createdAt: taskCreatedAt,
                lastUpdatedAt: cancelledAt
            };
            return <http:Ok>{
                headers: sessionId is string ? {[SESSION_ID_HEADER]: sessionId} : (),
                body: {
                    jsonrpc: JSONRPC_VERSION,
                    id: request.id,
                    result: result
                }
            };
        }

        private isolated function selectProtocolVersion(string requestedVersion) returns string {
            foreach string supportedVersion in SUPPORTED_PROTOCOL_VERSIONS {
                if supportedVersion == requestedVersion {
                    return requestedVersion;
                }
            }
            return LATEST_PROTOCOL_VERSION;
        }

        private isolated function executeOnListTools() returns ListToolsResult|Error {
            Service|AdvancedService mcpService = check getMcpServiceFromDispatcher(self);
            if mcpService is AdvancedService {
                return invokeOnListTools(mcpService);
            }
            if mcpService is Service {
                return listToolsForRemoteFunctions(mcpService);
            }
            return error DispatcherError("MCP Service is not attached");
        }

        private isolated function executeOnCallTool(CallToolParams params, Session? session)
                returns CallToolResult|Error {
            Service|AdvancedService mcpService = check getMcpServiceFromDispatcher(self);
            if mcpService is AdvancedService {
                return invokeOnCallTool(mcpService, params.cloneReadOnly(), session);
            }
            if mcpService is Service {
                CallToolResult|error result = callToolForRemoteFunctions(mcpService, params.cloneReadOnly(), session);
                if result is error {
                    return error DispatcherError(result.message());
                }
                return result;
            }
            return error DispatcherError("MCP Service is not attached");
        }
    };
}
