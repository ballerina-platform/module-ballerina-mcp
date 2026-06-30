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


package io.ballerina.stdlib.mcp.plugin.endpointyaml.generator;

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.api.symbols.ModuleSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.CheckExpressionNode;
import io.ballerina.compiler.syntax.tree.ExplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionArgumentNode;
import io.ballerina.compiler.syntax.tree.ImplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.ListenerDeclarationNode;
import io.ballerina.compiler.syntax.tree.NamedArgumentNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeParser;
import io.ballerina.compiler.syntax.tree.ParenthesizedArgList;
import io.ballerina.compiler.syntax.tree.PositionalArgumentNode;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.SyntaxTree;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.runtime.api.utils.IdentifierUtils;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;

import java.util.Map;
import java.util.Optional;

/**
 * Extracts the endpoint metadata (port, base path, type) of an MCP service declaration. The extracted endpoints are
 * collected and written to a single {@code endpoints.yaml} artifact by {@code McpEndpointArtifactTask}.
 */
public class EndpointYamlGenerator {

    private final ServiceDeclarationNode node;
    private final SyntaxNodeAnalysisContext context;

    private int port;
    final PackageMemberVisitor packageMemberVisitor = new PackageMemberVisitor();

    private static final String TYPE = "mcp";

    private record ListenerInfo(Optional<ParenthesizedArgList> argList) {
    }

    /**
     * Creates a generator for the service declaration in the given analysis context.
     *
     * @param context the analysis context whose node is the service declaration
     */
    public EndpointYamlGenerator(SyntaxNodeAnalysisContext context) {
        this.node = (ServiceDeclarationNode) context.node();
        this.context = context;
    }

    /**
     * Resolves the endpoint metadata of the service by extracting its listener port and base path.
     *
     * @return the extracted endpoint
     */
    public Endpoint getEndpoint() {
        String moduleName = context.currentPackage().module(context.moduleId()).moduleName().toString();
        ensureModuleVisited(moduleName);

        ListenerInfo listenerInfo = resolveListenerInfo(moduleName);
        port = resolvePort(listenerInfo.argList());
        String basePath = buildBasePath();

        return new Endpoint(port, basePath, TYPE);
    }

    private void ensureModuleVisited(String moduleName) {
        Map<String, ModuleMemberVisitor> moduleVisitors = packageMemberVisitor
                .createModuleVisitor(moduleName, context.semanticModel());
        ModuleMemberVisitor moduleMemberVisitor = moduleVisitors.get(moduleName);
        packageMemberVisitor.setModuleVisitors(moduleVisitors);

        context.currentPackage()
                .module(context.moduleId())
                .documentIds()
                .forEach(docId -> {
                    SyntaxTree tree = context.currentPackage()
                            .module(context.moduleId())
                            .document(docId)
                            .syntaxTree();
                    tree.rootNode().accept(moduleMemberVisitor);
                });

    }

    /**
     * Resolves the listener argument list of the service, handling inline {@code new} expressions as well as references
     * to named listener declarations.
     *
     * @param moduleName the module of the service declaration
     * @return the resolved listener information
     */
    private ListenerInfo resolveListenerInfo(String moduleName) {
        Optional<ParenthesizedArgList> argList = Optional.empty();
        SemanticModel semanticModel = context.semanticModel();

        for (ExpressionNode raw : node.expressions()) {
            ExpressionNode expr = unwrapCheckExpression(raw);

            if (expr.kind().equals(SyntaxKind.EXPLICIT_NEW_EXPRESSION)) {
                ExplicitNewExpressionNode explicit = (ExplicitNewExpressionNode) expr;
                argList = Optional.ofNullable(explicit.parenthesizedArgList());
            } else if (expr.kind().equals(SyntaxKind.IMPLICIT_NEW_EXPRESSION)) {
                ImplicitNewExpressionNode implicit = (ImplicitNewExpressionNode) expr;
                argList = implicit.parenthesizedArgList();
            } else if (isNameReference(expr)) {
                ListenerInfo resolution = resolveNamedListener(expr, moduleName, semanticModel);
                argList = resolution.argList();
            }
        }

        return new ListenerInfo(argList);
    }

    private ExpressionNode unwrapCheckExpression(ExpressionNode expr) {
        if (expr.kind().equals(SyntaxKind.CHECK_EXPRESSION)) {
            return ((CheckExpressionNode) expr).expression();
        }
        return expr;
    }

    private boolean isNameReference(ExpressionNode expr) {
        return expr.kind().equals(SyntaxKind.SIMPLE_NAME_REFERENCE) ||
                expr.kind().equals(SyntaxKind.QUALIFIED_NAME_REFERENCE);
    }

