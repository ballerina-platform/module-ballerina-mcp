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
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.stdlib.mcp.plugin;

import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.NodeVisitor;
import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.DiagnosticResult;
import io.ballerina.projects.Module;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.BuildProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import io.ballerina.tools.diagnostics.Diagnostic;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Checks that the root module's and the v2 module's rule sets each process only their own module's code, whatever
 * prefixes the imports use and however the two modules are mixed in a package.
 */
public class ModuleIsolationTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "ballerina_sources",
            "isolation").toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime")
            .toAbsolutePath();
    private static final String TOOL_FIELDS = "Tool{description:\"%s\",schema:{";

    // --- Import-style matrix ---

    @Test
    public void testRootModuleDefaultPrefix() {
        Compiled compiled = compile("root_default");
        compiled.assertMcpDiagnostics();
        compiled.assertRootTool("add", "mcp", "Adds two numbers");
    }

    @Test
    public void testRootModuleAlias() {
        Compiled compiled = compile("root_alias");
        compiled.assertMcpDiagnostics();
        compiled.assertRootTool("add", "old", "Adds two numbers");
        compiled.assertRootTool("echo", "old", "Explicit");
        Assert.assertFalse(compiled.source().contains("@mcp:"), compiled.source());
    }

    @Test
    public void testV2ModuleDefaultPrefix() {
        Compiled compiled = compile("v2_default");
        compiled.assertMcpDiagnostics();
        compiled.assertV2Tool("add", "v2", "Adds two numbers");
    }

    @Test
    public void testV2ModuleImportedAsMcp() {
        Compiled compiled = compile("v2_as_mcp");
        compiled.assertMcpDiagnostics();
        compiled.assertV2Tool("add", "mcp", "Adds two numbers");
    }

    @Test
    public void testV2ModuleAlias() {
        Compiled compiled = compile("v2_alias");
        compiled.assertMcpDiagnostics();
        compiled.assertV2Tool("add", "m2", "Adds two numbers");
    }

    @Test
    public void testBothModulesDefaultPrefixes() {
        Compiled compiled = compile("both_default");
        compiled.assertMcpDiagnostics();
        compiled.assertRootTool("rootTool", "mcp", "Root tool");
        compiled.assertV2Tool("v2Tool", "v2", "V2 tool");
    }

    @Test
    public void testBothModulesWithV2Alias() {
        Compiled compiled = compile("both_mcp2");
        compiled.assertMcpDiagnostics();
        compiled.assertRootTool("rootTool", "mcp", "Root tool");
        compiled.assertV2Tool("v2Tool", "mcp2", "V2 tool");
    }

    @Test
    public void testRootAliasedAndV2ImportedAsMcp() {
        Compiled compiled = compile("both_old_mcp");
        compiled.assertMcpDiagnostics();
        compiled.assertRootTool("rootTool", "old", "Root tool");
        compiled.assertV2Tool("v2Tool", "mcp", "V2 tool");
    }

    @Test
    public void testBothModulesInDifferentDocuments() {
        Compiled compiled = compile("two_documents");
        compiled.assertMcpDiagnostics();
        compiled.assertRootTool("rootTool", "mcp", "Root tool");
        compiled.assertV2Tool("v2Tool", "mcp", "V2 tool");
    }

    @Test
    public void testBasicAndAdvancedServicesOfBothModules() {
        Compiled compiled = compile("four_services");
        // Only the v2 advanced service's optional session is reported, with the v2 code.
        compiled.assertMcpDiagnostics("MCP_WARNING_204@36");
        compiled.assertRootTool("rootTool", "old", "Root tool");
        compiled.assertV2Tool("v2Tool", "mcp", "V2 tool");
        Assert.assertEquals(compiled.annotations("onCallTool"), List.of(List.of(), List.of()));
        Assert.assertEquals(compiled.annotations("onListTools"), List.of(List.of(), List.of()));
    }

    // --- Cross-firing negatives ---

    @Test
    public void testV2ConstructsOnRootServiceGetRootRulesOnly() {
        Compiled compiled = compile("root_with_v2_constructs");
        compiled.assertMcpDiagnostics("MCP_102@5");
        compiled.assertRootTool("withInputRequired", "mcp", "Returns a v2 input request");
    }

    @Test
    public void testRootSessionOnV2ServiceGetsV2RulesOnly() {
        Compiled compiled = compile("v2_with_root_session");
        compiled.assertMcpDiagnostics("MCP_202@5");
    }

    @Test
    public void testOnlyV2ElicitFormIsRewritten() {
        Compiled compiled = compile("elicit_form");
        compiled.assertMcpDiagnostics();
        String source = compiled.source();
        Assert.assertFalse(source.contains("mcp:elicitForm(\"V2 call\", Booking)"), source);
        Assert.assertFalse(source.contains("mcp:elicitForm(\"Root call\", Booking)"), source);
        Assert.assertTrue(source.contains("elicitForm(\"Local call\", Booking)"), source);
        Assert.assertEquals(countOccurrences(source, "\"description\":\"The guest's name\""), 2, source);
        compiled.assertV2Tool("book", "mcp", "Books a table");
        compiled.assertRootTool("prepare", "old", "Builds a form request");
    }

    // --- No-op cases ---

    @Test
    public void testPackageWithNeitherModuleIsUntouched() throws IOException {
        Compiled compiled = compile("neither_module");
        Assert.assertEquals(compiled.result.diagnostics().size(), 0, compiled.result.diagnostics().toString());
        Assert.assertEquals(compiled.source(),
                Files.readString(RESOURCE_DIRECTORY.resolve("neither_module").resolve("service.bal")));
    }

    @Test
    public void testErroneousCodeInBothModules() {
        Compiled compiled = compile("erroneous", false);
        Assert.assertTrue(compiled.result.errorCount() > 0);
        for (Diagnostic diagnostic : compiled.mcpDiagnostics()) {
            String file = diagnostic.location().lineRange().fileName();
            String code = diagnostic.diagnosticInfo().code();
            Assert.assertTrue(file.equals("root.bal") ? isRootCode(code) : isV2Code(code),
                    code + " reported in " + file);
        }
    }

    @Test
    public void testV2ModuleImportedAsUnderscore() {
        Compiled compiled = compile("v2_ignored");
        compiled.assertMcpDiagnostics();
        compiled.assertRootTool("rootTool", "mcp", "Root tool");
    }

    // --- Endpoint export ---

    @Test
    public void testEndpointExportIncludesBothModules() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("endpoint_export_both");
        try {
            deleteBuildOutput(projectDirPath);
            Assert.assertEquals(EndpointExportTest.executeBallerinaCommand(projectDirPath, true), 0);
            String endpoints = Files.readString(projectDirPath.resolve("target").resolve("artifact")
                    .resolve("endpoints.yaml"));
            Assert.assertEquals(countOccurrences(endpoints, "type: \"mcp\""), 2, endpoints);
            Assert.assertTrue(endpoints.contains("port: 9090"), endpoints);
            Assert.assertTrue(endpoints.contains("basePath: \"/root\""), endpoints);
            Assert.assertTrue(endpoints.contains("port: 9091"), endpoints);
            Assert.assertTrue(endpoints.contains("basePath: \"/v2\""), endpoints);
        } finally {
            deleteBuildOutput(projectDirPath);
        }
    }

    private static boolean isRootCode(String code) {
        return code.matches("MCP_(WARNING_)?1\\d\\d");
    }

    private static boolean isV2Code(String code) {
        return code.matches("MCP_(WARNING_)?2\\d\\d");
    }

    private static Compiled compile(String packageName) {
        return compile(packageName, true);
    }

    private static Compiled compile(String packageName, boolean expectValidResult) {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        BuildProject project = BuildProject.load(ProjectEnvironmentBuilder.getBuilder(environment),
                RESOURCE_DIRECTORY.resolve(packageName), BuildOptions.builder().setOffline(true).build());
        DiagnosticResult result = project.currentPackage().runCodeGenAndModifyPlugins();
        if (expectValidResult) {
            // The rewritten sources must compile, so each generated annotation binds to the intended module.
            DiagnosticResult compilation = project.currentPackage().getCompilation().diagnosticResult();
            Assert.assertEquals(compilation.errorCount(), 0, compilation.errors().toString());
        }
        return new Compiled(project, result);
    }

    private static int countOccurrences(String haystack, String needle) {
        int count = 0;
        for (int i = haystack.indexOf(needle); i >= 0; i = haystack.indexOf(needle, i + needle.length())) {
            count++;
        }
        return count;
    }

    private static void deleteBuildOutput(Path projectDirPath) throws IOException {
        Path targetDir = projectDirPath.resolve("target");
        if (Files.exists(targetDir)) {
            try (Stream<Path> paths = Files.walk(targetDir)) {
                for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) {
                    Files.delete(path);
                }
            }
        }
        Files.deleteIfExists(projectDirPath.resolve("Dependencies.toml"));
    }

    private record Compiled(BuildProject project, DiagnosticResult result) {

        List<Diagnostic> mcpDiagnostics() {
            return result.diagnostics().stream()
                    .filter(diagnostic -> diagnostic.diagnosticInfo().code().startsWith("MCP_"))
                    .toList();
        }

        // Expected entries are "<code>@<zero-based line>".
        void assertMcpDiagnostics(String... expected) {
            List<String> actual = mcpDiagnostics().stream()
                    .map(diagnostic -> diagnostic.diagnosticInfo().code() + "@"
                            + diagnostic.location().lineRange().startLine().line())
                    .toList();
            Assert.assertEquals(actual, List.of(expected), result.diagnostics().toString());
        }

        String source() {
            Module module = project.currentPackage().getDefaultModule();
            return module.documentIds().stream()
                    .map(documentId -> module.document(documentId).syntaxTree().toSourceCode())
                    .collect(Collectors.joining());
        }

        // The annotations of each function with the given name, in document order.
        List<List<String>> annotations(String functionName) {
            Module module = project.currentPackage().getDefaultModule();
            Map<String, List<List<String>>> byName = new HashMap<>();
            NodeVisitor visitor = new NodeVisitor() {
                @Override
                public void visit(FunctionDefinitionNode function) {
                    List<String> annotations = function.metadata()
                            .map(metadata -> metadata.annotations().stream().map(AnnotationNode::toSourceCode)
                                    .map(String::trim).toList())
                            .orElse(List.of());
                    byName.computeIfAbsent(function.functionName().text(), name -> new ArrayList<>())
                            .add(annotations);
                }
            };
            module.documentIds().forEach(id -> module.document(id).syntaxTree().rootNode().accept(visitor));
            return byName.getOrDefault(functionName, List.of());
        }

        void assertRootTool(String functionName, String prefix, String description) {
            String annotation = singleToolAnnotation(functionName);
            Assert.assertTrue(annotation.startsWith("@" + prefix + ":" + TOOL_FIELDS.formatted(description)),
                    annotation);
            // The 1.x generator only emits the 1.x fields.
            Assert.assertFalse(annotation.contains("outputSchema"), annotation);
        }

        void assertV2Tool(String functionName, String prefix, String description) {
            String annotation = singleToolAnnotation(functionName);
            Assert.assertTrue(annotation.startsWith("@" + prefix + ":" + TOOL_FIELDS.formatted(description)),
                    annotation);
            Assert.assertTrue(annotation.contains(",outputSchema:"), annotation);
            Assert.assertTrue(annotation.contains(",structuredOutput:"), annotation);
        }

        private String singleToolAnnotation(String functionName) {
            List<List<String>> functions = annotations(functionName);
            Assert.assertEquals(functions.size(), 1, functionName + ": " + functions);
            List<String> tools = functions.get(0).stream().filter(a -> a.contains(":Tool")).toList();
            Assert.assertEquals(tools.size(), 1, functionName + ": " + tools);
            return tools.get(0);
        }
    }
}
