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

package io.ballerina.stdlib.mcp.plugin;

import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.NodeFactory;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.NodeParser;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.Location;

import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.stream.Collectors;

import static io.ballerina.stdlib.mcp.plugin.ToolAnnotationConfig.DESCRIPTION_FIELD_NAME;
import static io.ballerina.stdlib.mcp.plugin.ToolAnnotationConfig.SCHEMA_FIELD_NAME;
import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic.UNABLE_TO_GENERATE_SCHEMA_FOR_FUNCTION;

public class RemoteFunctionAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {
    public static final String EMPTY_STRING = "";
    public static final String NIL_EXPRESSION = "()";

    private final Map<DocumentId, ModifierContext> modifierContextMap;
    private SyntaxNodeAnalysisContext context;

    RemoteFunctionAnalysisTask(Map<DocumentId, ModifierContext> modifierContextMap) {
        this.modifierContextMap = modifierContextMap;
    }

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        this.context = context;

        FunctionDefinitionNode functionDefinitionNode = (FunctionDefinitionNode) context.node();
        Optional<MetadataNode> metadataNode = functionDefinitionNode.metadata();
        if (metadataNode.isEmpty()) {
            return;
        }

        NodeList<AnnotationNode> annotationNodeList = metadataNode.get().annotations();
        Optional<AnnotationNode> toolAnnotationNode = annotationNodeList.stream()
                .filter(annotationNode ->
                        context.semanticModel().symbol(annotationNode)
                                .filter(symbol -> symbol.kind() == SymbolKind.ANNOTATION)
                                .filter(symbol -> Utils.isMcpToolAnnotation((AnnotationSymbol) symbol))
                                .isPresent()
                )
                .findFirst();
        if (toolAnnotationNode.isEmpty()) {
            return;
        }

        ToolAnnotationConfig config = createAnnotationConfig(toolAnnotationNode.get(), functionDefinitionNode);
        addToModifierContext(context, toolAnnotationNode.get(), config);
    }

    private ToolAnnotationConfig createAnnotationConfig(AnnotationNode annotationNode,
                                                        FunctionDefinitionNode functionDefinitionNode) {
        @SuppressWarnings("OptionalGetWithoutIsPresent") // is present already check in perform method
        FunctionSymbol functionSymbol = getFunctionSymbol(functionDefinitionNode).get();
        String functionName = functionSymbol.getName().orElse("unknownFunction");
        SeparatedNodeList<MappingFieldNode> fields = annotationNode.annotValue().isEmpty() ?
                NodeFactory.createSeparatedNodeList() : annotationNode.annotValue().get().fields();
        Map<String, ExpressionNode> fieldValues = extractFieldValues(fields);
        String description = fieldValues.containsKey(DESCRIPTION_FIELD_NAME)
                ? fieldValues.get(DESCRIPTION_FIELD_NAME).toSourceCode()
                : Utils.addDoubleQuotes(Objects.requireNonNullElse(Utils.getDescription(functionSymbol), functionName));
        String parameters = fieldValues.containsKey(SCHEMA_FIELD_NAME)
                ? fieldValues.get(SCHEMA_FIELD_NAME).toSourceCode()
                : getParameterSchema(functionSymbol, functionDefinitionNode.location());
        return new ToolAnnotationConfig(description, parameters);
    }

    private Optional<FunctionSymbol> getFunctionSymbol(FunctionDefinitionNode functionDefinitionNode) {
        Optional<Symbol> functionSymbol = context.semanticModel().symbol(functionDefinitionNode);
        return functionSymbol.filter(symbol -> symbol.kind() == SymbolKind.FUNCTION
                || symbol.kind() == SymbolKind.METHOD).map(FunctionSymbol.class::cast);
    }

    private Map<String, ExpressionNode> extractFieldValues(SeparatedNodeList<MappingFieldNode> fields) {
        return fields.stream()
                .filter(field -> field.kind() == SyntaxKind.SPECIFIC_FIELD)
                .map(field -> (SpecificFieldNode) field)
                .filter(field -> field.valueExpr().isPresent())
                .collect(Collectors.toMap(
                        field -> field.fieldName().toSourceCode().trim(),
                        field -> field.valueExpr().orElse(NodeParser.parseExpression(NIL_EXPRESSION))
                ));
    }

    private String getParameterSchema(FunctionSymbol functionSymbol, Location alternativeFunctionLocation) {
        try {
            return SchemaUtils.getParameterSchema(functionSymbol, this.context);
        } catch (Exception e) {
            Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(UNABLE_TO_GENERATE_SCHEMA_FOR_FUNCTION,
                    functionSymbol.getLocation().orElse(alternativeFunctionLocation),
                    functionSymbol.getName().orElse("unknownFunction"));
            reportDiagnostic(diagnostic);
            return NIL_EXPRESSION;
        }
    }

    private void reportDiagnostic(Diagnostic diagnostic) {
        this.context.reportDiagnostic(diagnostic);
    }

    private void addToModifierContext(SyntaxNodeAnalysisContext context, AnnotationNode annotationNode,
                                      ToolAnnotationConfig functionDefinitionNode) {
        this.modifierContextMap.computeIfAbsent(context.documentId(), document -> new ModifierContext())
                .add(annotationNode, functionDefinitionNode);
    }
}
