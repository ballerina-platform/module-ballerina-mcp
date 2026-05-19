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

package io.ballerina.stdlib.mcp.compiler;

import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.DiagnosticResult;
import io.ballerina.projects.PackageCompilation;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.BuildProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.text.MessageFormat;
import java.util.Comparator;
import java.util.Iterator;
import java.util.stream.Stream;

import static io.ballerina.stdlib.mcp.plugin.diagnostics.CompilationDiagnostic
        .UNABLE_TO_OBTAIN_VALID_SERVER_PORT_FROM_EXPRESSION;

/**
 * End-to-end tests for the MCP compiler-plugin OpenAPI generator. Each sample under
 * {@code src/test/resources/ballerina_sources/openapi_tests/} is compiled with
 * {@code exportOpenAPI = true} and the generated YAML files are asserted to exist
 * (or the expected warning to be emitted).
 */
public class OpenAPIGeneratorTest {
    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources",
            "ballerina_sources", "openapi_tests").toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime").toAbsolutePath();

    @Test
    public void testOpenAPIGenerationForListenerVariablePatterns() {
        String packagePath = "01_listener_variable_patterns";
        DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
        Assert.assertEquals(diagnosticResult.errorCount(), 0,
                "Expected no errors for package: " + packagePath);
        // One YAML per service. Each service path determines the YAML file name.
        String[] expected = {
                "positional_openapi.yaml",
                "named_arg_openapi.yaml",
                "indirection_openapi.yaml",
                "named_host_openapi.yaml",
                "mapping_host_openapi.yaml",
                "default_listener_openapi.yaml",
                "https_listener_openapi.yaml",
                // Root-path service falls back to the bal file name in `constructFileName`.
                "main_openapi.yaml"
        };
        for (String yaml : expected) {
            Path file = RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi/" + yaml);
            Assert.assertTrue(Files.exists(file), "OpenAPI file not generated: " + yaml);
        }
    }

    @Test
    public void testOpenAPIGenerationForAnonymousListener() {
        String packagePath = "02_anonymous_listener";
        DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
        Assert.assertEquals(diagnosticResult.errorCount(), 0,
                "Expected no errors for package: " + packagePath);
        Path openApiFile = RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi/api_v1_openapi.yaml");
        Assert.assertTrue(Files.exists(openApiFile),
                "OpenAPI file not generated for package: " + packagePath);
    }

    @Test
    public void testOpenAPIGenerationEmitsWarningForPortVariable() {
        String packagePath = "03_port_variable_warning";
        DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
        Assert.assertEquals(diagnosticResult.errorCount(), 0,
                "Expected no errors for package: " + packagePath);
        Assert.assertEquals(diagnosticResult.warningCount(), 1);

        Iterator<Diagnostic> diagnosticIterator = diagnosticResult.warnings().iterator();
        Diagnostic diagnostic = diagnosticIterator.next();
        String message = getWarningMessage(UNABLE_TO_OBTAIN_VALID_SERVER_PORT_FROM_EXPRESSION, "port", "9090");
        assertWarningMessage(diagnostic, message, 21, 42);

        Path openApiFile = RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi/mcp_openapi.yaml");
        Assert.assertTrue(Files.exists(openApiFile),
                "OpenAPI file not generated for package: " + packagePath);
    }

    @Test
    public void testOpenAPIGenerationForMultipleListeners() {
        String packagePath = "04_multi_listener";
        DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
        Assert.assertEquals(diagnosticResult.errorCount(), 0,
                "Expected no errors for package: " + packagePath);
        Path openApiFile = RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi/mcp_openapi.yaml");
        Assert.assertTrue(Files.exists(openApiFile),
                "OpenAPI file not generated for package: " + packagePath);
    }

    @Test
    public void testOpenAPIGenerationForMultipleServicesWithSamePath() throws IOException {
        String packagePath = "05_duplicate_paths";
        DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
        Assert.assertEquals(diagnosticResult.errorCount(), 0,
                "Expected no errors for package: " + packagePath);
        Path openApiDir = RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi");
        Assert.assertTrue(Files.exists(openApiDir));
        try (Stream<Path> entries = Files.list(openApiDir)) {
            long yamlCount = entries.filter(p -> p.toString().endsWith(".yaml")).count();
            Assert.assertEquals(yamlCount, 2,
                    "Expected one OpenAPI file per service (with disambiguating suffix)");
        }
    }

    @Test
    public void testOpenAPIGenerationSkippedWhenCompileErrorsPresent() throws IOException {
        String packagePath = "06_compile_error";
        DiagnosticResult diagnosticResult = getDiagnosticResult(packagePath);
        Assert.assertTrue(diagnosticResult.errorCount() > 0,
                "Expected at least one compile error for package: " + packagePath);
        Path openApiDir = RESOURCE_DIRECTORY.resolve(packagePath + "/target/openapi");
        if (Files.exists(openApiDir)) {
            try (Stream<Path> entries = Files.list(openApiDir)) {
                Assert.assertEquals(entries.count(), 0,
                        "No OpenAPI files should be generated when the package has compile errors");
            }
        }
    }

    @Test
    public void testOpenAPIGenerationSkippedWhenFlagDisabled() throws IOException {
        String packagePath = "01_listener_variable_patterns";
        Path projectDirPath = RESOURCE_DIRECTORY.resolve(packagePath);
        deleteOpenAPIArtifacts(projectDirPath);
        BuildOptions buildOptions = BuildOptions.builder().setExportOpenAPI(false).build();
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), projectDirPath, buildOptions);
        project.currentPackage().runCodeGenAndModifyPlugins();
        DiagnosticResult diagnosticResult = project.currentPackage().getCompilation().diagnosticResult();
        Assert.assertEquals(diagnosticResult.errorCount(), 0);
        Path openApiDir = projectDirPath.resolve("target").resolve("openapi");
        if (Files.exists(openApiDir)) {
            try (Stream<Path> entries = Files.list(openApiDir)) {
                Assert.assertEquals(entries.count(), 0,
                        "No OpenAPI files should be generated when --export-openapi is disabled");
            }
        }
    }

    private String getWarningMessage(CompilationDiagnostic compilationDiagnostic, Object... args) {
        return MessageFormat.format(compilationDiagnostic.getDiagnostic(), args);
    }

    private void assertWarningMessage(Diagnostic diagnostic, String message, int line, int column) {
        Assert.assertEquals(diagnostic.diagnosticInfo().severity(), DiagnosticSeverity.WARNING);
        Assert.assertEquals(diagnostic.message(), message);
        assertWarningLocation(diagnostic.location(), line, column);
    }

    private void assertWarningLocation(Location location, int line, int column) {
        // Compiler counts lines and columns from zero
        Assert.assertEquals((location.lineRange().startLine().line() + 1), line);
        Assert.assertEquals((location.lineRange().startLine().offset() + 1), column);
    }

    private DiagnosticResult getDiagnosticResult(String path) {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve(path);
        deleteOpenAPIArtifacts(projectDirPath);
        BuildOptions buildOptions = BuildOptions.builder().setExportOpenAPI(true).build();
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), projectDirPath, buildOptions);
        project.currentPackage().runCodeGenAndModifyPlugins();
        PackageCompilation compilation = project.currentPackage().getCompilation();
        return compilation.diagnosticResult();
    }

    private static void deleteOpenAPIArtifacts(Path projectDirPath) {
        Path openApiDir = projectDirPath.resolve("target").resolve("openapi");
        if (!Files.exists(openApiDir)) {
            return;
        }
        try (Stream<Path> paths = Files.walk(openApiDir)) {
            paths.sorted(Comparator.reverseOrder()).forEach(p -> {
                try {
                    Files.deleteIfExists(p);
                } catch (IOException e) {
                    throw new RuntimeException("Failed to delete stale OpenAPI artifact: " + p, e);
                }
            });
        } catch (IOException e) {
            throw new RuntimeException("Failed to clean OpenAPI output dir: " + openApiDir, e);
        }
    }

    private static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }
}
