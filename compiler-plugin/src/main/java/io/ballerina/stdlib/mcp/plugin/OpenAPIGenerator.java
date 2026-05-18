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
import io.ballerina.compiler.api.symbols.ClassSymbol;
import io.ballerina.compiler.api.symbols.ServiceDeclarationSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.syntax.tree.ListenerDeclarationNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.SyntaxTree;
import io.ballerina.openapi.service.mapper.diagnostic.ExceptionDiagnostic;
import io.ballerina.openapi.service.mapper.diagnostic.OpenAPIMapperDiagnostic;
import io.ballerina.openapi.service.mapper.model.ServiceDeclaration;
import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.Module;
import io.ballerina.projects.Package;
import io.ballerina.projects.Project;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;
import io.ballerina.tools.text.LinePosition;
import io.ballerina.tools.text.LineRange;
import io.ballerina.tools.text.TextRange;
import io.swagger.v3.core.util.Yaml;
import io.swagger.v3.oas.models.OpenAPI;

import java.io.IOException;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static io.ballerina.openapi.service.mapper.Constants.HYPHEN;
import static io.ballerina.openapi.service.mapper.Constants.OPENAPI_SUFFIX;
import static io.ballerina.openapi.service.mapper.Constants.SLASH;
import static io.ballerina.openapi.service.mapper.Constants.YAML_EXTENSION;
import static io.ballerina.openapi.service.mapper.diagnostic.DiagnosticMessages.OAS_CONVERTOR_108;
import static io.ballerina.openapi.service.mapper.utils.CodegenUtils.resolveContractFileName;
import static io.ballerina.openapi.service.mapper.utils.CodegenUtils.writeFile;
import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.containErrors;
import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.getNormalizedFileName;
import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic.OPENAPI_GENERATION_FAILED;
import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic.getDiagnostic;

/**
 * Compiler-plugin analysis task that emits an OpenAPI YAML contract for each {@code mcp:Service} when
 * {@code --export-openapi} is enabled. The contract describes the listener-derived server endpoint so that
 * downstream tooling (e.g. Choreo/Devant component config) can derive the host, port, and base path of the
 * MCP service.
 */
public class OpenAPIGenerator implements AnalysisTask<SyntaxNodeAnalysisContext> {
    public static final String OPENAPI = "openapi";
    public static final String OAS_PATH_SEPARATOR = "/";
    public static final String UNDERSCORE = "_";
    public static final String BALLERINA = "ballerina";
    public static final String MCP = "mcp";
    public static final String EMPTY = "";
    public static final String LISTENER = "Listener";

    static boolean isErrorPrinted = false;

    static void setIsWarningPrinted() {
        OpenAPIGenerator.isErrorPrinted = true;
    }

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        SemanticModel semanticModel = context.semanticModel();
        SyntaxTree syntaxTree = context.syntaxTree();
        Package currentPackage = context.currentPackage();
        Project project = currentPackage.project();
        BuildOptions buildOptions = project.buildOptions();
        if (!buildOptions.exportOpenAPI()) {
            return;
        }
        boolean hasErrors = context.compilation().diagnosticResult()
                .diagnostics().stream()
                .anyMatch(d -> DiagnosticSeverity.ERROR.equals(d.diagnosticInfo().severity()));

        if (hasErrors) {
            if (!isErrorPrinted) {
                setIsWarningPrinted();
                PrintStream outStream = System.out;
                outStream.println("openapi contract generation for mcp service is skipped because of the " +
                        "following compilation error(s) in the ballerina package:");
            }
            return;
        }

