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

package io.ballerina.stdlib.mcp.plugin.v2.diagnostics;

import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;

import static io.ballerina.tools.diagnostics.DiagnosticSeverity.ERROR;
import static io.ballerina.tools.diagnostics.DiagnosticSeverity.WARNING;

/**
 * Compilation errors in the Ballerina mcp package.
 */
public enum CompilationDiagnostic {
    UNABLE_TO_GENERATE_SCHEMA_FOR_FUNCTION(DiagnosticMessage.ERROR_101, DiagnosticCode.MCP_201, ERROR),
    INVALID_PARAMETER_TYPE(DiagnosticMessage.ERROR_102, DiagnosticCode.MCP_202, ERROR),
    SESSION_PARAM_NOT_ALLOWED_IN_STATELESS_MODE(DiagnosticMessage.ERROR_104, DiagnosticCode.MCP_204, ERROR),
    META_PARAM_MUST_BE_OPTIONAL(DiagnosticMessage.ERROR_106, DiagnosticCode.MCP_206, ERROR),
    DUPLICATE_PARAMETER(DiagnosticMessage.ERROR_107, DiagnosticCode.MCP_207, ERROR),
    INVALID_HEADER_PARAMETER_TYPE(DiagnosticMessage.ERROR_108, DiagnosticCode.MCP_208, ERROR),
    ADVANCED_SERVICE_MISSING_METHOD(DiagnosticMessage.ERROR_110, DiagnosticCode.MCP_210, ERROR),
    ADVANCED_METHOD_PARAMS(DiagnosticMessage.ERROR_111, DiagnosticCode.MCP_211, ERROR),
    ADVANCED_INVALID_RETURN_TYPE(DiagnosticMessage.ERROR_112, DiagnosticCode.MCP_212, ERROR),
    ADVANCED_UNKNOWN_REMOTE_METHOD(DiagnosticMessage.ERROR_113, DiagnosticCode.MCP_213, ERROR),
    REQUIRED_SESSION_IN_MODERN_MODE(DiagnosticMessage.ERROR_114, DiagnosticCode.MCP_214, ERROR),
    INVALID_MCP_ARGUMENT_TYPE(DiagnosticMessage.ERROR_115, DiagnosticCode.MCP_215, ERROR),
    INVALID_MCP_ARGUMENT_HEADER_NAME(DiagnosticMessage.ERROR_116, DiagnosticCode.MCP_216, ERROR),
    DUPLICATE_MCP_ARGUMENT_HEADER_NAME(DiagnosticMessage.ERROR_117, DiagnosticCode.MCP_217, ERROR),
    MCP_ARGUMENT_WITH_EXPLICIT_SCHEMA(DiagnosticMessage.ERROR_118, DiagnosticCode.MCP_218, ERROR),
    UNSUPPORTED_FORM_FIELD(DiagnosticMessage.ERROR_119, DiagnosticCode.MCP_219, ERROR),
    FORM_SCHEMA_TYPE_NOT_STATIC(DiagnosticMessage.ERROR_120, DiagnosticCode.MCP_220, ERROR),
    UNSTRUCTURED_OUTPUT_WITH_OUTPUT_SCHEMA(DiagnosticMessage.ERROR_121, DiagnosticCode.MCP_221, ERROR),
    UNABLE_TO_GENERATE_OUTPUT_SCHEMA(DiagnosticMessage.ERROR_122, DiagnosticCode.MCP_222, ERROR),
    REQUIRED_SESSION_IN_AUTO_MODE(DiagnosticMessage.WARNING_102, DiagnosticCode.MCP_WARNING_202, WARNING),
    OPTIONAL_SESSION_IN_MODERN_MODE(DiagnosticMessage.WARNING_103, DiagnosticCode.MCP_WARNING_203, WARNING),
    OPTIONAL_SESSION_IN_AUTO_MODE(DiagnosticMessage.WARNING_104, DiagnosticCode.MCP_WARNING_204, WARNING);

    private final String diagnostic;
    private final String diagnosticCode;
    private final DiagnosticSeverity diagnosticSeverity;

    CompilationDiagnostic(DiagnosticMessage message, DiagnosticCode diagnosticCode,
                          DiagnosticSeverity diagnosticSeverity) {
        this.diagnostic = message.getMessage();
        this.diagnosticCode = diagnosticCode.name();
        this.diagnosticSeverity = diagnosticSeverity;
    }

    public static Diagnostic getDiagnostic(CompilationDiagnostic compilationDiagnostic, Location location,
                                           Object... args) {
        DiagnosticInfo diagnosticInfo = new DiagnosticInfo(
                compilationDiagnostic.getDiagnosticCode(),
                compilationDiagnostic.getDiagnostic(),
                compilationDiagnostic.getDiagnosticSeverity());
        return DiagnosticFactory.createDiagnostic(diagnosticInfo, location, args);
    }

    public String getDiagnostic() {
        return diagnostic;
    }

    public String getDiagnosticCode() {
        return diagnosticCode;
    }

    public DiagnosticSeverity getDiagnosticSeverity() {
        return this.diagnosticSeverity;
    }
}
