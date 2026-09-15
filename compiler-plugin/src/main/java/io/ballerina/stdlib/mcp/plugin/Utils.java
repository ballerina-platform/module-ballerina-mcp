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
import io.ballerina.compiler.api.symbols.AnnotationAttachmentSymbol;
import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.ArrayTypeSymbol;
import io.ballerina.compiler.api.symbols.ConstantSymbol;
import io.ballerina.compiler.api.symbols.Documentable;
import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.FunctionTypeSymbol;
import io.ballerina.compiler.api.symbols.IntersectionTypeSymbol;
import io.ballerina.compiler.api.symbols.ParameterSymbol;
import io.ballerina.compiler.api.symbols.RecordTypeSymbol;
import io.ballerina.compiler.api.symbols.ServiceDeclarationSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.compiler.api.values.ConstantValue;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.IdentifierToken;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.Module;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;

import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Util class for the compiler plugin.
 */
public class Utils {

    public static final String BALLERINA_ORG = "ballerina";
    public static final String TOOL_ANNOTATION_NAME = "Tool";
    public static final String ARGUMENT_ANNOTATION_NAME = "Argument";
    public static final String ARGUMENT_HEADER_NAME_FIELD = "headerName";
    public static final String MCP_PACKAGE_NAME = "mcp";
    public static final String STREAMABLE_HTTP_BASIC_SERVICE_NAME = "StreamableHttpService";
    public static final String STREAMABLE_HTTP_ADVANCED_SERVICE_NAME = "StreamableHttpAdvancedService";
    public static final String SESSION_TYPE_NAME = "HttpSession";
    public static final String META_TYPE_NAME = "RequestMetaObject";
    public static final String CALL_TOOL_PARAMS_TYPE_NAME = "CallToolParams";
    public static final String CALL_TOOL_RESULT_TYPE_NAME = "CallToolResult";
    public static final String LIST_TOOLS_RESULT_TYPE_NAME = "ListToolsResult";
    public static final String INPUT_REQUIRED_RESULT_TYPE_NAME = "InputRequiredResult";
    public static final String SUBSCRIPTION_FILTER_TYPE_NAME = "SubscriptionFilter";
    public static final String HTTP_PACKAGE_NAME = "http";
    public static final String HEADERS_TYPE_NAME = "Headers";
    public static final String REQUEST_TYPE_NAME = "Request";
    public static final String HEADER_ANNOTATION_NAME = "Header";
    public static final String UNKNOWN_SYMBOL = "unknown";
    public static final String STREAMABLE_HTTP_CONFIG_ANNOTATION_NAME = "StreamableHttpConfig";
    public static final String SESSION_MODE_FIELD = "sessionMode";
    private static final Pattern MCP_HEADER_NAME = Pattern.compile("[!#$%&'*+.^_`|~0-9A-Za-z-]+");

    // Human-readable lists of supported parameter types, used in the INVALID_PARAMETER_TYPE diagnostic.
    public static final String BASIC_TOOL_SUPPORTED_PARAM_TYPES =
            "'anydata' tool parameters, a first 'mcp:HttpSession' parameter, an optional "
                    + "'mcp:RequestMetaObject' parameter, "
                    + "an 'http:Headers' parameter, an 'http:Request' parameter, or '@http:Header' parameters";
    public static final String ADVANCED_SUPPORTED_PARAM_TYPES =
            "'mcp:CallToolParams', 'mcp:HttpSession', 'http:Headers', 'http:Request', or an '@http:Header' parameter";
    // 'onListTools' does not accept 'mcp:CallToolParams' or 'mcp:HttpSession'.
    public static final String ADVANCED_LIST_TOOLS_SUPPORTED_PARAM_TYPES =
            "'http:Headers', 'http:Request', or an '@http:Header' parameter";

    public enum HttpSessionMode {
        STATEFUL("stateful"),
        STATELESS("stateless"),
        AUTO("auto");

        private final String value;

        HttpSessionMode(String value) {
            this.value = value;
        }

        public String getValue() {
            return value;
        }

