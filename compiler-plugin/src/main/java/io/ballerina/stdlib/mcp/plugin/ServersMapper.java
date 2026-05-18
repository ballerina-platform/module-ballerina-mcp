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
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.VariableSymbol;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.CheckExpressionNode;
import io.ballerina.compiler.syntax.tree.ExplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionArgumentNode;
import io.ballerina.compiler.syntax.tree.ImplicitNewExpressionNode;
import io.ballerina.compiler.syntax.tree.ListenerDeclarationNode;
import io.ballerina.compiler.syntax.tree.MappingConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.NamedArgumentNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.ParenthesizedArgList;
import io.ballerina.compiler.syntax.tree.PositionalArgumentNode;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.SeparatedNodeList;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.openapi.service.mapper.utils.MapperCommonUtils;
import io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.Location;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.servers.Server;
import io.swagger.v3.oas.models.servers.ServerVariable;
import io.swagger.v3.oas.models.servers.ServerVariables;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

import static io.ballerina.stdlib.mcp.plugin.OpenAPIGenerator.NullLocation;
import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic.UNABLE_TO_OBTAIN_VALID_SERVER_PORT;
import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic
        .UNABLE_TO_OBTAIN_VALID_SERVER_PORT_FROM_EXPRESSION;
import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic.getDiagnostic;

/**
 * Maps Ballerina service listeners to OpenAPI {@link Server} definitions by extracting host and port information.
 * Modifies the given OpenAPI instance by adding the mapped server details.
 */
public class ServersMapper {
    private static final String SERVER = "server";
    private static final String PORT = "port";
    private static final String HOST_FIELD_NAME = "host";
    private static final String LISTEN_ON = "listenOn";
    private static final String DEFAULT_HTTP_PORT = "9090";
    private static final String PORT_443 = "443";
    private static final String HTTPS_LOCALHOST = "https://localhost";
    private static final String HTTP_LOCALHOST = "http://localhost";

    private final OpenAPI openAPI;
    private final Map<String, ListenerDeclarationNode> endpoints;
    private final ServiceDeclarationNode service;
    private final SemanticModel semanticModel;
    private final List<Diagnostic> diagnostics = new ArrayList<>();

    public ServersMapper(OpenAPI openAPI, Set<ListenerDeclarationNode> endpoints,
                         ServiceDeclarationNode service, SemanticModel semanticModel) {
        this.openAPI = openAPI;
        this.endpoints = mapEndpoints(endpoints);
        this.service = service;
        this.semanticModel = semanticModel;
    }

    private static Map<String, ListenerDeclarationNode> mapEndpoints(Set<ListenerDeclarationNode> nodes) {
        return nodes.stream()
                .collect(Collectors.toMap(node -> node.variableName().text(), Function.identity()));
    }

    public void setServers() {
        extractServersFromServiceExpressions();

        List<Server> servers = this.openAPI.getServers();
        if (!endpoints.isEmpty()) {
            for (ListenerDeclarationNode endpoint : endpoints.values()) {
                for (ExpressionNode expression : this.service.expressions()) {
                    addServerForEndpoint(servers, endpoint, expression);
                }
            }
        }

        if (isServerListEmpty()) {
            this.openAPI.setServers(Collections.singletonList(getDefaultServerWithBasePath(getServiceBasePath())));
        } else if (servers.size() > 1) {
            this.openAPI.setServers(Collections.singletonList(mergeServerEnums(servers)));
        }
    }

    private boolean isServerListEmpty() {
        return this.openAPI.getServers().isEmpty() || this.openAPI.getServers().stream()
                .allMatch(server -> server.getUrl() == null
                        && (server.getVariables() == null || server.getVariables().isEmpty()));
    }

    private void addServerForEndpoint(List<Server> servers, ListenerDeclarationNode endpoint, ExpressionNode expNode) {
        String endpointName = endpoint.variableName().text().trim();

        boolean matchesEndpoint = (expNode instanceof QualifiedNameReferenceNode qualifiedNameReferenceNode
                && qualifiedNameReferenceNode.identifier().text().trim().equals(endpointName))
                || expNode.toString().trim().equals(endpointName);

        if (matchesEndpoint) {
            servers.add(extractServer(endpoint, getServiceBasePath()));
        }
    }

