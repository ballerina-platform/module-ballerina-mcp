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

import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.plugins.CodeAnalysisContext;
import io.ballerina.projects.plugins.CodeAnalyzer;
import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.Endpoint;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Code analyzer that collects endpoint metadata from MCP service declarations and writes it to a single
 * {@code endpoints.yaml} artifact during the compilation phase.
 */
public class McpCodeAnalyzer extends CodeAnalyzer {

    @Override
    public void init(CodeAnalysisContext codeAnalysisContext) {
        // Shared per compilation: the syntax-node task collects an endpoint per service, the compilation task writes
        // them all to a single file once every service has been analyzed.
        List<Endpoint> endpoints = Collections.synchronizedList(new ArrayList<>());
        codeAnalysisContext.addSyntaxNodeAnalysisTask(new McpCodeAnalyzerTask(endpoints),
                SyntaxKind.SERVICE_DECLARATION);
        codeAnalysisContext.addCompilationAnalysisTask(new McpEndpointArtifactTask(endpoints));
    }
}
