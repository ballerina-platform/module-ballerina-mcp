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

import io.ballerina.compiler.api.symbols.ConstantSymbol;
import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.values.ConstantValue;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic;

import java.util.Optional;

/** Diagnoses session dependencies without rejecting existing auto-mode services. */
public class ProtocolSessionAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {
    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        if (!Utils.isMcpService(context)) {
            return;
        }
        ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) context.node();
        String protocolMode = protocolMode(serviceNode, context);
        if ("legacy".equals(protocolMode) || protocolMode == null) {
            return;
        }
        for (Node member : serviceNode.members()) {
            if (!(member instanceof FunctionDefinitionNode functionNode)
                    || functionNode.qualifierList().stream()
                    .noneMatch(token -> token.kind() == SyntaxKind.REMOTE_KEYWORD)) {
                continue;
            }
            Optional<Symbol> symbol = context.semanticModel().symbol(functionNode);
            if (symbol.isEmpty() || !(symbol.get() instanceof FunctionSymbol functionSymbol)) {
                continue;
            }
            functionSymbol.typeDescriptor().params().ifPresent(parameters -> parameters.forEach(parameter -> {
                if (!Utils.isSessionType(parameter.typeDescriptor())) {
                    return;
                }
                boolean nullable = Utils.isOptionalType(parameter.typeDescriptor());
                CompilationDiagnostic diagnostic;
                if ("modern".equals(protocolMode)) {
                    diagnostic = nullable ? CompilationDiagnostic.OPTIONAL_SESSION_IN_MODERN_MODE
                            : CompilationDiagnostic.REQUIRED_SESSION_IN_MODERN_MODE;
                } else {
                    diagnostic = nullable ? CompilationDiagnostic.OPTIONAL_SESSION_IN_AUTO_MODE
                            : CompilationDiagnostic.REQUIRED_SESSION_IN_AUTO_MODE;
                }
                context.reportDiagnostic(CompilationDiagnostic.getDiagnostic(diagnostic,
                        parameter.getLocation().orElse(functionNode.location()),
                        parameter.getName().orElse("session")));
            }));
        }
    }

    private String protocolMode(ServiceDeclarationNode serviceNode, SyntaxNodeAnalysisContext context) {
        if (serviceNode.metadata().isEmpty()) {
            return "auto";
        }
        AnnotationNode selected = null;
        for (AnnotationNode annotation : serviceNode.metadata().get().annotations()) {
            Optional<Symbol> symbol = context.semanticModel().symbol(annotation.annotReference());
            if (symbol.isEmpty() || !Utils.isMcpModuleSymbol(symbol.get())) {
                continue;
            }
            String name = symbol.get().getName().orElse("");
            if ("StreamableHttpConfig".equals(name)) {
                selected = annotation;
                break;
            }
        }
        if (selected == null || selected.annotValue().isEmpty()) {
            return "auto";
        }
        for (Node field : selected.annotValue().get().fields()) {
            if (field instanceof SpecificFieldNode specific
                    && "protocolMode".equals(specific.fieldName().toString().trim())
                    && specific.valueExpr().isPresent()) {
                Node expression = specific.valueExpr().get();
                String value = expression.toString().trim();
                Optional<Symbol> symbol = context.semanticModel().symbol(expression);
                if (symbol.isPresent() && symbol.get() instanceof ConstantSymbol constant) {
                    Object constantValue = constant.constValue();
                    value = String.valueOf(constantValue instanceof ConstantValue resolved
                            ? resolved.value() : constantValue);
                }
                value = value.replace("\"", "");
                return switch (value) {
                    case "auto", "modern", "legacy" -> value;
                    default -> null;
                };
            }
        }
        return "auto";
    }
}