    private static Server mergeServerEnums(List<Server> servers) {
        if (servers.isEmpty()) {
            return null;
        }

        Server mainServer = servers.getFirst();
        ServerVariables mainVars = mainServer.getVariables();
        ServerVariable hostVar = mainVars.get(SERVER);
        ServerVariable portVar = mainVars.get(PORT);

        if (servers.size() > 1) {
            List<Server> rotated = new ArrayList<>(servers);
            Collections.rotate(rotated, servers.size() - 1);

            for (Server server : rotated) {
                ServerVariables vars = server.getVariables();
                if (vars.get(SERVER) != null) {
                    hostVar.addEnumItem(vars.get(SERVER).getDefault());
                }
                if (vars.get(PORT) != null) {
                    portVar.addEnumItem(vars.get(PORT).getDefault());
                }
            }
        }
        return mainServer;
    }

    private Server extractServer(ListenerDeclarationNode endpoint, String basePath) {
        Node initializer = endpoint.initializer();
        Optional<ParenthesizedArgList> argList;

        if (initializer.kind() == SyntaxKind.CHECK_EXPRESSION) {
            ExpressionNode innerExpr = ((CheckExpressionNode) initializer).expression();
            argList = extractParenthesizedArgList(innerExpr);
        } else {
            argList = extractParenthesizedArgList(initializer);
        }
        return generateServer(basePath, argList);
    }

    private static Optional<ParenthesizedArgList> extractParenthesizedArgList(Node expression) {
        return switch (expression.kind()) {
            case EXPLICIT_NEW_EXPRESSION ->
                    Optional.ofNullable(((ExplicitNewExpressionNode) expression).parenthesizedArgList());
            case IMPLICIT_NEW_EXPRESSION -> ((ImplicitNewExpressionNode) expression).parenthesizedArgList();
            default -> Optional.empty();
        };
    }

    private void extractServersFromServiceExpressions() {
        List<Server> servers = new ArrayList<>();
        String basePath = getServiceBasePath();

        for (ExpressionNode expression : this.service.expressions()) {
            if (expression.kind() == SyntaxKind.EXPLICIT_NEW_EXPRESSION) {
                ExplicitNewExpressionNode explicit = (ExplicitNewExpressionNode) expression;
                servers.add(generateServer(basePath, Optional.ofNullable(explicit.parenthesizedArgList())));
            }
        }
        openAPI.setServers(servers);
    }

    private Server generateServer(String basePath, Optional<ParenthesizedArgList> argListOpt) {
        ServerVariables serverVars = new ServerVariables();
        String port = null;
        String host = null;

        if (argListOpt.isPresent()) {
            SeparatedNodeList<FunctionArgumentNode> args = argListOpt.get().arguments();
            if (!args.isEmpty()) {
                FunctionArgumentNode firstArg = args.get(0);
                if (firstArg instanceof PositionalArgumentNode posArg) {
                    Optional<Symbol> symbol = semanticModel.symbol(posArg.expression());
                    if (symbol.isPresent() && symbol.get() instanceof VariableSymbol
                            && endpoints.containsKey(posArg.expression().toSourceCode().strip())) {
                        String varName = posArg.expression().toSourceCode().strip();
                        var httpListenerArgList = extractParenthesizedArgList(endpoints.get(varName).initializer());
                        return generateServer(basePath, httpListenerArgList);
                    }
                    port = getValidPort(firstArg);
                } else if (firstArg instanceof NamedArgumentNode namedArg
                        && (namedArg.argumentName().name().text().strip().equals(PORT)
                        || namedArg.argumentName().name().text().strip().equals(LISTEN_ON))) {
                    Optional<Symbol> symbol = semanticModel.symbol(namedArg.expression());
                    if (symbol.isPresent() && symbol.get() instanceof VariableSymbol
                            && endpoints.containsKey(namedArg.expression().toSourceCode().strip())) {
                        String varName = namedArg.expression().toSourceCode().strip();
                        var httpListenerArgList = extractParenthesizedArgList(endpoints.get(varName).initializer());
                        return generateServer(basePath, httpListenerArgList);
                    }
                    port = getValidPort(firstArg);
                }
                // The following condition is only true when the argList is of an http:Listener
                if (args.size() > 1) {
                    FunctionArgumentNode secondArg = args.get(1);
                    if (secondArg instanceof NamedArgumentNode namedArg
                            && HOST_FIELD_NAME.equals(namedArg.argumentName().name().text())) {
                        host = extractHost(namedArg);
                    } else if (secondArg instanceof PositionalArgumentNode posArg
                            && posArg.expression() instanceof MappingConstructorExpressionNode mapping) {
                        host = extractHost(mapping);
                    }
                }
            }
        }

        return buildServer(basePath, port, host, serverVars);
    }