    private ListenerInfo resolveNamedListener(ExpressionNode expr, String moduleName,
                                              SemanticModel semanticModel) {
        String listenerModuleName = getModuleName(semanticModel, expr);
        if (listenerModuleName.isEmpty()) {
            listenerModuleName = moduleName;
        }

        String listenerName;

        if (expr instanceof QualifiedNameReferenceNode refNode) {
            listenerName = unescapeIdentifier(refNode.identifier().text().trim());
        } else {
            listenerName = unescapeIdentifier(expr.toString().trim());
        }

        Optional<ListenerDeclarationNode> declOpt =
                packageMemberVisitor.getListenerDeclaration(listenerModuleName, listenerName);

        if (declOpt.isEmpty()) {
            return new ListenerInfo(Optional.empty());
        }

        ListenerDeclarationNode decl = declOpt.get();
        Optional<ParenthesizedArgList> argList = extractArgListFromListenerDecl(decl);
        return new ListenerInfo(argList);
    }

    private Optional<ParenthesizedArgList> extractArgListFromListenerDecl(ListenerDeclarationNode decl) {
        Node initNode = decl.initializer();
        if (initNode == null) {
            return Optional.empty();
        }
        ExpressionNode initializer = (ExpressionNode) initNode;
        initializer = unwrapCheckExpression(initializer);

        return switch (initializer.kind()) {
            case EXPLICIT_NEW_EXPRESSION ->
                    Optional.ofNullable(((ExplicitNewExpressionNode) initializer).parenthesizedArgList());
            case IMPLICIT_NEW_EXPRESSION -> ((ImplicitNewExpressionNode) initializer).parenthesizedArgList();
            default -> Optional.empty();
        };
    }

    /**
     * Resolves the port from the listener argument list, checking the positional argument first and then any
     * {@code port} named argument.
     *
     * @param argListOpt the listener argument list, if available
     * @return the resolved port, or {@code 0} if it cannot be determined
     */
    private int resolvePort(Optional<ParenthesizedArgList> argListOpt) {
        if (argListOpt.isEmpty()) {
            return 0;
        }
        SeparatedNodeList<FunctionArgumentNode> arguments = argListOpt.get().arguments();
        int index = resolvePortFromPositionalArgs(arguments);
        resolvePortFromNamedArgs(arguments, index);
        return port;
    }

    private int resolvePortFromPositionalArgs(SeparatedNodeList<FunctionArgumentNode> arguments) {
        int index = 0;
        for (; index < arguments.size(); index++) {
            FunctionArgumentNode arg = arguments.get(index);
            if (arg instanceof NamedArgumentNode) {
                break;
            }
            if (index == 0) {
                PositionalArgumentNode portArg = (PositionalArgumentNode) arg;
                String portVal = getPortValue(portArg.expression(), context.semanticModel(), context).orElse(null);
                assignPortIfParseable(portVal);
            }
        }
        return index;
    }

    private void resolvePortFromNamedArgs(SeparatedNodeList<FunctionArgumentNode> arguments, int startIndex) {
        for (int i = startIndex; i < arguments.size(); i++) {
            FunctionArgumentNode arg = arguments.get(i);
            if (arg instanceof NamedArgumentNode namedArg &&
                    namedArg.argumentName().toString().trim().equals("port")) {
                String portValue = getPortValue(namedArg.expression(), context.semanticModel(), context)
                        .orElse(null);
                assignPortIfParseable(portValue);
            }
        }
    }

    private void assignPortIfParseable(String portValue) {
        if (portValue == null) {
            return;
        }
        try {
            port = Integer.parseInt(portValue);
        } catch (NumberFormatException ignored) {

        }
    }

    private String buildBasePath() {
        StringBuilder basePath = new StringBuilder();
        for (Node identifierNode : node.absoluteResourcePath()) {
            basePath.append(identifierNode.toString().replace("\"", "").trim());
        }
        return basePath.toString();
    }

    private Optional<String> getPortValue(ExpressionNode expression, SemanticModel semanticModel,
                                          SyntaxNodeAnalysisContext context) {
        return getPortValue(expression, false, semanticModel, context);
    }

    /**
     * Resolves a port expression to its literal value, following variable and constant references and reporting
     * diagnostics for configurable ports without a usable default.
     *
     * @param expression         the port expression
     * @param isConfigurablePort whether the port is reached through a configurable declaration
     * @param semanticModel      the semantic model
     * @param context            the analysis context used to report diagnostics
     * @return the resolved port literal, or empty if it cannot be determined
     */
    private Optional<String> getPortValue(ExpressionNode expression, boolean isConfigurablePort,
                                          SemanticModel semanticModel, SyntaxNodeAnalysisContext context) {
        if (expression.kind().equals(SyntaxKind.NUMERIC_LITERAL)) {
            return resolveNumericLiteral(expression);
        }
        if (!isNameReference(expression)) {
            return Optional.empty();
        }
        return resolvePortFromVariable(expression, semanticModel, context, isConfigurablePort);
    }

