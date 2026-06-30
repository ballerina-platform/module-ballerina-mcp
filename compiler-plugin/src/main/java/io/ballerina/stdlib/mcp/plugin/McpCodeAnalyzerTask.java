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

import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.Package;
import io.ballerina.projects.Project;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.Endpoint;
import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.EndpointYamlGenerator;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;

import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import static io.ballerina.stdlib.mcp.plugin.Utils.hasCompilationErrors;
import static io.ballerina.stdlib.mcp.plugin.Utils.isInTestSource;
import static io.ballerina.stdlib.mcp.plugin.Utils.isMcpService;

/**
 * Analysis task that extracts the endpoint metadata of each MCP service when the {@code --export-endpoints} build
 * option is enabled, collecting it for {@link McpEndpointArtifactTask} to write to a single artifact.
 */
public class McpCodeAnalyzerTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final AtomicBoolean unsupportedVersionWarned = new AtomicBoolean(false);

    private final List<Endpoint> endpoints;

    /**
     * Creates the task with the shared list that collects an endpoint per analyzed service.
     *
     * @param endpoints the list to which extracted endpoints are added
     */
    McpCodeAnalyzerTask(List<Endpoint> endpoints) {
        this.endpoints = endpoints;
    }

    /**
     * Extracts and collects the endpoint metadata for the analyzed service when endpoint export is enabled.
     *
     * @param context the syntax node analysis context for the service declaration
     */
    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        if (hasCompilationErrors(context) || isInTestSource(context) || !isMcpService(context)) {
            return;
        }
        Package currentPackage = context.currentPackage();
        Project project = currentPackage.project();
        BuildOptions buildOptions = project.buildOptions();
        if (isExportEndpoints(buildOptions, context)) {
            EndpointYamlGenerator endpointYamlGeneratorMcp = new EndpointYamlGenerator(context);
            endpoints.add(endpointYamlGeneratorMcp.getEndpoint());
        }
    }

    /**
     * Checks whether the {@code --export-endpoints} build option is enabled, reporting a warning on Ballerina versions
     * that do not support the option.
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
            if (unsupportedVersionWarned.compareAndSet(false, true)) {
                DiagnosticInfo diagnosticInfo = new DiagnosticInfo(
                        "NO_SUCH_METHOD_ERROR",
                        "The `--export-endpoints` build option is not supported in the current ballerina version. " +
                                "Use ballerina 2201.13.3 or higher. " + e.getMessage(),
                        DiagnosticSeverity.WARNING
                );
                context.reportDiagnostic(
                        DiagnosticFactory.createDiagnostic(diagnosticInfo, context.node().location()));
            }
        }
        return isExportEndpoints;
    }

}
