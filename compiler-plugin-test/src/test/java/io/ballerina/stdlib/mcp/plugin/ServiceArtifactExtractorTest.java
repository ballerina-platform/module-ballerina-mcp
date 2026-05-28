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
import java.util.Objects;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

public class ServiceArtifactExtractorTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "test-src")
            .toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime")
            .toAbsolutePath();
    private static final String ARTIFACT_DIR = "artifact";
    private static final String ENDPOINT_SUFFIX = "_endpoint.yaml";

    @Test
    public void testExportEndpointsForSimpleService() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_01");
        try {
            executeBallerinaCommand(projectDirPath, true);

            Path artifactDir = projectDirPath.resolve("target").resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir), "Artifact directory should exist");
            assertArtifactCount(artifactDir, ENDPOINT_SUFFIX, 1,
                    "Expected one endpoint YAML for package_20");
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

            Assert.assertTrue(diagnostic.hasErrors());
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testExportEndpointsForMultipleMcpServersAcrossFiles() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_08");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path artifactDir = projectDirPath.resolve("target").resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir), "Artifact directory should exist");
            assertArtifactCount(artifactDir, ENDPOINT_SUFFIX, 2,
                    "Expected endpoint artifacts for both services in package_08");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testExportEndpointsForMultipleServicesInSingleFile() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_05");
        try {
            executeBallerinaCommand(projectDirPath, true);
            Path artifactDir = projectDirPath.resolve("target").resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir), "Artifact directory should exist");
            assertArtifactCount(artifactDir, ENDPOINT_SUFFIX, 2,
                    "Expected one endpoint YAML from the single gRPC service in the file");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testEndpointYamlFallbackNamingForEmptyServiceNames() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_07");
        try {
            executeBallerinaCommand(projectDirPath, true);

            Path artifactDir = projectDirPath.resolve("target").resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir), "Artifact directory should exist");

            List<String> endpointFiles;
            try (Stream<Path> paths = Files.walk(artifactDir)) {
                endpointFiles = paths
                        .map(this::safeFileName)
                        .filter(fileName -> fileName.endsWith(ENDPOINT_SUFFIX))
                        .toList();
            }

            Assert.assertEquals(endpointFiles.size(), 2,
                    "Expected endpoint YAML artifacts for both services with empty names");
            Assert.assertTrue(endpointFiles.stream()
                            .allMatch(fileName -> fileName.matches(".+_-?[0-9]+_endpoint\\.yaml")),
                    "Endpoint YAML files should use fallback hash-based naming for empty service names");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    @Test
    public void testExportEndpointsSkipsNonMcpServices() throws Exception {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve("package_11");
        try {
            executeBallerinaCommand(projectDirPath, true);

            Path artifactDir = projectDirPath.resolve("target").resolve(ARTIFACT_DIR);
            Assert.assertTrue(Files.exists(artifactDir), "Artifact directory should exist");
            long mcpStampedCount;
            try (Stream<Path> paths = Files.walk(artifactDir)) {
                mcpStampedCount = paths
                        .filter(p -> safeFileName(p).endsWith(ENDPOINT_SUFFIX))
                        .filter(this::hasMcpType)
                        .count();
            }
            Assert.assertEquals(mcpStampedCount, 1,
                    "MCP plugin must emit endpoint.yaml only for the MCP service, " +
                            "not for the co-located non-MCP service");
        } finally {
            deleteDirectories(projectDirPath);
        }
    }

    private boolean hasMcpType(Path yamlFile) {
        try (Stream<String> lines = Files.lines(yamlFile)) {
            return lines.map(String::trim).anyMatch("type: \"mcp\""::equals);
        } catch (IOException e) {
            return false;
        }
    }

    private String safeFileName(Path path) {
        Path fileName = path == null ? null : path.getFileName();
        return Objects.toString(fileName, "");
    }

    private void assertArtifactCount(Path artifactDir, String suffix, int expectedCount, String message)
            throws IOException {
        try (Stream<Path> paths = Files.walk(artifactDir)) {
            long artifactCount = paths
                    .map(this::safeFileName)
                    .filter(fileName -> fileName.endsWith(suffix))
                    .count();
            Assert.assertEquals(artifactCount, expectedCount, message);
        }
    }

    static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }

    public static void executeBallerinaCommand(Path projectDirPath, boolean exportEndpoints) throws Exception {
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
        boolean completed = process.waitFor(2, TimeUnit.MINUTES);
        Assert.assertTrue(completed, "bal build timed out after 2 minutes");
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
