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
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

public class ServiceArtifactExtractorTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "test-src")
            .toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime")
            .toAbsolutePath();
    private static final String ARTIFACT_DIR = "artifact";
    private static final String ENDPOINTS_FILE = "endpoints.yaml";

    @Test
    public void testExportEndpointsForSimpleService() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_01");
        try {
            executeBallerinaCommand(projectDirPath, true);

            Path endpointsFile = endpointsFile(projectDirPath);
            Assert.assertTrue(Files.exists(endpointsFile), "endpoints.yaml should be generated");
            Assert.assertEquals(countEndpoints(endpointsFile), 1,
                    "Expected one endpoint entry for the single service in package_01");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testBuildWithoutExportEndpointsFlag() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_01");
        try {
            executeBallerinaCommand(projectDirPath, false);
            Path artifactDir = projectDirPath.resolve("target").resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.notExists(artifactDir),
                    "Artifact directory should not be generated without --export-endpoints");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testExportEndpointsWithCompilationErrors() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_04");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path artifactDir = projectDirPath.resolve("target").resolve(ARTIFACT_DIR);
            BuildOptions buildOptions = BuildOptions.builder().setExportEndpoints(true).build();
            BuildProject project = BuildProject.load(getEnvironmentBuilder(), projectDirPath, buildOptions);

            DiagnosticResult diagnostic = project.currentPackage().getCompilation().diagnosticResult();

            Assert.assertTrue(diagnostic.hasErrors(),
                    "package_04 fixture is expected to have compilation errors");
            Assert.assertTrue(Files.notExists(artifactDir),
                    "Endpoint artifacts must not be emitted for a package with compilation errors");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testExportEndpointsForMultipleMcpServersAcrossFiles() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_08");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path endpointsFile = endpointsFile(projectDirPath);
            Assert.assertTrue(Files.exists(endpointsFile), "endpoints.yaml should be generated");
            Assert.assertEquals(countEndpoints(endpointsFile), 2,
                    "Expected both services in package_08 in a single endpoints.yaml");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testExportEndpointsForMultipleServicesInSingleFile() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_05");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path endpointsFile = endpointsFile(projectDirPath);
            Assert.assertTrue(Files.exists(endpointsFile), "endpoints.yaml should be generated");
            Assert.assertEquals(countEndpoints(endpointsFile), 2,
                    "Expected both MCP services in package_05 in a single endpoints.yaml");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testExportEndpointsForServicesWithEmptyNames() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_07");
        try {
            executeBallerinaCommand(projectDirPath, true);

            Path endpointsFile = endpointsFile(projectDirPath);
            Assert.assertTrue(Files.exists(endpointsFile), "endpoints.yaml should be generated");
            Assert.assertEquals(countEndpoints(endpointsFile), 2,
                    "Expected both services with empty names in a single endpoints.yaml");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testExportEndpointsSkipsNonMcpServices() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_11");
        try {
            executeBallerinaCommand(projectDirPath, true);

            Path endpointsFile = endpointsFile(projectDirPath);
            Assert.assertTrue(Files.exists(endpointsFile), "endpoints.yaml should be generated");
            Assert.assertEquals(countMcpEndpoints(endpointsFile), 1,
                    "MCP plugin must record only the MCP service, not the co-located non-MCP service");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testExportEndpointsSkipsServicesInTestSources() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_12");
        try {
            executeBallerinaCommand(projectDirPath, true);

            Path endpointsFile = endpointsFile(projectDirPath);
            Assert.assertTrue(Files.exists(endpointsFile), "endpoints.yaml should be generated");
            Assert.assertEquals(countEndpoints(endpointsFile), 1,
                    "MCP plugin must record only the production-source service, not the test-source service");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    private Path endpointsFile(Path projectDirPath) {
        return projectDirPath.resolve("target").resolve(ARTIFACT_DIR).resolve(ENDPOINTS_FILE);
    }

    private long countEndpoints(Path endpointsFile) throws IOException {
        try (Stream<String> lines = Files.lines(endpointsFile)) {
            return lines.map(String::trim).filter(line -> line.startsWith("type:")).count();
        }
    }

    private long countMcpEndpoints(Path endpointsFile) throws IOException {
        try (Stream<String> lines = Files.lines(endpointsFile)) {
            return lines.map(String::trim).filter("type: \"mcp\""::equals).count();
        }
    }

    static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }

    public static int executeBallerinaCommand(Path projectDirPath, boolean exportEndpoints) throws Exception {
        List<String> buildArgs = new ArrayList<>();
        String balFile = "bal";
        if (System.getProperty("os.name").startsWith("Windows")) {
            balFile = "bal.bat";
        }
        buildArgs.add(0, DISTRIBUTION_PATH.resolve("bin").resolve(balFile).toString());
        buildArgs.add(1, "build");
        if (exportEndpoints) {
            buildArgs.add(2, "--export-endpoints");
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
                paths.sorted(Comparator.reverseOrder())
                        .forEach(path -> {
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
