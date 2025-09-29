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

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.ConstantSymbol;
import io.ballerina.compiler.api.symbols.Documentable;
import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.FunctionTypeSymbol;
import io.ballerina.compiler.api.symbols.ParameterSymbol;
import io.ballerina.compiler.api.symbols.ServiceDeclarationSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.values.ConstantValue;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.IdentifierToken;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.Location;

import java.util.Optional;

/**
 * Util class for the compiler plugin.
 */
public class Utils {
    public static final String BALLERINA_ORG = "ballerina";
    public static final String TOOL_ANNOTATION_NAME = "Tool";
    public static final String MCP_PACKAGE_NAME = "mcp";
    public static final String MCP_BASIC_SERVICE_NAME = "Service";
    public static final String SESSION_TYPE_NAME = "Session";
    public static final String UNKNOWN_SYMBOL = "unknown";
    public static final String SERVICE_CONFIG_ANNOTATION_NAME = "ServiceConfig";
    public static final String SESSION_MODE_FIELD = "sessionMode";

    public enum SessionMode {
        STATEFUL("stateful"),
        STATELESS("stateless"),
        AUTO("auto");

        private final String value;

        SessionMode(String value) {
            this.value = value;
        }

        public String getValue() {
            return value;
        }

        public static SessionMode fromString(String value) {
            if (value == null) {
                return AUTO;
            }
            for (SessionMode mode : values()) {
                if (mode.value.equalsIgnoreCase(value)) {
                    return mode;
                }
            }
            return AUTO;
        }
    }

    private Utils() {
    }

    public static boolean isMcpToolAnnotation(AnnotationSymbol annotationSymbol) {
        return annotationSymbol.getModule().isPresent()
                && isMcpModuleSymbol(annotationSymbol.getModule().get())
                && annotationSymbol.getName().isPresent()
                && TOOL_ANNOTATION_NAME.equals(annotationSymbol.getName().get());
    }

    public static boolean isMcpModuleSymbol(Symbol symbol) {
        return symbol.getModule().isPresent()
                && MCP_PACKAGE_NAME.equals(symbol.getModule().get().id().moduleName())
                && BALLERINA_ORG.equals(symbol.getModule().get().id().orgName());
    }

    public static String getParameterDescription(FunctionSymbol functionSymbol, String parameterName) {
        if (functionSymbol.documentation().isEmpty()
                || functionSymbol.documentation().get().description().isEmpty()) {
            return null;
        }
        return functionSymbol.documentation().get().parameterMap().getOrDefault(parameterName, null);
    }

    public static String getDescription(Documentable documentable) {
        if (documentable.documentation().isEmpty()
                || documentable.documentation().get().description().isEmpty()) {
            return null;
        }
        return documentable.documentation().get().description().get();
    }

    public static String escapeDoubleQuotes(String input) {
        return input.replace("\"", "\\\"");
    }


    public static String addDoubleQuotes(String input) {
        return "\"" + input + "\"";
    }

    public static Optional<AnnotationNode> getToolAnnotationNode(SemanticModel semanticModel,
                                                                 FunctionDefinitionNode functionDefinitionNode) {
        Optional<MetadataNode> metadataNode = functionDefinitionNode.metadata();
        if (metadataNode.isEmpty()) {
            return Optional.empty();
        }

        NodeList<AnnotationNode> annotationNodes = metadataNode.get().annotations();
        return annotationNodes.stream()
                .filter(annotationNode ->
                        semanticModel.symbol(annotationNode)
                                .filter(symbol -> symbol.kind() == SymbolKind.ANNOTATION)
                                .filter(symbol -> Utils.isMcpToolAnnotation((AnnotationSymbol) symbol))
                                .isPresent()
                )
                .findFirst();
    }

    public static boolean isMcpServiceFunction(SemanticModel semanticModel,
                                               FunctionDefinitionNode functionDefinitionNode) {
        Optional<Symbol> parentSymbol = semanticModel.symbol(functionDefinitionNode.parent());

        if (parentSymbol.isEmpty() || parentSymbol.get().kind() != SymbolKind.SERVICE_DECLARATION) {
            return false;
        }

        ServiceDeclarationSymbol serviceSymbol = (ServiceDeclarationSymbol) parentSymbol.get();
        Optional<TypeSymbol> firstListenerType = serviceSymbol.listenerTypes().stream().findFirst();

        boolean isFromMcpModule = firstListenerType
                .flatMap(TypeSymbol::getModule)
                .flatMap(module -> module.getName().map(MCP_PACKAGE_NAME::equals))
                .orElse(false);

        boolean isServiceType = serviceSymbol.typeDescriptor()
                .flatMap(type -> type.getName().map(MCP_BASIC_SERVICE_NAME::equals))
                .orElse(false);

        return isFromMcpModule && isServiceType;
    }

    public static boolean isAnydataType(TypeSymbol typeSymbol, SyntaxNodeAnalysisContext context) {
        return typeSymbol.subtypeOf(context.semanticModel().types().ANYDATA);
    }