    private String extractHost(NamedArgumentNode namedArg) {
        if (namedArg.expression() instanceof BasicLiteralNode bln) {
            return bln.toSourceCode().replaceAll("\"", "").trim();
        }
        return null;
    }

    private static String extractHost(MappingConstructorExpressionNode mapping) {
        for (MappingFieldNode field : mapping.fields()) {
            if (field instanceof SpecificFieldNode specific && HOST_FIELD_NAME.equals(specific.fieldName().toString())
                    && specific.valueExpr().isPresent()) {
                return specific.valueExpr().get().toString().replaceAll("\"", "");
            }
        }
        return null;
    }

    private String getValidPort(FunctionArgumentNode functionArgumentNode) {
        String text = functionArgumentNode.toString();
        if (functionArgumentNode instanceof NamedArgumentNode namedArgumentNode) {
            text = namedArgumentNode.expression().toSourceCode().trim();
        } else if (functionArgumentNode instanceof PositionalArgumentNode positionalArgumentNode) {
            text = positionalArgumentNode.expression().toSourceCode().trim();
        }
        if (text.matches(".*http:getDefaultListener.*$")) {
            return DEFAULT_HTTP_PORT;
        }
        if (text.matches("\\d+")) {
            return text;
        }
        addDiagnosticWarning(UNABLE_TO_OBTAIN_VALID_SERVER_PORT_FROM_EXPRESSION,
                functionArgumentNode.location(),
                functionArgumentNode.toSourceCode().strip(), DEFAULT_HTTP_PORT);
        return DEFAULT_HTTP_PORT;
    }

    private Server buildServer(String basePath, String port, String host, ServerVariables serverVars) {
        if (port == null) {
            addDiagnosticWarning(UNABLE_TO_OBTAIN_VALID_SERVER_PORT, new NullLocation(), DEFAULT_HTTP_PORT);
            port = DEFAULT_HTTP_PORT;
        }
        ServerVariable serverVar = new ServerVariable();
        serverVar._default(host != null ? host : (port.equals(PORT_443) ? HTTPS_LOCALHOST : HTTP_LOCALHOST));

        ServerVariable portVar = new ServerVariable();
        portVar._default(port);

        serverVars.addServerVariable(SERVER, serverVar);
        serverVars.addServerVariable(PORT, portVar);

        Server server = new Server();
        server.setVariables(serverVars);
        server.setUrl(String.format("{server}:{port}%s", basePath));
        return server;
    }

    private void addDiagnosticWarning(CompilationDiagnostic compilationDiagnostic, Location location, Object... args) {
        Diagnostic diagnostic = getDiagnostic(compilationDiagnostic, location, args);
        this.diagnostics.add(diagnostic);
    }

    private Server getDefaultServerWithBasePath(String basePath) {
        return buildServer(basePath, null, null, new ServerVariables());
    }

    private String getServiceBasePath() {
        StringBuilder path = new StringBuilder();
        for (Node node : this.service.absoluteResourcePath()) {
            path.append(MapperCommonUtils.unescapeIdentifier(node.toString()));
        }
        return path.toString().trim();
    }

    public List<Diagnostic> getDiagnostics() {
        return Collections.unmodifiableList(this.diagnostics);
    }
}
