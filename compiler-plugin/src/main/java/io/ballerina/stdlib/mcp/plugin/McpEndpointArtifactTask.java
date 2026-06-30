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

import io.ballerina.projects.Project;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.CompilationAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.Endpoint;
import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.EndpointsArtifactWriter;

import java.io.IOException;
import java.io.PrintStream;
import java.util.List;

/**
 * Compilation-phase task that writes the endpoints collected from every MCP service into a single
 * {@code target/artifact/endpoints.yaml}. It runs once per package after all service declarations have been analyzed by
 * {@link McpCodeAnalyzerTask}.
 */
public class McpEndpointArtifactTask implements AnalysisTask<CompilationAnalysisContext> {

    private static final PrintStream outStream = System.out;

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
        if (endpoints.isEmpty()) {
            return;
        }
        Project project = context.currentPackage().project();
        try {
            new EndpointsArtifactWriter().write(project.targetDir(), endpoints, context);
        } catch (IOException e) {
            outStream.println(e);
        }
    }
}
