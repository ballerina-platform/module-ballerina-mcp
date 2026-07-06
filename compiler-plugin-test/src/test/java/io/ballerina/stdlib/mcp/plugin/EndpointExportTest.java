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

package io.ballerina.stdlib.mcp.plugin;

import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.DiagnosticResult;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.BuildProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

/**
 * End-to-end tests for the {@code --export-endpoints} build option: each fixture is built with {@code bal build} and
 * the resulting single {@code target/artifact/endpoints.yaml} is asserted. Covers listener/path topologies, listener
 * shapes, port resolution, and the cases that must not produce an artifact.
 */
public class EndpointExportTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "test-src")
            .toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime")
            .toAbsolutePath();
    private static final String ARTIFACT_DIR = "artifact";
    private static final String ENDPOINTS_FILE = "endpoints.yaml";

    // --- Topology: how listeners and base paths combine across services in one package ---

    @Test
    public void testSimpleService() throws Exception {
        withBuild("simple_service", true, endpoints -> {
            Assert.assertEquals(countEntries(endpoints), 1);
            Assert.assertTrue(endpoints.contains("port: 9090"));
            Assert.assertTrue(endpoints.contains("basePath: \"/mcp\""));
            Assert.assertTrue(endpoints.contains("type: \"mcp\""));
        });
    }

    @Test
    public void testAdvancedService() throws Exception {
        withBuild("advanced_service", true, endpoints -> {
            Assert.assertEquals(countEntries(endpoints), 1);
            Assert.assertTrue(endpoints.contains("port: 9090"));
            Assert.assertTrue(endpoints.contains("basePath: \"/mcp\""));
        });
    }

    @Test
    public void testSameListenerSamePath() throws Exception {
        withBuild("same_listener_same_path", true, endpoints -> {
            // Two services on the same listener and path produce two (identical) entries.
            Assert.assertEquals(countEntries(endpoints), 2);
            Assert.assertEquals(countOccurrences(endpoints, "port: 9090"), 2);
            Assert.assertEquals(countOccurrences(endpoints, "basePath: \"/mcp\""), 2);
        });
    }

    @Test
    public void testSameListenerDifferentPaths() throws Exception {
        withBuild("same_listener_different_paths", true, endpoints -> {
            Assert.assertEquals(countEntries(endpoints), 2);
            Assert.assertEquals(countOccurrences(endpoints, "port: 9090"), 2);
            Assert.assertTrue(endpoints.contains("basePath: \"/alpha\""));
            Assert.assertTrue(endpoints.contains("basePath: \"/beta\""));
        });
    }

    @Test
    public void testDifferentListenersSamePath() throws Exception {
        withBuild("different_listeners_same_path", true, endpoints -> {
            Assert.assertEquals(countEntries(endpoints), 2);
            Assert.assertTrue(endpoints.contains("port: 9090"));
            Assert.assertTrue(endpoints.contains("port: 9091"));
            Assert.assertEquals(countOccurrences(endpoints, "basePath: \"/mcp\""), 2);
        });
    }

    @Test
    public void testDifferentListenersDifferentPaths() throws Exception {
        withBuild("different_listeners_different_paths", true, endpoints -> {
            Assert.assertEquals(countEntries(endpoints), 2);
            Assert.assertTrue(endpoints.contains("port: 9090"));
            Assert.assertTrue(endpoints.contains("port: 9091"));
            Assert.assertTrue(endpoints.contains("basePath: \"/alpha\""));
            Assert.assertTrue(endpoints.contains("basePath: \"/beta\""));
        });
    }

    @Test
    public void testMcpAndNonMcpServiceExportsOnlyMcp() throws Exception {
        withBuild("mcp_and_non_mcp_service", true, endpoints -> {
            // Assert only on MCP-typed entries so the test survives HTTP/GraphQL adding their own entries later.
            Assert.assertEquals(countOccurrences(endpoints, "type: \"mcp\""), 1,
                    "MCP must export exactly one (its own) entry, not the co-located HTTP service");
            Assert.assertTrue(endpoints.contains("basePath: \"/mcp\""), "The MCP service should be exported");
        });
    }

    // --- Listener shapes and port resolution ---

    @Test
    public void testInlineExplicitListener() throws Exception {
        withBuild("inline_explicit_listener", true, endpoints -> {
            Assert.assertEquals(countEntries(endpoints), 1);
            Assert.assertTrue(endpoints.contains("port: 9090"), "Port from a const should resolve");
            Assert.assertTrue(endpoints.contains("basePath: \"/mcp\""));
        });
    }

    @Test
    public void testNoBasePath() throws Exception {
        withBuild("no_base_path", true, endpoints -> {
            Assert.assertEquals(countEntries(endpoints), 1);
            Assert.assertTrue(endpoints.contains("port: 9090"));
            Assert.assertTrue(endpoints.contains("basePath: \"\""),
                    "A service with no path should have an empty base path");
        });
    }

    @Test
    public void testConfigurablePortWithDefault() throws Exception {
        withBuild("configurable_port_with_default", true, endpoints -> {
            Assert.assertEquals(countEntries(endpoints), 1);
            Assert.assertTrue(endpoints.contains("port: 9090"), "The configurable default should be used");
        });
    }

    @Test
    public void testConfigurablePortRequiredIsLenient() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("configurable_port_required");
        try {
            deleteDirectories(projectDirPath);
            BuildResult result = buildCapturingOutput(projectDirPath);

            // Lenient: a required configurable port must not fail the build, and the warning must be accurate.
            Assert.assertEquals(result.exitCode(), 0, "A required configurable port must not fail the build");
            Assert.assertTrue(result.output().contains("cannot be determined at build time"),
                    "An accurate required-configurable warning should be emitted");
            Assert.assertFalse(result.output().contains("using the default value"),
                    "The misleading default-value warning must not be emitted for a required configurable");

            Path endpointsFile = artifactDir(projectDirPath).resolve(ENDPOINTS_FILE);
            Assert.assertTrue(Files.exists(endpointsFile), "endpoints.yaml should still be generated");
            String endpoints = Files.readString(endpointsFile);
            Assert.assertEquals(countEntries(endpoints), 1);
            Assert.assertTrue(endpoints.contains("port: 0"), "Required configurable port falls back to 0");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    // --- Cases that must not produce an artifact ---

    @Test
    public void testCompilationErrorProducesNoArtifact() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("compilation_error");
        try {
            deleteDirectories(projectDirPath);
            executeBallerinaCommand(projectDirPath, true);
            Assert.assertTrue(Files.notExists(artifactDir(projectDirPath)),
                    "No artifact should be emitted for a package with compilation errors");

            BuildOptions buildOptions = BuildOptions.builder().setExportEndpoints(true).build();
            BuildProject project = BuildProject.load(getEnvironmentBuilder(), projectDirPath, buildOptions);
            DiagnosticResult diagnostics = project.currentPackage().getCompilation().diagnosticResult();
            Assert.assertTrue(diagnostics.hasErrors(), "The fixture is expected to have compilation errors");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testServiceInTestSourceIsSkipped() throws Exception {
        withBuild("service_in_test_source", true, endpoints -> {
            Assert.assertEquals(countEntries(endpoints), 1, "Only the production-source service should be exported");
            Assert.assertTrue(endpoints.contains("basePath: \"/main\""));
            Assert.assertFalse(endpoints.contains("/test"), "A service declared in test sources must not be exported");
        });
    }

    @Test
    public void testBuildWithoutExportFlagProducesNoArtifact() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("simple_service");
        try {
            deleteDirectories(projectDirPath);
            executeBallerinaCommand(projectDirPath, false);
            Assert.assertTrue(Files.notExists(artifactDir(projectDirPath)),
                    "No artifact should be emitted without --export-endpoints");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    // --- Helpers ---

    private interface EndpointsAssertion {

        void check(String endpointsYaml);
    }

    private void withBuild(String packageName, boolean exportEndpoints, EndpointsAssertion assertion) throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve(packageName);
        try {
            deleteDirectories(projectDirPath);
            executeBallerinaCommand(projectDirPath, exportEndpoints);
            Path endpointsFile = artifactDir(projectDirPath).resolve(ENDPOINTS_FILE);
            Assert.assertTrue(Files.exists(endpointsFile), "endpoints.yaml should be generated for " + packageName);
            assertion.check(Files.readString(endpointsFile));
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    private static Path artifactDir(Path projectDirPath) {
        return projectDirPath.resolve("target").resolve(ARTIFACT_DIR);
    }

    private static long countEntries(String endpointsYaml) {
        return endpointsYaml.lines().map(String::trim).filter(line -> line.startsWith("type:")).count();
    }

    private static int countOccurrences(String haystack, String needle) {
        int count = 0;
        for (int i = haystack.indexOf(needle); i >= 0; i = haystack.indexOf(needle, i + needle.length())) {
            count++;
        }
        return count;
    }

    static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }

    private record BuildResult(int exitCode, String output) {
    }

    private static BuildResult buildCapturingOutput(Path projectDirPath) throws Exception {
        List<String> buildArgs = new ArrayList<>();
        String balFile = System.getProperty("os.name").startsWith("Windows") ? "bal.bat" : "bal";
        buildArgs.add(DISTRIBUTION_PATH.resolve("bin").resolve(balFile).toString());
        buildArgs.add("build");
        buildArgs.add("--export-endpoints");

        ProcessBuilder pb = new ProcessBuilder(buildArgs).redirectErrorStream(true);
        pb.directory(projectDirPath.toFile());
        Process process = pb.start();
        String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        if (!process.waitFor(2, TimeUnit.MINUTES)) {
            process.destroyForcibly().waitFor();
            Assert.fail("bal build timed out after 2 minutes");
        }
        return new BuildResult(process.exitValue(), output);
    }

    static int executeBallerinaCommand(Path projectDirPath, boolean exportEndpoints) throws Exception {
        List<String> buildArgs = new ArrayList<>();
        String balFile = "bal";
        if (System.getProperty("os.name").startsWith("Windows")) {
            balFile = "bal.bat";
        }
        buildArgs.add(DISTRIBUTION_PATH.resolve("bin").resolve(balFile).toString());
        buildArgs.add("build");
        if (exportEndpoints) {
            buildArgs.add("--export-endpoints");
        }

        ProcessBuilder pb = new ProcessBuilder(buildArgs)
                .redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.INHERIT);
        pb.directory(projectDirPath.toFile());
        Process process = pb.start();
        if (!process.waitFor(2, TimeUnit.MINUTES)) {
            process.destroyForcibly().waitFor();
            Assert.fail("bal build timed out after 2 minutes");
        }
        return process.exitValue();
    }

    private void deleteDirectories(Path projectDirPath) throws IOException {
        Path targetDir = projectDirPath.resolve("target");
        if (Files.exists(targetDir)) {
            try (Stream<Path> paths = Files.walk(targetDir)) {
                paths.sorted(Comparator.reverseOrder()).forEach(path -> {
                    try {
                        Files.delete(path);
                    } catch (IOException e) {
                        Assert.fail("Failed to delete file: " + path, e);
                    }
                });
            }
        }
        Path dependenciesFile = projectDirPath.resolve("Dependencies.toml");
        if (Files.exists(dependenciesFile)) {
            Files.delete(dependenciesFile);
        }
    }
}