    public static boolean validateParameterTypes(FunctionSymbol functionSymbol,
                                                 FunctionDefinitionNode functionDefinitionNode,
                                                 SyntaxNodeAnalysisContext context) {
        FunctionTypeSymbol functionTypeSymbol = functionSymbol.typeDescriptor();
        if (functionTypeSymbol.params().isEmpty()) {
            return true;
        }

        String functionName = functionSymbol.getName().orElse(UNKNOWN_SYMBOL);
        Location alternativeLocation = functionDefinitionNode.location();
        SessionMode sessionMode = getSessionMode(functionDefinitionNode, context.semanticModel());

        var parameterSymbolList = functionTypeSymbol.params().get();
        boolean hasSessionParam = false;

        for (int i = 0; i < parameterSymbolList.size(); i++) {
            ParameterSymbol parameterSymbol = parameterSymbolList.get(i);
            TypeSymbol parameterType = parameterSymbol.typeDescriptor();
            String parameterName = parameterSymbol.getName().orElse(UNKNOWN_SYMBOL);

            boolean isSessionType = isSessionType(parameterType);

            if (isSessionType) {
                if (hasSessionParam) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.SESSION_PARAM_MUST_BE_FIRST,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }

                if (i != 0) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.SESSION_PARAM_MUST_BE_FIRST,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }

                if (sessionMode == SessionMode.STATELESS) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.SESSION_PARAM_NOT_ALLOWED_IN_STATELESS_MODE,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }

                hasSessionParam = true;
            } else if (!isAnydataType(parameterType, context)) {
                Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                        CompilationDiagnostic.INVALID_PARAMETER_TYPE,
                        parameterSymbol.getLocation().orElse(alternativeLocation),
                        functionName, parameterName);
                context.reportDiagnostic(diagnostic);
                return false;
            }
        }

        return true;
    }

    static boolean isSessionType(TypeSymbol typeSymbol) {
        return SESSION_TYPE_NAME.equals(typeSymbol.getName().orElse(""))
                && isMcpModuleSymbol(typeSymbol);
    }

    private static SessionMode getSessionMode(FunctionDefinitionNode functionDefinitionNode,
                                              SemanticModel semanticModel) {
        ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) functionDefinitionNode.parent();
        if (serviceNode.metadata().isEmpty() || serviceNode.metadata().get().annotations().isEmpty()) {
            return SessionMode.AUTO;
        }

        // Find the MCP ServiceConfig annotation
        AnnotationNode serviceConfigAnnotation = null;
        for (AnnotationNode annotation : serviceNode.metadata().get().annotations()) {
            if (isMcpServiceConfigAnnotation(annotation)) {
                serviceConfigAnnotation = annotation;
                break;
            }
        }

        if (serviceConfigAnnotation == null || serviceConfigAnnotation.annotValue().isEmpty()) {
            return SessionMode.AUTO;
        }

        SeparatedNodeList<MappingFieldNode> fields = serviceConfigAnnotation.annotValue().get().fields();
        for (MappingFieldNode field : fields) {
            if (field.kind() == SyntaxKind.SPECIFIC_FIELD) {
                SpecificFieldNode specificField = (SpecificFieldNode) field;
                String fieldName = ((IdentifierToken) specificField.fieldName()).text();

                if (SESSION_MODE_FIELD.equals(fieldName) && specificField.valueExpr().isPresent()) {
                    return resolveSessionModeValue(specificField.valueExpr().get(), semanticModel);
                }
            }
        }

        return SessionMode.AUTO;
    }

    private static SessionMode resolveSessionModeValue(io.ballerina.compiler.syntax.tree.ExpressionNode valueExpr,
                                                       SemanticModel semanticModel) {
        Optional<Symbol> symbol = semanticModel.symbol(valueExpr);
        if (symbol.isPresent()) {
            Symbol resolvedSymbol = symbol.get();

            if (resolvedSymbol.kind() == SymbolKind.ENUM_MEMBER) {
                ConstantSymbol enumMemberSymbol = (ConstantSymbol) resolvedSymbol;

                if (isMcpModuleSymbol(enumMemberSymbol)) {
                    Object constValue = enumMemberSymbol.constValue();
                    if (constValue instanceof ConstantValue) {
                        String enumValue = ((ConstantValue) constValue).value().toString();
                        return SessionMode.fromString(enumValue);
                    }
                }
            }
        }

        if (valueExpr.kind() == SyntaxKind.STRING_LITERAL) {
            BasicLiteralNode stringLiteral = (BasicLiteralNode) valueExpr;
            String literalValue = stringLiteral.literalToken().text();
            if (literalValue.startsWith("\"") && literalValue.endsWith("\"")) {
                literalValue = literalValue.substring(1, literalValue.length() - 1);
            }
            return SessionMode.fromString(literalValue);
        }

        return SessionMode.AUTO;
    }

    private static boolean isMcpServiceConfigAnnotation(AnnotationNode annotation) {
        if (annotation.annotReference().kind() != SyntaxKind.QUALIFIED_NAME_REFERENCE) {
            return false;
        }

        QualifiedNameReferenceNode qualifiedRef = (QualifiedNameReferenceNode) annotation.annotReference();
        String modulePrefix = qualifiedRef.modulePrefix().text();
        String identifier = qualifiedRef.identifier().text();

        return MCP_PACKAGE_NAME.equals(modulePrefix) && SERVICE_CONFIG_ANNOTATION_NAME.equals(identifier);
    }
}
