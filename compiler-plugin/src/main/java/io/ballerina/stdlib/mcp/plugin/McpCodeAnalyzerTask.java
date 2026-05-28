/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.stdlib.mcp.plugin;

import io.ballerina.compiler.api.symbols.ModuleSymbol;
import io.ballerina.compiler.api.symbols.ServiceDeclarationSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.Package;
import io.ballerina.projects.Project;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.EndpointYamlGenerator;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;

import java.io.IOException;
import java.io.PrintStream;
import java.util.Optional;

import static io.ballerina.stdlib.mcp.plugin.Utils.BALLERINA_ORG;
import static io.ballerina.stdlib.mcp.plugin.Utils.MCP_PACKAGE_NAME;

/**
 * Analysis task that writes an endpoint YAML for each MCP service when the
 * {@code --export-endpoints} build option is enabled.
 */
public class McpCodeAnalyzerTask implements AnalysisTask<SyntaxNodeAnalysisContext> {
    private static final PrintStream outStream = System.out;

    /**
     * Generates the endpoint YAML for the analyzed service when endpoint export is enabled.
     *
     * @param context the syntax node analysis context for the service declaration
     */
    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        if (!isMcpService(context)) {
            return;
        }
        Package currentPackage = context.currentPackage();
        Project project = currentPackage.project();
        BuildOptions buildOptions = project.buildOptions();
        if (isExportEndpoints(buildOptions, context)) {
            EndpointYamlGenerator endpointYamlGeneratorMcp = new EndpointYamlGenerator(context);
            try {
                endpointYamlGeneratorMcp.writeEndpointYaml();
            } catch (IOException e) {
                outStream.println(e);
            }
        }
    }

    /**
     * Checks whether the {@code --export-endpoints} build option is enabled, reporting a warning
     * on Ballerina versions that do not support the option.
     *
     * @param buildOptions the project build options
     * @param context      the analysis context used to report diagnostics
     * @return {@code true} if endpoint export is enabled, {@code false} otherwise
     */
    private boolean isExportEndpoints(BuildOptions buildOptions, SyntaxNodeAnalysisContext context) {
        boolean isExportEndpoints = false;
        // Ensure backward compatibility with older ballerina-lang versions
        try {
            isExportEndpoints = buildOptions.exportEndpoints();
        } catch (NoSuchMethodError e) {
            // Used to catch the buildOption not found error for earlier ballerina versions
            DiagnosticInfo diagnosticInfo = new DiagnosticInfo(
                    "NO_SUCH_METHOD_ERROR",
                    "The `--export-endpoints` build option is not supported in the current ballerina version. " +
                            "Use ballerina 2201.13.3 or higher. " + e.getMessage(),
                    DiagnosticSeverity.WARNING
            );
            context.reportDiagnostic(DiagnosticFactory.createDiagnostic(diagnosticInfo, context.node().location()));
        }
        return isExportEndpoints;
    }

    /**
     * Checks whether the service in the analysis context is bound to a {@code ballerina/mcp} listener.
     *
     * @param context the analysis context
     * @return {@code true} if at least one listener type belongs to the {@code ballerina/mcp} module
     */
    private boolean isMcpService(SyntaxNodeAnalysisContext context) {
        if (!(context.node() instanceof ServiceDeclarationNode)) {
            return false;
        }
        Optional<Symbol> symbol = context.semanticModel().symbol(context.node());
        if (symbol.isEmpty() || !(symbol.get() instanceof ServiceDeclarationSymbol serviceSymbol)) {
            return false;
        }
        return serviceSymbol.listenerTypes().stream().anyMatch(McpCodeAnalyzerTask::isMcpListenerType);
    }

    private static boolean isMcpListenerType(TypeSymbol listenerType) {
        if (listenerType.typeKind() == TypeDescKind.UNION) {
            return ((UnionTypeSymbol) listenerType).memberTypeDescriptors().stream()
                    .filter(t -> t instanceof TypeReferenceTypeSymbol)
                    .map(t -> (TypeReferenceTypeSymbol) t)
                    .anyMatch(t -> t.getModule().map(McpCodeAnalyzerTask::isMcpModule).orElse(false));
        }
        if (listenerType.typeKind() == TypeDescKind.TYPE_REFERENCE) {
            return ((TypeReferenceTypeSymbol) listenerType).typeDescriptor().getModule()
                    .map(McpCodeAnalyzerTask::isMcpModule).orElse(false);
        }
        return false;
    }

    private static boolean isMcpModule(ModuleSymbol moduleSymbol) {
        return moduleSymbol.getName().map(MCP_PACKAGE_NAME::equals).orElse(false)
                && BALLERINA_ORG.equals(moduleSymbol.id().orgName());
    }
}