    private Optional<String> resolveNumericLiteral(ExpressionNode expression) {
        BasicLiteralNode literal = (BasicLiteralNode) expression;
        return Optional.of(literal.literalToken().text());
    }

    private Optional<String> resolvePortFromVariable(ExpressionNode expression,
                                                     SemanticModel semanticModel,
                                                     SyntaxNodeAnalysisContext context, boolean isConfigurablePort) {
        String moduleName = getModuleName(semanticModel, expression);
        String portVariableName = extractVariableName(expression);

        Optional<ModuleMemberVisitor.VariableDeclaredValue> varOpt =
                packageMemberVisitor.getVariableDeclaredValue(moduleName, portVariableName);

        if (varOpt.isEmpty()) {
            return Optional.empty();
        }

        ModuleMemberVisitor.VariableDeclaredValue varVal = varOpt.get();
        if (varVal.isRequired()) {
            // A required configurable (`= ?`) has no build-time value; warn and fall back to port 0 without failing
            // the build.
            reportRequiredConfigurablePortDiagnostic(context);
            return Optional.empty();
        }
        String portValueSource = String.valueOf(varVal.value());
        ExpressionNode portExpr = portValueSource.isEmpty() ? null : NodeParser.parseExpression(portValueSource);

        if (portExpr == null || portExpr.isMissing()) {
            return Optional.empty();
        }

        return resolvePortExpression(portExpr, varVal.isConfigurable(), isConfigurablePort, semanticModel, context);
    }

    private String extractVariableName(ExpressionNode expression) {
        if (expression instanceof QualifiedNameReferenceNode refNode) {
            return unescapeIdentifier(refNode.identifier().text().trim());
        }
        return unescapeIdentifier(expression.toString().trim());
    }

    private Optional<String> resolvePortExpression(ExpressionNode portExpr, boolean isConfigurable,
                                                   boolean isConfigurablePort,
                                                   SemanticModel semanticModel,
                                                   SyntaxNodeAnalysisContext context) {
        if (isConfigurable || isConfigurablePort) {
            reportDefaultPortConfigDiagnostic(context);
        }
        if (portExpr.kind().equals(SyntaxKind.NUMERIC_LITERAL)) {
            return resolveNumericLiteral(portExpr);
        }
        return getPortValue(portExpr, isConfigurable, semanticModel, context);
    }

    private void reportRequiredConfigurablePortDiagnostic(SyntaxNodeAnalysisContext context) {
        DiagnosticInfo diagnosticInfo = new DiagnosticInfo(
                "PORT_REQUIRED_WITHOUT_DEFAULT",
                "The port is a required configurable with no default value, so it cannot be determined at build " +
                        "time. Generating endpoint information with port 0 when the --export-endpoints flag is present",
                DiagnosticSeverity.WARNING
        );
        context.reportDiagnostic(DiagnosticFactory.createDiagnostic(diagnosticInfo, context.node().location()));
    }

    private void reportDefaultPortConfigDiagnostic(SyntaxNodeAnalysisContext context) {
        DiagnosticInfo diagnosticInfo = new DiagnosticInfo(
                "CONFIGURABLE_PORT_DEFAULT_USED",
                "The server port is defined as a configurable. Hence, " +
                        "using the default value to generate the server information " +
                        "when --export-endpoints flag is present",
                DiagnosticSeverity.WARNING
        );
        context.reportDiagnostic(DiagnosticFactory.createDiagnostic(diagnosticInfo, context.node().location()));
    }

    /**
     * Unescapes a Ballerina identifier, stripping escape characters and quoting.
     *
     * @param parameterName the raw identifier text
     * @return the unescaped identifier
     */
    public static String unescapeIdentifier(String parameterName) {
        String unescapedParamName = IdentifierUtils.unescapeBallerina(parameterName);
        return unescapedParamName.replace("\\\\", "").replace("'", "");
    }

    /**
     * Returns the name of the module that owns the symbol of the given node.
     *
     * @param semanticModel the semantic model
     * @param node          the node whose owning module is resolved
     * @return the module name, or an empty string if it cannot be resolved
     */
    public static String getModuleName(SemanticModel semanticModel, Node node) {
        Optional<Symbol> symbol = semanticModel.symbol(node);
        if (symbol.isEmpty()) {
            return "";
        }
        return getModuleName(symbol.get());
    }

    /**
     * Returns the name of the module that owns the given symbol.
     *
     * @param symbol the symbol whose owning module is resolved
     * @return the module name, or an empty string if it cannot be resolved
     */
    public static String getModuleName(Symbol symbol) {
        Optional<ModuleSymbol> module = symbol.getModule();
        if (module.isEmpty()) {
            return "";
        }
        return module.get().id().moduleName();
    }

}
