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

import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;

import static io.ballerina.tools.diagnostics.DiagnosticSeverity.ERROR;

/**
 * Compilation errors in the Ballerina mcp package.
 */
public enum CompilationDiagnostic {
    UNABLE_TO_GENERATE_SCHEMA_FOR_FUNCTION(DiagnosticMessage.ERROR_101, DiagnosticCode.MCP_101, ERROR),
    INVALID_PARAMETER_TYPE(DiagnosticMessage.ERROR_102, DiagnosticCode.MCP_102, ERROR),
    SESSION_PARAM_MUST_BE_FIRST(DiagnosticMessage.ERROR_103, DiagnosticCode.MCP_103, ERROR),
    SESSION_PARAM_NOT_ALLOWED_IN_STATELESS_MODE(DiagnosticMessage.ERROR_104, DiagnosticCode.MCP_104, ERROR);

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