        public static HttpSessionMode fromString(String value) {
            if (value == null) {
                return AUTO;
            }
            for (HttpSessionMode mode : values()) {
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

    private static boolean isHttpModuleSymbol(Symbol symbol) {
        return symbol.getModule().isPresent()
                && HTTP_PACKAGE_NAME.equals(symbol.getModule().get().id().moduleName())
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
        return isMcpBasicService(semanticModel, functionDefinitionNode.parent());
    }

    /**
     * Returns whether the given node is an `mcp:StreamableHttpService` declaration attached to a
     * listener from the mcp module. These are the only services whose tool methods the source modifier may rewrite;
     * every other service declaration (including advanced mcp services and unrelated services such as `http:Service`)
     * must be left untouched.
     */
    public static boolean isMcpBasicService(SemanticModel semanticModel, Node serviceNode) {
        Optional<Symbol> serviceDeclSymbol = semanticModel.symbol(serviceNode);

        if (serviceDeclSymbol.isEmpty() || serviceDeclSymbol.get().kind() != SymbolKind.SERVICE_DECLARATION) {
            return false;
        }

        ServiceDeclarationSymbol serviceSymbol = (ServiceDeclarationSymbol) serviceDeclSymbol.get();

        boolean isFromMcpModule = serviceSymbol.listenerTypes().stream()
                .anyMatch(Utils::isListenerFromMcpModule);

        boolean isServiceType = serviceSymbol.typeDescriptor()
                .flatMap(TypeSymbol::getName)
                .map(STREAMABLE_HTTP_BASIC_SERVICE_NAME::equals)
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
        HttpSessionMode sessionMode = getSessionMode(functionDefinitionNode, context.semanticModel());

        var parameterSymbolList = functionTypeSymbol.params().get();
        boolean hasSessionParam = false;
        boolean hasMetaParam = false;
        boolean hasHeadersParam = false;
        boolean hasRequestParam = false;
        Set<String> argumentHeaderNames = new HashSet<>();

        for (int i = 0; i < parameterSymbolList.size(); i++) {
            ParameterSymbol parameterSymbol = parameterSymbolList.get(i);
            TypeSymbol parameterType = parameterSymbol.typeDescriptor();
            String parameterName = parameterSymbol.getName().orElse(UNKNOWN_SYMBOL);

            boolean isSessionType = isSessionType(parameterType);
            boolean isMetaParam = isMetaParameter(parameterType);
            boolean hasMcpArgument = hasMcpArgumentAnnotation(parameterSymbol);

            if (hasMcpArgument) {
                if (hasHttpHeaderAnnotation(parameterSymbol) || isSessionType || isMetaParam
                        || isHttpHeadersType(parameterType) || isHttpRequestType(parameterType)
                        || !isValidMcpHeaderArgumentType(parameterType, context)) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.INVALID_MCP_ARGUMENT_TYPE,
                            parameterSymbol.getLocation().orElse(alternativeLocation), functionName, parameterName);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }
                String headerName = getMcpArgumentHeaderName(parameterSymbol).orElse("");
                if (!MCP_HEADER_NAME.matcher(headerName).matches()) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.INVALID_MCP_ARGUMENT_HEADER_NAME,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName, headerName);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }
                if (!argumentHeaderNames.add(headerName.toLowerCase(Locale.ROOT))) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.DUPLICATE_MCP_ARGUMENT_HEADER_NAME,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName, headerName);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }
            }

            if (hasHttpHeaderAnnotation(parameterSymbol)) {
                if (!isValidHeaderParamType(parameterType, context)) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.INVALID_HEADER_PARAMETER_TYPE,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }
                continue;
            }

            if (isHttpHeadersType(parameterType)) {
                if (hasHeadersParam) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.DUPLICATE_PARAMETER,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName, HTTP_PACKAGE_NAME + ":" + HEADERS_TYPE_NAME);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }
                hasHeadersParam = true;
            } else if (isHttpRequestType(parameterType)) {
                if (hasRequestParam) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.DUPLICATE_PARAMETER,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName, HTTP_PACKAGE_NAME + ":" + REQUEST_TYPE_NAME);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }
                hasRequestParam = true;
            } else if (isSessionType) {
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

                if (sessionMode == HttpSessionMode.STATELESS && !isOptionalType(parameterType)) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.SESSION_PARAM_NOT_ALLOWED_IN_STATELESS_MODE,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }

                hasSessionParam = true;
            } else if (isMetaParam) {
                if (hasMetaParam) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.DUPLICATE_PARAMETER,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName, MCP_PACKAGE_NAME + ":" + META_TYPE_NAME);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }

                // Check if Meta parameter is optional
                if (!isOptionalType(parameterType)) {
                    Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                            CompilationDiagnostic.META_PARAM_MUST_BE_OPTIONAL,
                            parameterSymbol.getLocation().orElse(alternativeLocation),
                            functionName, parameterName);
                    context.reportDiagnostic(diagnostic);
                    return false;
                }

                hasMetaParam = true;
            } else if (!isAnydataType(parameterType, context)) {
                Diagnostic diagnostic = CompilationDiagnostic.getDiagnostic(
                        CompilationDiagnostic.INVALID_PARAMETER_TYPE,
                        parameterSymbol.getLocation().orElse(alternativeLocation),
                        functionName, parameterName, BASIC_TOOL_SUPPORTED_PARAM_TYPES);
                context.reportDiagnostic(diagnostic);
                return false;
            }
        }

        return true;
    }

    static boolean isSessionType(TypeSymbol typeSymbol) {
        if (typeSymbol.typeKind() == TypeDescKind.UNION) {
            return ((UnionTypeSymbol) typeSymbol).memberTypeDescriptors().stream()
                    .filter(member -> member.typeKind() != TypeDescKind.NIL).allMatch(Utils::isSessionType);
        }
        if (SESSION_TYPE_NAME.equals(typeSymbol.getName().orElse("")) && isMcpModuleSymbol(typeSymbol)) {
            return true;
        }
        return typeSymbol instanceof TypeReferenceTypeSymbol reference && isSessionType(reference.typeDescriptor());
    }

    static boolean isCallToolParamsType(TypeSymbol typeSymbol) {
        return CALL_TOOL_PARAMS_TYPE_NAME.equals(typeSymbol.getName().orElse(""))
                && isMcpModuleSymbol(typeSymbol);
    }

    static boolean isMetaType(TypeSymbol typeSymbol) {
        return META_TYPE_NAME.equals(typeSymbol.getName().orElse(""))
                && isMcpModuleSymbol(typeSymbol);
    }

    /**
     * Check if a TypeSymbol is optional/nullable (e.g., mcp:RequestMetaObject?).
     * An optional type is a union type that includes NIL as one of its members.
     *
     * @param typeSymbol The type symbol to check
     * @return true if the type is optional/nullable, false otherwise
     */
    static boolean isOptionalType(TypeSymbol typeSymbol) {
        if (typeSymbol instanceof TypeReferenceTypeSymbol reference) {
            return isOptionalType(reference.typeDescriptor());
        }
        if (typeSymbol.typeKind() != TypeDescKind.UNION) {
            return false;
        }

        UnionTypeSymbol unionTypeSymbol = (UnionTypeSymbol) typeSymbol;
        for (TypeSymbol memberType : unionTypeSymbol.memberTypeDescriptors()) {
            if (memberType.typeKind() == TypeDescKind.NIL) {
                return true;
            }
        }
        return false;
    }

    /**
     * Check if a parameter is request metadata (either mcp:RequestMetaObject or mcp:RequestMetaObject?).
     * Returns true if the parameter is Meta type, and also indicates if it's optional.
     *
     * @param typeSymbol The type symbol to check
     * @return true if the parameter is a Meta type (optional or not)
     */
    static boolean isMetaParameter(TypeSymbol typeSymbol) {
        // Direct Meta type check
        if (isMetaType(typeSymbol)) {
            return true;
        }

        // Check if it is an optional request metadata type (mcp:RequestMetaObject?).
        if (typeSymbol.typeKind() == TypeDescKind.UNION) {
            UnionTypeSymbol unionTypeSymbol = (UnionTypeSymbol) typeSymbol;
            for (TypeSymbol memberType : unionTypeSymbol.memberTypeDescriptors()) {
                if (isMetaType(memberType)) {
                    return true;
                }
            }
        }

        return false;
    }

    static boolean isHttpHeadersType(TypeSymbol typeSymbol) {
        return HEADERS_TYPE_NAME.equals(typeSymbol.getName().orElse(""))
                && isHttpModuleSymbol(typeSymbol);
    }

    static boolean isHttpRequestType(TypeSymbol typeSymbol) {
        return REQUEST_TYPE_NAME.equals(typeSymbol.getName().orElse(""))
                && isHttpModuleSymbol(typeSymbol);
    }

    static boolean hasHttpHeaderAnnotation(ParameterSymbol parameterSymbol) {
        return parameterSymbol.annotations().stream()
                .anyMatch(annotation -> HEADER_ANNOTATION_NAME.equals(annotation.getName().orElse(""))
                        && isHttpModuleSymbol(annotation));
    }

    static boolean hasMcpArgumentAnnotation(ParameterSymbol parameterSymbol) {
        return parameterSymbol.annotations().stream()
                .anyMatch(annotation -> ARGUMENT_ANNOTATION_NAME.equals(annotation.getName().orElse(""))
                        && isMcpModuleSymbol(annotation));
    }

    static Optional<String> getMcpArgumentHeaderName(ParameterSymbol parameterSymbol) {
        for (AnnotationAttachmentSymbol attachment : parameterSymbol.annotAttachments()) {
            AnnotationSymbol annotation = attachment.typeDescriptor();
            if (!ARGUMENT_ANNOTATION_NAME.equals(annotation.getName().orElse(""))
                    || !isMcpModuleSymbol(annotation)) {
                continue;
            }
            Optional<ConstantValue> attachmentValue = attachment.attachmentValue();
            if (attachmentValue.isEmpty() || !(attachmentValue.get().value() instanceof Map<?, ?> fields)) {
                return Optional.empty();
            }
            Object headerName = fields.get(ARGUMENT_HEADER_NAME_FIELD);
            if (headerName instanceof ConstantValue constantValue && constantValue.value() instanceof String value) {
                return Optional.of(value);
            }
            if (headerName instanceof String value) {
                return Optional.of(value);
            }
            return Optional.empty();
        }
        return Optional.empty();
    }

    static boolean isValidMcpHeaderArgumentType(TypeSymbol typeSymbol, SyntaxNodeAnalysisContext context) {
        TypeSymbol rawType = getRawType(typeSymbol);
        var types = context.semanticModel().types();
        return rawType.subtypeOf(types.STRING) || rawType.subtypeOf(types.INT)
                || rawType.subtypeOf(types.FLOAT) || rawType.subtypeOf(types.DECIMAL)
                || rawType.subtypeOf(types.BOOLEAN);
    }

    /**
     * Validates the type of a '@http:Header' annotated parameter consistently with http services: 'string', 'int',
     * 'float', 'decimal', 'boolean', arrays of those types, their nilable variants, or a closed record consisting of
     * those types.
     */
    static boolean isValidHeaderParamType(TypeSymbol typeSymbol, SyntaxNodeAnalysisContext context) {
        if (isValidHeaderValueType(typeSymbol, context)) {
            return true;
        }
        TypeSymbol rawType = getRawType(getNonNilType(typeSymbol));
        if (rawType instanceof RecordTypeSymbol recordTypeSymbol) {
            if (recordTypeSymbol.restTypeDescriptor().isPresent()) {
                return false;
            }
            return recordTypeSymbol.fieldDescriptors().values().stream()
                    .allMatch(field -> isValidHeaderValueType(field.typeDescriptor(), context));
        }
        return false;
    }

    private static boolean isValidHeaderValueType(TypeSymbol typeSymbol, SyntaxNodeAnalysisContext context) {
        TypeSymbol rawType = getRawType(typeSymbol);
        if (rawType.typeKind() == TypeDescKind.UNION) {
            // Consistent with http: a union is valid only when all its non-nil members share
            // a single basic type (covers nilable variants, enums, and finite string unions)
            var nonNilMembers = ((UnionTypeSymbol) rawType).memberTypeDescriptors().stream()
                    .filter(member -> member.typeKind() != TypeDescKind.NIL)
                    .toList();
            if (nonNilMembers.isEmpty()) {
                return false;
            }
            if (nonNilMembers.size() == 1) {
                return isValidHeaderValueType(nonNilMembers.getFirst(), context);
            }
            var types = context.semanticModel().types();
            for (TypeSymbol basicType : new TypeSymbol[]{types.STRING, types.INT, types.FLOAT,
                    types.DECIMAL, types.BOOLEAN}) {
                if (nonNilMembers.stream().allMatch(member -> member.subtypeOf(basicType))) {
                    return true;
                }
            }
            return false;
        }
        if (rawType.typeKind() == TypeDescKind.ARRAY) {
            return isValidHeaderValueType(((ArrayTypeSymbol) rawType).memberTypeDescriptor(), context);
        }
        return isBasicType(rawType, context);
    }

    private static boolean isBasicType(TypeSymbol typeSymbol, SyntaxNodeAnalysisContext context) {
        var types = context.semanticModel().types();
        TypeSymbol rawType = getRawType(typeSymbol);
        return rawType.subtypeOf(types.STRING) || rawType.subtypeOf(types.INT)
                || rawType.subtypeOf(types.FLOAT) || rawType.subtypeOf(types.DECIMAL)
                || rawType.subtypeOf(types.BOOLEAN);
    }

    private static TypeSymbol getNonNilType(TypeSymbol typeSymbol) {
        TypeSymbol rawType = getRawType(typeSymbol);
        if (rawType.typeKind() != TypeDescKind.UNION) {
            return typeSymbol;
        }
        var nonNilMembers = ((UnionTypeSymbol) rawType).memberTypeDescriptors().stream()
                .filter(member -> member.typeKind() != TypeDescKind.NIL)
                .toList();
        return nonNilMembers.size() == 1 ? nonNilMembers.get(0) : typeSymbol;
    }

    private static TypeSymbol getRawType(TypeSymbol typeSymbol) {
        if (typeSymbol.typeKind() == TypeDescKind.INTERSECTION) {
            return getRawType(((IntersectionTypeSymbol) typeSymbol).effectiveTypeDescriptor());
        }
        return typeSymbol.typeKind() == TypeDescKind.TYPE_REFERENCE
                ? getRawType(((TypeReferenceTypeSymbol) typeSymbol).typeDescriptor())
                : typeSymbol;
    }

    private static HttpSessionMode getSessionMode(FunctionDefinitionNode functionDefinitionNode,
                                              SemanticModel semanticModel) {
        ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) functionDefinitionNode.parent();
        if (serviceNode.metadata().isEmpty() || serviceNode.metadata().get().annotations().isEmpty()) {
            return HttpSessionMode.AUTO;
        }

        AnnotationNode transportConfigAnnotation =
                findMcpAnnotation(serviceNode, STREAMABLE_HTTP_CONFIG_ANNOTATION_NAME);
        if (transportConfigAnnotation != null) {
            return getSessionModeFieldValue(transportConfigAnnotation, semanticModel);
        }
        return HttpSessionMode.AUTO;
    }

    private static AnnotationNode findMcpAnnotation(ServiceDeclarationNode serviceNode, String annotationName) {
        for (AnnotationNode annotation : serviceNode.metadata().get().annotations()) {
            if (isMcpAnnotation(annotation, annotationName)) {
                return annotation;
            }
        }
        return null;
    }

    private static HttpSessionMode getSessionModeFieldValue(AnnotationNode annotationNode,
                                                            SemanticModel semanticModel) {
        if (annotationNode.annotValue().isEmpty()) {
            return HttpSessionMode.AUTO;
        }

        SeparatedNodeList<MappingFieldNode> fields = annotationNode.annotValue().get().fields();
        for (MappingFieldNode field : fields) {
            if (field.kind() == SyntaxKind.SPECIFIC_FIELD) {
                SpecificFieldNode specificField = (SpecificFieldNode) field;
                String fieldName = ((IdentifierToken) specificField.fieldName()).text();

                if (SESSION_MODE_FIELD.equals(fieldName) && specificField.valueExpr().isPresent()) {
                    return resolveSessionModeValue(specificField.valueExpr().get(), semanticModel);
                }
            }
        }

        return HttpSessionMode.AUTO;
    }

    private static HttpSessionMode resolveSessionModeValue(io.ballerina.compiler.syntax.tree.ExpressionNode valueExpr,
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
                        return HttpSessionMode.fromString(enumValue);
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
            return HttpSessionMode.fromString(literalValue);
        }

        return HttpSessionMode.AUTO;
    }

    private static boolean isMcpAnnotation(AnnotationNode annotation, String annotationName) {
        if (annotation.annotReference().kind() != SyntaxKind.QUALIFIED_NAME_REFERENCE) {
            return false;
        }

        QualifiedNameReferenceNode qualifiedRef = (QualifiedNameReferenceNode) annotation.annotReference();
        String modulePrefix = qualifiedRef.modulePrefix().text();
        String identifier = qualifiedRef.identifier().text();

        return MCP_PACKAGE_NAME.equals(modulePrefix) && annotationName.equals(identifier);
    }

    /**
     * Checks whether the semantic model in the given context contains any error-severity diagnostic.
     *
     * @param context the analysis context
     * @return {@code true} if at least one diagnostic is of severity {@code ERROR}
     */
    public static boolean hasCompilationErrors(SyntaxNodeAnalysisContext context) {
        for (Diagnostic diagnostic : context.semanticModel().diagnostics()) {
            if (diagnostic.diagnosticInfo().severity() == DiagnosticSeverity.ERROR) {
                return true;
            }
        }
        return false;
    }

    /**
     * Checks whether the document under analysis is a test source of its module.
     *
     * @param context the analysis context
     * @return {@code true} if the document is one of the module's test documents
     */
    public static boolean isInTestSource(SyntaxNodeAnalysisContext context) {
        Module currentModule = context.currentPackage().module(context.moduleId());
        return currentModule.testDocumentIds().contains(context.documentId());
    }

    /**
     * Checks whether the service in the analysis context is bound to a {@code ballerina/mcp} listener.
     *
     * @param context the analysis context
     * @return {@code true} if at least one listener type belongs to the {@code ballerina/mcp} module
     */
    public static boolean isMcpService(SyntaxNodeAnalysisContext context) {
        if (!(context.node() instanceof ServiceDeclarationNode)) {
            return false;
        }
        Optional<Symbol> symbol = context.semanticModel().symbol(context.node());
        if (symbol.isEmpty() || !(symbol.get() instanceof ServiceDeclarationSymbol serviceSymbol)) {
            return false;
        }
        return serviceSymbol.listenerTypes().stream().anyMatch(Utils::isMcpListenerType);
    }

    private static boolean isMcpListenerType(TypeSymbol listenerType) {
        if (listenerType.typeKind() == TypeDescKind.UNION) {
            return ((UnionTypeSymbol) listenerType).memberTypeDescriptors().stream()
                    .anyMatch(Utils::isMcpListenerType);
        }
        if (listenerType.typeKind() == TypeDescKind.TYPE_REFERENCE) {
            return ((TypeReferenceTypeSymbol) listenerType).typeDescriptor().getModule()
                    .map(Utils::isMcpModuleSymbol).orElse(false);
        }
        return false;
    }

    private static boolean isListenerFromMcpModule(TypeSymbol typeSymbol) {
        if (typeSymbol instanceof UnionTypeSymbol unionTypeSymbol) {
            return unionTypeSymbol.memberTypeDescriptors().stream()
                    .anyMatch(Utils::isListenerFromMcpModule);
        }
        return typeSymbol.getModule()
                .map(module -> MCP_PACKAGE_NAME.equals(module.id().moduleName())
                        && BALLERINA_ORG.equals(module.id().orgName()))
                .orElse(false);
    }
}
