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

import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.FunctionTypeSymbol;
import io.ballerina.compiler.api.symbols.ParameterSymbol;
import io.ballerina.compiler.api.symbols.ServiceDeclarationSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic;
import io.ballerina.tools.diagnostics.Location;

import java.util.List;
import java.util.Optional;

/**
 * Analysis task that validates the remote methods of an {@code mcp:StreamableHttpAdvancedService}.
 *
 * <p>The service type is an empty marker, so this task enforces the contract the type used to pin: the service
 * must declare {@code onListTools} and {@code onCallTool} remote methods, and their parameters are restricted to the
 * supported set (CallToolParams, Session, http:Headers, http:Request, and {@code @http:Header} parameters).</p>
 */
public class AdvancedServiceAnalysisTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String ON_CALL_TOOL = "onCallTool";
    private static final String ON_LIST_TOOLS = "onListTools";
    private static final String HTTP_HEADERS_DISPLAY = "http:Headers";
    private static final String HTTP_REQUEST_DISPLAY = "http:Request";
    private static final String SESSION_DISPLAY = "mcp:Session";
    private static final String CALL_TOOL_RESULT_DISPLAY = "mcp:CallToolResult|mcp:ServerError";
    private static final String LIST_TOOLS_RESULT_DISPLAY = "mcp:ListToolsResult|mcp:ServerError";

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) context.node();
        Optional<Symbol> symbol = context.semanticModel().symbol(serviceNode);
        if (symbol.isEmpty() || symbol.get().kind() != SymbolKind.SERVICE_DECLARATION) {
            return;
        }
        if (!isStreamableHttpAdvancedService((ServiceDeclarationSymbol) symbol.get())) {
            return;
        }

        Location serviceLocation = serviceNode.location();
        FunctionDefinitionNode onCallTool = null;
        FunctionDefinitionNode onListTools = null;

        // Locate the two known remote methods; any other remote method is unsupported.
        for (Node member : serviceNode.members()) {
            if (!(member instanceof FunctionDefinitionNode functionNode) || !hasRemoteQualifier(functionNode)) {
                continue;
            }
            String methodName = functionNode.functionName().text();
            if (ON_CALL_TOOL.equals(methodName)) {
                onCallTool = functionNode;
            } else if (ON_LIST_TOOLS.equals(methodName)) {
                onListTools = functionNode;
            } else {
                report(context, CompilationDiagnostic.ADVANCED_UNKNOWN_REMOTE_METHOD,
                        functionNode.location(), methodName);
            }
        }

        if (onCallTool == null) {
            report(context, CompilationDiagnostic.ADVANCED_SERVICE_MISSING_METHOD, serviceLocation, ON_CALL_TOOL);
        } else {
            validateMethod(context, onCallTool, ON_CALL_TOOL, true);
        }

        if (onListTools == null) {
            report(context, CompilationDiagnostic.ADVANCED_SERVICE_MISSING_METHOD, serviceLocation, ON_LIST_TOOLS);
        } else {
            validateMethod(context, onListTools, ON_LIST_TOOLS, false);
        }
    }

    private static boolean isStreamableHttpAdvancedService(ServiceDeclarationSymbol serviceSymbol) {
        Optional<TypeSymbol> typeDescriptor = serviceSymbol.typeDescriptor();
        return typeDescriptor.isPresent()
                && Utils.STREAMABLE_HTTP_ADVANCED_SERVICE_NAME.equals(typeDescriptor.get().getName().orElse(""))
                && Utils.isMcpModuleSymbol(typeDescriptor.get());
    }

    private static boolean hasRemoteQualifier(FunctionDefinitionNode functionNode) {
        return functionNode.qualifierList().stream()
                .anyMatch(token -> token.kind() == SyntaxKind.REMOTE_KEYWORD);
    }

    private void validateMethod(SyntaxNodeAnalysisContext context, FunctionDefinitionNode functionNode,
                                String methodName, boolean isCallTool) {
        Optional<Symbol> symbol = context.semanticModel().symbol(functionNode);
        if (symbol.isEmpty() || !(symbol.get() instanceof FunctionSymbol functionSymbol)) {
            return;
        }
        FunctionTypeSymbol functionType = functionSymbol.typeDescriptor();
        Location location = functionNode.location();

        int callToolParamsCount = 0;
        boolean hasHeaders = false;
        boolean hasRequest = false;
        boolean hasSession = false;

        for (ParameterSymbol parameter : functionType.params().orElse(List.of())) {
            TypeSymbol type = parameter.typeDescriptor();
            String paramName = parameter.getName().orElse(Utils.UNKNOWN_SYMBOL);
            Location paramLocation = parameter.getLocation().orElse(location);

            if (Utils.hasHttpHeaderAnnotation(parameter)) {
                if (!Utils.isValidHeaderParamType(type, context)) {
                    report(context, CompilationDiagnostic.INVALID_HEADER_PARAMETER_TYPE, paramLocation,
                            methodName, paramName);
                }
            } else if (Utils.isHttpHeadersType(type)) {
                if (hasHeaders) {
                    report(context, CompilationDiagnostic.DUPLICATE_PARAMETER, paramLocation,
                            methodName, paramName, HTTP_HEADERS_DISPLAY);
                }
                hasHeaders = true;
            } else if (Utils.isHttpRequestType(type)) {
                if (hasRequest) {
                    report(context, CompilationDiagnostic.DUPLICATE_PARAMETER, paramLocation,
                            methodName, paramName, HTTP_REQUEST_DISPLAY);
                }
                hasRequest = true;
            } else if (isCallTool && Utils.isCallToolParamsType(type)) {
                callToolParamsCount++;
            } else if (isCallTool && isSessionParam(type)) {
                if (hasSession) {
                    report(context, CompilationDiagnostic.DUPLICATE_PARAMETER, paramLocation,
                            methodName, paramName, SESSION_DISPLAY);
                }
                hasSession = true;
            } else {
                String supportedTypes = isCallTool
                        ? Utils.ADVANCED_SUPPORTED_PARAM_TYPES : Utils.ADVANCED_LIST_TOOLS_SUPPORTED_PARAM_TYPES;
                report(context, CompilationDiagnostic.INVALID_PARAMETER_TYPE, paramLocation,
                        methodName, paramName, supportedTypes);
            }
        }

        if (isCallTool && callToolParamsCount != 1) {
            report(context, CompilationDiagnostic.ADVANCED_ON_CALL_TOOL_PARAMS, location, methodName);
        }

        String expectedResultType = isCallTool
                ? Utils.CALL_TOOL_RESULT_TYPE_NAME : Utils.LIST_TOOLS_RESULT_TYPE_NAME;
        String expectedDisplay = isCallTool ? CALL_TOOL_RESULT_DISPLAY : LIST_TOOLS_RESULT_DISPLAY;
        if (!returnTypeContains(functionType, expectedResultType)) {
            report(context, CompilationDiagnostic.ADVANCED_INVALID_RETURN_TYPE, location, methodName, expectedDisplay);
        }
    }

    /**
     * Returns whether the type is {@code mcp:Session} or a nilable {@code mcp:Session?}. Session is typically declared
     * nilable because it is absent in stateless mode.
     */
    private static boolean isSessionParam(TypeSymbol type) {
        if (Utils.isSessionType(type)) {
            return true;
        }
        if (type.typeKind() != TypeDescKind.UNION) {
            return false;
        }
        List<TypeSymbol> nonNilMembers = ((UnionTypeSymbol) type).memberTypeDescriptors().stream()
                .filter(member -> member.typeKind() != TypeDescKind.NIL)
                .toList();
        return nonNilMembers.size() == 1 && Utils.isSessionType(nonNilMembers.get(0));
    }

    private static boolean returnTypeContains(FunctionTypeSymbol functionType, String typeName) {
        return functionType.returnTypeDescriptor()
                .map(returnType -> typeMatches(returnType, typeName))
                .orElse(false);
    }

    private static boolean typeMatches(TypeSymbol type, String typeName) {
        if (type.typeKind() == TypeDescKind.UNION) {
            return ((UnionTypeSymbol) type).memberTypeDescriptors().stream()
                    .anyMatch(member -> typeMatches(member, typeName));
        }
        if (typeName.equals(type.getName().orElse("")) && Utils.isMcpModuleSymbol(type)) {
            return true;
        }
        if (type.typeKind() == TypeDescKind.TYPE_REFERENCE) {
            return typeMatches(((TypeReferenceTypeSymbol) type).typeDescriptor(), typeName);
        }
        return false;
    }

    private void report(SyntaxNodeAnalysisContext context, CompilationDiagnostic diagnostic, Location location,
                        Object... args) {
        context.reportDiagnostic(CompilationDiagnostic.getDiagnostic(diagnostic, location, args));
    }
}
