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
import io.ballerina.projects.Project;
import io.ballerina.projects.directory.BuildProject;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Comparator;
import java.util.stream.Stream;

import static io.ballerina.stdlib.mcp.plugin.ServiceArtifactExtractorTest.executeBallerinaCommand;
import static io.ballerina.stdlib.mcp.plugin.ServiceArtifactExtractorTest.getEnvironmentBuilder;

public class EndpointDetailsExtractorTest {
    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "test-src")
            .toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime")
            .toAbsolutePath();

    private static final String TARGET_DIR = "target";
    private static final String ARTIFACT_DIR = "artifact";

    @Test
    public void testHardcodedPortExtraction() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_01");
        try {
            executeBallerinaCommand(projectDirPath, true);

            Path artifactDir = projectDirPath.resolve(TARGET_DIR).resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir));
            Path endpointYaml = artifactDir.resolve("main_mcp_endpoint.yaml");
            assertEndpointPort(endpointYaml, 9091);
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testConfigurablePortWithDefaultValue() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_02");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path artifactDir = projectDirPath.resolve(TARGET_DIR).resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir));
            Path endpointYaml = artifactDir.resolve("main_mcp_endpoint.yaml");
            assertEndpointPort(endpointYaml, 9091);
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testConfigurablePortWithRequiredValue()  throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_03");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path artifactDir = projectDirPath.resolve(TARGET_DIR).resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir));
            Path endpointYaml = artifactDir.resolve("main_mcp_endpoint.yaml");
            assertEndpointPort(endpointYaml, 0);
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testBasePathForMultipleServices() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_05");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path artifactDir = projectDirPath.resolve(TARGET_DIR).resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir), "Artifact directory should exist");
            // Expect 2 endpoint YAMLs for 2 services
            long count = Files.list(artifactDir).filter(p -> p.getFileName().toString().endsWith("_endpoint.yaml")).count();
            Assert.assertEquals(count, 2, "Expected 2 endpoint YAML files for multiple services");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testListenerNotResolved() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_09");
        try {
            // Should not generate artifact if listener is not resolved
            executeBallerinaCommand(projectDirPath, true);
            BuildOptions buildOptions = BuildOptions.builder().setExportEndpoints(true).build();
            BuildProject project = BuildProject.load(getEnvironmentBuilder(), projectDirPath, buildOptions);

            DiagnosticResult diagnostic = project.currentPackage().getCompilation().diagnosticResult();

            Assert.assertTrue(diagnostic.diagnostics().stream()
                    .anyMatch(diagnostic1 -> {
                        String code = diagnostic1.diagnosticInfo().code();
                        if (code == "LISTENER_NOT_RESOLVED") {
                            return true;
                        }
                        String message = diagnostic1.message();
                        return message.contains("undefined symbol");
                    }));
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testNamedListenerReference() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_01");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path artifactDir = projectDirPath.resolve(TARGET_DIR).resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir), "Artifact directory should exist");
            long count = Files.list(artifactDir).filter(p -> p.getFileName().toString().endsWith("_endpoint.yaml")).count();
            Assert.assertTrue(count >= 1, "Should generate at least one endpoint YAML for named listener");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testImplicitNewExpressionListener() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_10");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path artifactDir = projectDirPath.resolve(TARGET_DIR).resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir), "Artifact directory should exist");
            long count = Files.list(artifactDir).filter(p -> p.getFileName().toString().endsWith("_endpoint.yaml")).count();
            Assert.assertTrue(count >= 1, "Should generate at least one endpoint YAML for implicit new listener");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    private static void assertEndpointPort(Path endpointYaml, int expectedPort) throws IOException {
        try (Stream<String> lines = Files.lines(endpointYaml)) {
            String portLine = lines.map(String::trim)
                    .filter(line -> line.startsWith("port:"))
                    .findFirst()
                    .orElseThrow(() -> new AssertionError("No port field found in: " + endpointYaml));
            int actualPort = Integer.parseInt(portLine.substring("port:".length()).trim());
            Assert.assertEquals(actualPort, expectedPort, "Unexpected endpoint port in " + endpointYaml);
        }
    }

    private void deleteDirectories(Path projectDirPath) throws IOException {
        Path targetDir = projectDirPath.resolve(TARGET_DIR);
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
