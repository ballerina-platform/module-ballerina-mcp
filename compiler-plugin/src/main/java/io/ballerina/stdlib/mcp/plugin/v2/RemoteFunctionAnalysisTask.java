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

package io.ballerina.stdlib.mcp.plugin.v2;

import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.ObjectTypeSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.VariableSymbol;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.ClassDefinitionNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.NodeFactory;
import io.ballerina.compiler.syntax.tree.NodeLocation;
import io.ballerina.compiler.syntax.tree.NodeParser;
import io.ballerina.compiler.syntax.tree.ObjectConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.Document;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.v2.diagnostics.CompilationDiagnostic;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.Location;

import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.stream.Collectors;

import static io.ballerina.stdlib.mcp.plugin.v2.ToolAnnotationConfig.DESCRIPTION_FIELD_NAME;
import static io.ballerina.stdlib.mcp.plugin.v2.ToolAnnotationConfig.OUTPUT_SCHEMA_FIELD_NAME;
import static io.ballerina.stdlib.mcp.plugin.v2.ToolAnnotationConfig.SCHEMA_FIELD_NAME;
import static io.ballerina.stdlib.mcp.plugin.v2.ToolAnnotationConfig.SCOPES_FIELD_NAME;
import static io.ballerina.stdlib.mcp.plugin.v2.ToolAnnotationConfig.STRUCTURED_OUTPUT_FIELD_NAME;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.getToolAnnotationNode;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.isMcpServiceFunction;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.validateParameterTypes;
import static io.ballerina.stdlib.mcp.plugin.v2.diagnostics.CompilationDiagnostic.UNABLE_TO_GENERATE_OUTPUT_SCHEMA;
import static io.ballerina.stdlib.mcp.plugin.v2.diagnostics.CompilationDiagnostic.UNABLE_TO_GENERATE_SCHEMA_FOR_FUNCTION;

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

        if (!isMcpServiceFunction(context.semanticModel(), functionDefinitionNode)) {
            if (isDynamicBasicService(functionDefinitionNode)) {
                getToolAnnotationNode(context.semanticModel(), functionDefinitionNode).ifPresent(annotation ->
                        getFunctionSymbol(functionDefinitionNode).ifPresent(function -> validateOutputPolicy(
                                annotation, function, functionDefinitionNode.location(), NIL_EXPRESSION)));
            }
            return;
        }

        Optional<FunctionSymbol> functionSymbol = getFunctionSymbol(functionDefinitionNode);
        if (functionSymbol.isEmpty()) {
            return;
        }

        if (!validateParameterTypes(functionSymbol.get(), functionDefinitionNode, context)) {
            return;
        }

        AnnotationNode toolAnnotationNode = getToolAnnotationNode(
                context.semanticModel(), functionDefinitionNode
        ).orElse(null);

        NodeLocation functionNodeLocation = functionDefinitionNode.location();
        ToolAnnotationConfig config = createAnnotationConfig(functionSymbol.get(), functionNodeLocation,
                toolAnnotationNode);
        addToModifierContext(context, functionDefinitionNode, config);
    }

    private ToolAnnotationConfig createAnnotationConfig(FunctionSymbol functionSymbol,
                                                        NodeLocation functionNodeLocation,
                                                        AnnotationNode annotationNode) {
        String functionName = functionSymbol.getName().orElse(Utils.UNKNOWN_SYMBOL + "Function");
        String description = Utils.addDoubleQuotes(Utils.escapeDoubleQuotes(
                Objects.requireNonNullElse(Utils.getDescription(functionSymbol), functionName)));
        if (annotationNode == null) {
            return new ToolAnnotationConfig(description, getParameterSchema(functionSymbol, functionNodeLocation),
                    getReturnSchema(functionSymbol), NIL_EXPRESSION, null, null);
        }
        SeparatedNodeList<MappingFieldNode> fields = annotationNode.annotValue().isEmpty()
                ? NodeFactory.createSeparatedNodeList() : annotationNode.annotValue().get().fields();
        Map<String, ExpressionNode> fieldValues = extractFieldValues(fields);
        AnnotationValues.Value policy = AnnotationValues.field(annotationNode, STRUCTURED_OUTPUT_FIELD_NAME,
                null, context);
        AnnotationValues.Value suppliedSchema = AnnotationValues.field(annotationNode, OUTPUT_SCHEMA_FIELD_NAME,
                null, context);
        boolean disabledOutput = policy.known() && Boolean.FALSE.equals(policy.value());
        String generatedOutput = disabledOutput ? NIL_EXPRESSION : getReturnSchema(functionSymbol);
        validateOutputPolicy(annotationNode, functionSymbol, functionNodeLocation, generatedOutput);
        AnnotationValues.Value inputSchema = AnnotationValues.field(annotationNode, SCHEMA_FIELD_NAME, null, context);
        if ((fieldValues.containsKey(SCHEMA_FIELD_NAME) || inputSchema.known() && inputSchema.value() != null)
                && functionSymbol.typeDescriptor().params()
                        .map(params -> params.stream().anyMatch(Utils::hasMcpArgumentAnnotation)).orElse(false)) {
            reportDiagnostic(CompilationDiagnostic.getDiagnostic(
                    CompilationDiagnostic.MCP_ARGUMENT_WITH_EXPLICIT_SCHEMA, functionNodeLocation, functionName));
        }
        boolean hasSpread = fields.stream().anyMatch(field -> field.kind() == SyntaxKind.SPREAD_FIELD);
        boolean hasShorthand = fields.stream().anyMatch(field -> field instanceof SpecificFieldNode specific
                && specific.valueExpr().isEmpty());
        if (hasSpread || hasShorthand || !policy.known() || !suppliedSchema.known()) {
            String generatedInput;
            if (hasSpread || fieldValues.containsKey(SCHEMA_FIELD_NAME)) {
                try {
                    generatedInput = SchemaUtils.getParameterSchema(functionSymbol, context);
                } catch (SchemaGenerationException e) {
                    generatedInput = NIL_EXPRESSION;
                }
            } else {
                generatedInput = getParameterSchema(functionSymbol, functionNodeLocation);
            }
            return new ToolAnnotationConfig(description, generatedInput, generatedOutput, NIL_EXPRESSION, null,
                    annotationNode.annotValue().orElseThrow().toSourceCode());
        }
        if (fieldValues.containsKey(DESCRIPTION_FIELD_NAME)) {
            description = fieldValues.get(DESCRIPTION_FIELD_NAME).toSourceCode();
        }
        String parameters = fieldValues.containsKey(SCHEMA_FIELD_NAME)
                ? fieldValues.get(SCHEMA_FIELD_NAME).toSourceCode()
                : getParameterSchema(functionSymbol, functionNodeLocation);
        String structuredOutput = fieldValues.containsKey(STRUCTURED_OUTPUT_FIELD_NAME)
                ? fieldValues.get(STRUCTURED_OUTPUT_FIELD_NAME).toSourceCode() : NIL_EXPRESSION;
        String outputSchema = fieldValues.containsKey(OUTPUT_SCHEMA_FIELD_NAME)
                && !(suppliedSchema.known() && suppliedSchema.value() == null)
                ? fieldValues.get(OUTPUT_SCHEMA_FIELD_NAME).toSourceCode() : generatedOutput;
        String scopes = fieldValues.containsKey(SCOPES_FIELD_NAME)
                ? fieldValues.get(SCOPES_FIELD_NAME).toSourceCode() : null;
        return new ToolAnnotationConfig(description, parameters, outputSchema, structuredOutput, scopes, null);
    }

    private void validateOutputPolicy(AnnotationNode annotation, FunctionSymbol function,
                                      NodeLocation location, String generatedOutput) {
        String mode = ProtocolSessionAnalysisTask.protocolMode(context.node().parent(), context);
        if (!"auto".equals(mode) && !"modern".equals(mode)) {
            return;
        }
        AnnotationValues.Value policy = AnnotationValues.field(annotation, STRUCTURED_OUTPUT_FIELD_NAME, null, context);
        AnnotationValues.Value schema = AnnotationValues.field(annotation, OUTPUT_SCHEMA_FIELD_NAME, null, context);
        String functionName = function.getName().orElse(Utils.UNKNOWN_SYMBOL + "Function");
        if (policy.known() && Boolean.FALSE.equals(policy.value()) && schema.known() && schema.value() != null) {
            reportDiagnostic(CompilationDiagnostic.getDiagnostic(
                    CompilationDiagnostic.UNSTRUCTURED_OUTPUT_WITH_OUTPUT_SCHEMA, location, functionName));
        }
        if (policy.known() && Boolean.TRUE.equals(policy.value()) && schema.known() && schema.value() == null
                && NIL_EXPRESSION.equals(generatedOutput)) {
            reportDiagnostic(CompilationDiagnostic.getDiagnostic(
                    UNABLE_TO_GENERATE_OUTPUT_SCHEMA, location, functionName));
        }
    }

    private boolean isDynamicBasicService(FunctionDefinitionNode function) {
        if (function.parent() instanceof ObjectConstructorExpressionNode object) {
            Optional<Symbol> enclosing = context.semanticModel().symbol(object.parent());
            if (enclosing.isPresent() && enclosing.get() instanceof VariableSymbol variable) {
                return isBasicServiceType(variable.typeDescriptor());
            }
            Document document = context.currentPackage().module(context.moduleId()).document(context.documentId());
            return context.semanticModel().expectedType(document, object.lineRange().startLine())
                    .map(this::isBasicServiceType).orElse(false);
        }
        if (function.parent() instanceof ClassDefinitionNode definition) {
            return context.semanticModel().symbol(definition)
                    .filter(ObjectTypeSymbol.class::isInstance).map(ObjectTypeSymbol.class::cast)
                    .map(this::isBasicServiceType).orElse(false);
        }
        return false;
    }

    private boolean isBasicServiceType(TypeSymbol type) {
        if (Utils.isMcpModuleSymbol(type) && "StreamableHttpService".equals(type.getName().orElse(""))) {
            return true;
        }
        if (type instanceof TypeReferenceTypeSymbol reference) {
            return isBasicServiceType(reference.typeDescriptor());
        }
        return type instanceof ObjectTypeSymbol object && object.typeInclusions().stream()
                .anyMatch(this::isBasicServiceType);
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
        } catch (SchemaGenerationException e) {
            Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(UNABLE_TO_GENERATE_SCHEMA_FOR_FUNCTION,
                    functionSymbol.getLocation().orElse(alternativeFunctionLocation),
                    functionSymbol.getName().orElse(Utils.UNKNOWN_SYMBOL + "Function"));
            reportDiagnostic(diagnostic);
            return NIL_EXPRESSION;
        }
    }

    private String getReturnSchema(FunctionSymbol functionSymbol) {
        try {
            return Objects.requireNonNullElse(SchemaUtils.getReturnSchema(functionSymbol, context), NIL_EXPRESSION);
        } catch (SchemaGenerationException e) {
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
