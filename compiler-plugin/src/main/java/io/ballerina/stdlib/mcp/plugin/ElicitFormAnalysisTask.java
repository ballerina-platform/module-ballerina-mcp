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

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.ParameterSymbol;
import io.ballerina.compiler.api.symbols.RecordTypeSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.api.symbols.TypeDefinitionSymbol;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionArgumentNode;
import io.ballerina.compiler.syntax.tree.FunctionCallExpressionNode;
import io.ballerina.compiler.syntax.tree.NamedArgumentNode;
import io.ballerina.compiler.syntax.tree.PositionalArgumentNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static io.ballerina.compiler.syntax.tree.SyntaxKind.NAMED_ARG;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.POSITIONAL_ARG;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.QUALIFIED_NAME_REFERENCE;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.SIMPLE_NAME_REFERENCE;
import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic.FORM_SCHEMA_TYPE_NOT_STATIC;
import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic.UNSUPPORTED_FORM_FIELD;

/**
 * Generates the form schema of a record type passed to {@code mcp:elicitForm}, for the source modifier to supply.
 */
public class ElicitFormAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {
    private static final String ELICIT_FORM_FUNCTION_NAME = "elicitForm";
    private static final String SCHEMA_PARAMETER_NAME = "schema";

    private final Map<DocumentId, ModifierContext> modifierContextMap;

    ElicitFormAnalysisTask(Map<DocumentId, ModifierContext> modifierContextMap) {
        this.modifierContextMap = modifierContextMap;
    }

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        FunctionCallExpressionNode call = (FunctionCallExpressionNode) context.node();
        SemanticModel semanticModel = context.semanticModel();
        Optional<FunctionSymbol> elicitForm = getElicitFormFunction(semanticModel, call);
        if (elicitForm.isEmpty()) {
            return;
        }
        Optional<ExpressionNode> schemaArgument = getSchemaArgument(call.arguments(),
                getSchemaParameterPosition(elicitForm.get()));
        if (schemaArgument.isEmpty() || !isTypedesc(semanticModel, schemaArgument.get())) {
            return;
        }
        ExpressionNode argument = schemaArgument.get();
        Optional<TypeDefinitionSymbol> recordType = getRecordTypeDefinition(semanticModel, argument);
        if (recordType.isEmpty()) {
            context.reportDiagnostic(CompilationDiagnostic.getDiagnostic(FORM_SCHEMA_TYPE_NOT_STATIC,
                    argument.location()));
            return;
        }
        String typeName = recordType.get().getName().orElse(Utils.UNKNOWN_SYMBOL);
        try {
            String formSchema = SchemaUtils.getFormSchema(
                    (RecordTypeSymbol) Utils.getRawType(recordType.get().typeDescriptor()), context);
            modifierContextMap.computeIfAbsent(context.documentId(), document -> new ModifierContext())
                    .addFormSchema(argument, formSchema);
        } catch (UnsupportedFormFieldException e) {
            context.reportDiagnostic(CompilationDiagnostic.getDiagnostic(UNSUPPORTED_FORM_FIELD,
                    argument.location(), typeName, e.fieldName()));
        }
    }

    private static Optional<FunctionSymbol> getElicitFormFunction(SemanticModel semanticModel,
                                                                  FunctionCallExpressionNode call) {
        return semanticModel.symbol(call)
                .filter(symbol -> symbol.kind() == SymbolKind.FUNCTION)
                .filter(symbol -> ELICIT_FORM_FUNCTION_NAME.equals(symbol.getName().orElse(null)))
                .filter(Utils::isMcpModuleSymbol)
                .map(FunctionSymbol.class::cast);
    }

    private static int getSchemaParameterPosition(FunctionSymbol elicitForm) {
        List<ParameterSymbol> parameters = elicitForm.typeDescriptor().params().orElse(List.of());
        for (int position = 0; position < parameters.size(); position++) {
            if (SCHEMA_PARAMETER_NAME.equals(parameters.get(position).getName().orElse(null))) {
                return position;
            }
        }
        return -1;
    }

    private static Optional<ExpressionNode> getSchemaArgument(SeparatedNodeList<FunctionArgumentNode> arguments,
                                                              int schemaPosition) {
        for (int index = 0; index < arguments.size(); index++) {
            FunctionArgumentNode argument = arguments.get(index);
            if (argument.kind() == POSITIONAL_ARG && index == schemaPosition) {
                return Optional.of(((PositionalArgumentNode) argument).expression());
            }
            if (argument.kind() == NAMED_ARG && SCHEMA_PARAMETER_NAME.equals(
                    ((NamedArgumentNode) argument).argumentName().name().text())) {
                return Optional.of(((NamedArgumentNode) argument).expression());
            }
        }
        return Optional.empty();
    }

    private static boolean isTypedesc(SemanticModel semanticModel, ExpressionNode argument) {
        return semanticModel.typeOf(argument)
                .map(type -> Utils.getRawType(type).typeKind() == TypeDescKind.TYPEDESC)
                .orElse(false);
    }

    // Only a reference to a record type definition names a type known at compile time.
    private static Optional<TypeDefinitionSymbol> getRecordTypeDefinition(SemanticModel semanticModel,
                                                                          ExpressionNode argument) {
        if (argument.kind() != SIMPLE_NAME_REFERENCE && argument.kind() != QUALIFIED_NAME_REFERENCE) {
            return Optional.empty();
        }
        Optional<Symbol> symbol = semanticModel.symbol(argument);
        if (symbol.isPresent() && symbol.get() instanceof TypeReferenceTypeSymbol typeReference) {
            symbol = Optional.of(typeReference.definition());
        }
        if (symbol.isEmpty() || symbol.get().kind() != SymbolKind.TYPE_DEFINITION) {
            return Optional.empty();
        }
        TypeDefinitionSymbol typeDefinition = (TypeDefinitionSymbol) symbol.get();
        TypeSymbol rawType = Utils.getRawType(typeDefinition.typeDescriptor());
        return rawType.typeKind() == TypeDescKind.RECORD ? Optional.of(typeDefinition) : Optional.empty();
    }
}