        Path outPath = project.targetDir();
        ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) context.node();
        Map<Integer, String> services = new HashMap<>();
        List<Diagnostic> diagnostics = new ArrayList<>();

        try {
            if (containErrors(semanticModel.diagnostics())) {
                diagnostics.addAll(semanticModel.diagnostics());
            } else if (isMcpService(serviceNode, semanticModel)) {
                generateOpenAPISpec(semanticModel, serviceNode, syntaxTree, services, project, outPath, diagnostics);
            }
        } catch (Exception e) {
            // Catch-all so the patch never breaks a previously-compiling build. Surface the failure as a warning
            // and continue; the project still builds, the OpenAPI artifact is just missing.
            diagnostics.add(getDiagnostic(OPENAPI_GENERATION_FAILED, serviceNode.location(), e.toString()));
        }
        if (!diagnostics.isEmpty()) {
            for (Diagnostic diagnostic : diagnostics) {
                context.reportDiagnostic(diagnostic);
            }
        }
    }

    private void generateOpenAPISpec(SemanticModel semanticModel, ServiceDeclarationNode serviceNode,
                                     SyntaxTree syntaxTree, Map<Integer, String> services,
                                     Project project, Path outPath, List<Diagnostic> diagnostics) {
        Optional<Symbol> serviceSymbol = semanticModel.symbol(serviceNode);
        if (serviceSymbol.isEmpty() || !(serviceSymbol.get() instanceof ServiceDeclarationSymbol)) {
            return;
        }
        extractServiceNodes(syntaxTree.rootNode(), services, semanticModel);
        ListenerVisitor listenerVisitor = extractListenersFromDefaultModule(project);
        Set<ListenerDeclarationNode> listeners = listenerVisitor.getListenerDeclarationNodes();

        OpenAPI mcpServiceSchema = McpServiceOpenAPISchema.generate();
        ServersMapper serversMapper = new ServersMapper(mcpServiceSchema, listeners, serviceNode, semanticModel);
        serversMapper.setServers();
        diagnostics.addAll(serversMapper.getDiagnostics());

        String fileName = constructFileName(syntaxTree, services, serviceSymbol.get());
        writeOpenAPIYaml(outPath, mcpServiceSchema, fileName, diagnostics);
    }

    public static ListenerVisitor extractListenersFromDefaultModule(Project project) {
        ListenerVisitor listenerVisitor = new ListenerVisitor();
        Module module = project.currentPackage().module(project.currentPackage().getDefaultModule().moduleId());
        module.documentIds().forEach((documentId) -> {
            SyntaxTree syntaxTreeDoc = module.document(documentId).syntaxTree();
            syntaxTreeDoc.rootNode().accept(listenerVisitor);
        });
        return listenerVisitor;
    }

    public static boolean isMcpService(ServiceDeclarationNode serviceNode, SemanticModel semanticModel) {
        Optional<Symbol> serviceSymbol = semanticModel.symbol(serviceNode);
        if (serviceSymbol.isEmpty() || !(serviceSymbol.get() instanceof ServiceDeclarationSymbol serviceNodeSymbol)) {
            return false;
        }

        Optional<Symbol> listenerTypeSymbol = semanticModel.types().getTypeByName(BALLERINA, MCP, EMPTY, LISTENER);
        if (listenerTypeSymbol.isEmpty() || listenerTypeSymbol.get().kind() != SymbolKind.CLASS) {
            return false;
        }

        return serviceNodeSymbol.listenerTypes().stream()
                .anyMatch(listenerType -> isMcpListener(listenerType, (ClassSymbol) listenerTypeSymbol.get()));
    }

    private static boolean isMcpListener(TypeSymbol listenerType, TypeSymbol mcpListenerType) {
        // The listener type can be mcp:Listener for listener variable attachment
        // or mcp:Listener|error for anonymous new listener attachment
        return mcpListenerType.subtypeOf(listenerType);
    }

    private String constructFileName(SyntaxTree syntaxTree, Map<Integer, String> services, Symbol serviceSymbol) {
        String balFileName = syntaxTree.filePath().replaceAll(SLASH, UNDERSCORE).split("\\.")[0];
        String mappedName = services.get(serviceSymbol.hashCode());
        if (mappedName == null) {
            return balFileName + UNDERSCORE + serviceSymbol.hashCode() + OPENAPI_SUFFIX + YAML_EXTENSION;
        }
        String fileName = getNormalizedFileName(mappedName);
        if (fileName.equals(SLASH)) {
            return balFileName + OPENAPI_SUFFIX + YAML_EXTENSION;
        }
        if (fileName.contains(HYPHEN) && fileName.split(HYPHEN)[0].equals(SLASH) || fileName.isBlank()) {
            return balFileName + UNDERSCORE + serviceSymbol.hashCode() + OPENAPI_SUFFIX + YAML_EXTENSION;
        }
        return fileName + OPENAPI_SUFFIX + YAML_EXTENSION;
    }

    private void writeOpenAPIYaml(Path outPath, OpenAPI openAPI, String serviceName, List<Diagnostic> diagnostics) {
        String yamlOpenApiSpec = Yaml.pretty(openAPI);
        if (yamlOpenApiSpec == null) {
            return;
        }
        try {
            Files.createDirectories(Paths.get(outPath + OAS_PATH_SEPARATOR + OPENAPI));
            String fileName = resolveContractFileName(outPath.resolve(OPENAPI), serviceName, false);
            writeFile(outPath.resolve(OPENAPI + OAS_PATH_SEPARATOR + fileName), yamlOpenApiSpec);
        } catch (IOException e) {
            ExceptionDiagnostic diagnostic = new ExceptionDiagnostic(OAS_CONVERTOR_108, e.toString());
            diagnostics.add(getDiagnostics(diagnostic));
        }
    }

    private static void extractServiceNodes(ModulePartNode modulePartNode, Map<Integer, String> services,
                                            SemanticModel semanticModel) {
        List<String> allServices = new ArrayList<>();
        for (Node node : modulePartNode.members()) {
            if (!node.kind().equals(SyntaxKind.SERVICE_DECLARATION)) {
                continue;
            }
            ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) node;
            if (!isMcpService(serviceNode, semanticModel)) {
                continue;
            }
            Optional<Symbol> serviceSymbol = semanticModel.symbol(serviceNode);
            if (serviceSymbol.isEmpty() || !(serviceSymbol.get() instanceof ServiceDeclarationSymbol)) {
                continue;
            }
            String service = (new ServiceDeclaration(serviceNode, semanticModel)).absoluteResourcePath();
            String updateServiceName = service;
            if (allServices.contains(service)) {
                updateServiceName = service + HYPHEN + serviceSymbol.get().hashCode();
            } else {
                allServices.add(service);
            }
            services.put(serviceSymbol.get().hashCode(), updateServiceName);
        }
    }

    public static Diagnostic getDiagnostics(OpenAPIMapperDiagnostic diagnostic) {
        DiagnosticInfo diagnosticInfo = new DiagnosticInfo(diagnostic.getCode(), diagnostic.getMessage(),
                diagnostic.getDiagnosticSeverity());
        Location location = diagnostic.getLocation().orElse(new NullLocation());
        return DiagnosticFactory.createDiagnostic(diagnosticInfo, location);
    }

    public static class NullLocation implements Location {
        @Override
        public LineRange lineRange() {
            LinePosition from = LinePosition.from(0, 0);
            return LineRange.from("", from, from);
        }

        @Override
        public TextRange textRange() {
            return TextRange.from(0, 0);
        }
    }
}
