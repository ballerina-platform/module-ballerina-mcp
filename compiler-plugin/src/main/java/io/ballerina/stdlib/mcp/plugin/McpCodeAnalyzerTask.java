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
import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.EndpointYamlGenerator;

import java.io.IOException;
import java.io.PrintStream;

public class McpCodeAnalyzerTask implements AnalysisTask<SyntaxNodeAnalysisContext> {
    private static final PrintStream outStream = System.out;
    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        Package currentPackage = context.currentPackage();
        Project project = currentPackage.project();
        BuildOptions buildOptions = project.buildOptions();
        if (isExportEndpoints(buildOptions)) {
            EndpointYamlGenerator endpointYamlGeneratorMcp = new EndpointYamlGenerator(context);
            try {
                endpointYamlGeneratorMcp.writeEndpointYaml();
            } catch (IOException e) {
                outStream.println(e);
            }
        }
    }

    private boolean isExportEndpoints(BuildOptions buildOptions) {
        boolean isExportEndpoints = false;
        // Ensure backward compatibility with older ballerina-lang versions
        try {
            isExportEndpoints = buildOptions.exportEndpoints();
        } catch (Throwable e) {
            outStream.println("The ballerina version is not supported for --export-endpoints" +
                    " build option. Try using ballerina 2201.13.3 or above.");
        }
        return isExportEndpoints;
    }
}
