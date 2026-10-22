/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
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

package io.ballerina.stdlib.mcp.plugin;

import io.ballerina.compiler.api.symbols.ServiceDeclarationSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic;

import java.util.Map;
import java.util.Optional;

/**
 * Warns on service declarations of the deprecated transport-neutral service types. The language reports
 * no deprecation for a type used as a service declaration's type, so the plugin does.
 */
public class DeprecatedServiceAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final Map<String, String> REPLACEMENTS = Map.of(
            Utils.MCP_BASIC_SERVICE_NAME, Utils.STREAMABLE_HTTP_BASIC_SERVICE_NAME,
            Utils.MCP_ADVANCED_SERVICE_NAME, Utils.STREAMABLE_HTTP_ADVANCED_SERVICE_NAME);

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) context.node();
        Optional<Symbol> symbol = context.semanticModel().symbol(serviceNode);
        if (symbol.isEmpty() || !(symbol.get() instanceof ServiceDeclarationSymbol serviceSymbol)) {
            return;
        }
        Optional<TypeSymbol> serviceType = serviceSymbol.typeDescriptor();
        if (serviceType.isEmpty() || !Utils.isMcpModuleSymbol(serviceType.get())) {
            return;
        }
        String typeName = serviceType.get().getName().orElse("");
        String replacement = REPLACEMENTS.get(typeName);
        if (replacement == null) {
            return;
        }
        context.reportDiagnostic(CompilationDiagnostic.getDiagnostic(
                CompilationDiagnostic.DEPRECATED_TRANSPORT_NEUTRAL_SERVICE,
                serviceNode.typeDescriptor().map(node -> node.location()).orElse(serviceNode.location()),
                "mcp:" + typeName, "mcp:" + replacement));
    }
}
