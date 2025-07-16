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

import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.NodeFactory;
import io.ballerina.compiler.syntax.tree.NodeLocation;
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
import static io.ballerina.stdlib.mcp.plugin.Utils.getToolAnnotationNode;
import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic.UNABLE_TO_GENERATE_SCHEMA_FOR_FUNCTION;

/**
 * Analysis task that processes remote function definitions to generate MCP tool annotation configurations.
 * 
 * <p>This task analyzes function signatures, extracts parameter schemas, and creates tool annotation
 * configurations that will be used by {@link McpSourceModifier} to update source code.</p>
 */
public class RemoteFunctionAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {
    public static final String EMPTY_STRING = "";
    public static final String NIL_EXPRESSION = "()";

    private final Map<DocumentId, ModifierContext> modifierContextMap;
    private SyntaxNodeAnalysisContext context;

    /**
     * Creates a new analysis task with the given modifier context map.
     * 
     * @param modifierContextMap map to store analysis results for each document
     */
    RemoteFunctionAnalysisTask(Map<DocumentId, ModifierContext> modifierContextMap) {
        this.modifierContextMap = modifierContextMap;
    }

    /**
     * Performs analysis on a function definition node to extract tool annotation information.
     * 
     * @param context the syntax node analysis context containing the function definition
     */
    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        this.context = context;

        FunctionDefinitionNode functionDefinitionNode = (FunctionDefinitionNode) context.node();
        AnnotationNode toolAnnotationNode = getToolAnnotationNode(
                context.semanticModel(), functionDefinitionNode
        ).orElse(null);

        NodeLocation functionNodeLocation = functionDefinitionNode.location();
        Optional<FunctionSymbol> functionSymbol = getFunctionSymbol(functionDefinitionNode);
        if (functionSymbol.isEmpty()) {
            return;
        }
        ToolAnnotationConfig config = createAnnotationConfig(functionSymbol.get(), functionNodeLocation,
                toolAnnotationNode);
        addToModifierContext(context, functionDefinitionNode, config);
    }

    private ToolAnnotationConfig createAnnotationConfig(FunctionSymbol functionSymbol,
                                                        NodeLocation functionNodeLocation,
                                                        AnnotationNode annotationNode) {
        String functionName = functionSymbol.getName().orElse("unknownFunction");
        String description = Utils.addDoubleQuotes(
                Utils.escapeDoubleQuotes(
                        Objects.requireNonNullElse(Utils.getDescription(functionSymbol), functionName)));
        if (annotationNode == null) {
            String schema = getParameterSchema(functionSymbol, functionNodeLocation);
            return new ToolAnnotationConfig(description, schema);
        }
        SeparatedNodeList<MappingFieldNode> fields = annotationNode.annotValue().isEmpty() ?
                NodeFactory.createSeparatedNodeList() : annotationNode.annotValue().get().fields();
        Map<String, ExpressionNode> fieldValues = extractFieldValues(fields);
        if (fieldValues.containsKey(DESCRIPTION_FIELD_NAME)) {
            description = fieldValues.get(DESCRIPTION_FIELD_NAME).toSourceCode();
        }
        String parameters = fieldValues.containsKey(SCHEMA_FIELD_NAME)
                ? fieldValues.get(SCHEMA_FIELD_NAME).toSourceCode()
                : getParameterSchema(functionSymbol, functionNodeLocation);
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

    private void addToModifierContext(SyntaxNodeAnalysisContext context, FunctionDefinitionNode functionDefinitionNode,
                                      ToolAnnotationConfig toolAnnotationConfig) {
        this.modifierContextMap.computeIfAbsent(context.documentId(), document -> new ModifierContext())
                .add(functionDefinitionNode, toolAnnotationConfig);
    }
}
