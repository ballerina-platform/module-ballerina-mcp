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
    ERROR_102("Parameter ''{1}'' in function ''{0}'' has an unsupported type. Supported types are {2}."),
    ERROR_103("HttpSession parameter ''{1}'' in function ''{0}'' must be the first parameter."),
    ERROR_104("HttpSession parameter ''{1}'' in function ''{0}'' is not allowed when sessionMode is 'STATELESS'."),
    ERROR_105("Meta parameter ''{1}'' in function ''{0}'' must be the last parameter."),
    ERROR_106("Request metadata parameter ''{1}'' in function ''{0}'' must be optional " +
            "(e.g., 'mcp:RequestMetaObject?')."),
    ERROR_107("Duplicate parameter ''{1}'' in function ''{0}''. " +
            "Only one parameter of type ''{2}'' is allowed."),
    ERROR_108("Invalid type of header param ''{1}'' in function ''{0}'': expected one of the 'string', 'int', " +
            "'float', 'decimal', 'boolean' types, an array of the above types, or a record which consists of " +
            "the above types."),
    ERROR_110("A service of type 'mcp:StreamableHttpAdvancedService' must define a remote method ''{0}''."),
    ERROR_111("Remote method ''{0}'' in an 'mcp:StreamableHttpAdvancedService' must declare exactly one " +
            "parameter of type 'mcp:CallToolParams'."),
    ERROR_112("Remote method ''{0}'' in an 'mcp:StreamableHttpAdvancedService' must return ''{1}''."),
    ERROR_113("Remote method ''{0}'' is not supported in an 'mcp:StreamableHttpAdvancedService'. " +
            "Only 'onListTools' and 'onCallTool' are allowed."),
    ERROR_114("Required HttpSession parameter ''{0}'' is not supported in modern protocol mode. " +
            "Use explicit application state or select legacy protocol mode."),
    ERROR_115("Parameter ''{1}'' in function ''{0}'' cannot use '@mcp:Argument': expected a non-nilable " +
            "'string', 'int', 'float', 'decimal', or 'boolean' tool argument."),
    ERROR_116("Invalid MCP argument header name ''{2}'' on parameter ''{1}'' in function ''{0}''."),
    ERROR_117("Duplicate MCP argument header name ''{2}'' on parameter ''{1}'' in function ''{0}''."),
    ERROR_118("Function ''{0}'' cannot combine '@mcp:Argument' with an explicitly supplied '@mcp:Tool.schema'."),
    WARNING_102("Required HttpSession parameter ''{0}'' restricts this service to legacy MCP in auto protocol mode."),
    WARNING_103("HttpSession parameter ''{0}'' is always nil for modern MCP requests. " +
            "Remove it or migrate session-dependent behavior to explicit application state."),
    WARNING_104("HttpSession parameter ''{0}'' may be nil for modern MCP requests in auto protocol mode. " +
            "Handle nil explicitly or select legacy protocol mode if this service requires sessions."),
    WARNING_101("The Ballerina version is not supported for endpoints.yaml. " +
            "Try using Ballerina 2201.13.6 or above.");

    private final String message;

    DiagnosticMessage(String message) {
        this.message = message;
    }

    public String getMessage() {
        return this.message;
    }
}
