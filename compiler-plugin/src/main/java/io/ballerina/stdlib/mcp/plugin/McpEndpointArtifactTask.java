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
import io.ballerina.projects.Project;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.CompilationAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.Endpoint;
import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.EndpointsArtifactWriter;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;
import io.ballerina.tools.text.LinePosition;
import io.ballerina.tools.text.LineRange;
import io.ballerina.tools.text.TextRange;

import java.io.IOException;
import java.util.List;

/**
 * Compilation-phase task that writes the endpoints collected from every MCP service into a single
 * {@code target/artifact/endpoints.yaml}. It runs once per package after all service declarations have been analyzed by
 * {@link McpCodeAnalyzerTask}.
 */
public class McpEndpointArtifactTask implements AnalysisTask<CompilationAnalysisContext> {

    private final List<Endpoint> endpoints;

    /**
     * Creates the task with the shared list that {@link McpCodeAnalyzerTask} populates per service.
     *
     * @param endpoints the endpoints collected during syntax-node analysis
     */
    McpEndpointArtifactTask(List<Endpoint> endpoints) {
        this.endpoints = endpoints;
    }

    @Override
    public void perform(CompilationAnalysisContext context) {
        if (context.compilation().diagnosticResult().hasErrors()) {
            return;
        }
        Project project = context.currentPackage().project();
        if (!isExportEndpoints(project.buildOptions())) {
            return;
        }
        // Write even when no MCP endpoints were collected: an existing endpoints.yaml may still hold stale MCP
        // entries (e.g. from a build where services were later removed) that the writer must clean up.
        try {
            new EndpointsArtifactWriter().write(project.targetDir(), endpoints, context);
        } catch (IOException e) {
            reportWriteFailureDiagnostic(context, e);
        }
    }

    private boolean isExportEndpoints(BuildOptions buildOptions) {
        try {
            return buildOptions.exportEndpoints();
        } catch (NoSuchMethodError e) {
            // Unsupported Ballerina version; McpCodeAnalyzerTask already warns about this when MCP services are
            // present. There is nothing to export here either way.
            return false;
        }
    }

    private void reportWriteFailureDiagnostic(CompilationAnalysisContext context, IOException e) {
        DiagnosticInfo diagnosticInfo = new DiagnosticInfo(
                "ENDPOINTS_ARTIFACT_WRITE_FAILED",
                "Failed to write the endpoint export artifact: " + e.getMessage(),
                DiagnosticSeverity.ERROR
        );
        context.reportDiagnostic(DiagnosticFactory.createDiagnostic(diagnosticInfo, new NullLocation()));
    }

    /**
     * A {@link Location} placeholder for the write-failure diagnostic, which is not tied to a specific source node.
     */
    private static class NullLocation implements Location {

        @Override
        public LineRange lineRange() {
            return LineRange.from("", LinePosition.from(0, 0), LinePosition.from(0, 0));
        }

        @Override
        public TextRange textRange() {
            return TextRange.from(0, 0);
        }
    }
}
