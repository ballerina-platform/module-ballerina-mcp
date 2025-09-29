/*
 * Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.stdlib.mcp.plugin.diagnostics;

/**
 * Compilation error messages used in Ballerina mcp package compiler plugin.
 */
public enum DiagnosticMessage {
    ERROR_101("Failed to generate the parameter schema definition for the function ''{0}''." +
            " Specify the parameter schema manually using the `@mcp:McpTool` annotation's parameter field."),
    ERROR_102("Parameter ''{1}'' in function ''{0}'' must be of type 'anydata'. " +
            "Only the first parameter can be of type 'mcp:Session'."),
    ERROR_103("Session parameter ''{1}'' in function ''{0}'' must be the first parameter."),
    ERROR_104("Session parameter ''{1}'' in function ''{0}'' is not allowed when sessionMode is 'STATELESS'.");

    private final String message;

    DiagnosticMessage(String message) {
        this.message = message;
    }

    public String getMessage() {
        return this.message;
    }
}
