package io.ballerina.stdlib.mcp.plugin;

import org.testng.Assert;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class FileNameGeneratorUtilTest {
    private static final Path TEST_DIR = Paths.get("src", "test", "resources", "test-src").toAbsolutePath();
    private static final String ARTIFACT_DIR = "artifact";

    @Test
    public void testResolveContractFileNameWithExistingFile() throws IOException {
        Path tempDir = Files.createTempDirectory("filename_test");
        try {
            String fileName = "service_endpoint.yaml";
            Files.createFile(tempDir.resolve(fileName));
            String resolved = io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.FileNameGeneratorUtil.resolveContractFileName(tempDir, fileName);
            Assert.assertTrue(resolved.equals(fileName) || resolved.startsWith("service_endpoint"), "Should resolve to original or new name");
        } finally {
            for (Path p : Files.newDirectoryStream(tempDir)) {
                Files.delete(p);
            }
            Files.delete(tempDir);
        }
    }

    @Test
    public void testResolveContractFileNameWithNonExistentDir() {
        Path nonExistentDir = Paths.get("/tmp/does_not_exist_" + System.currentTimeMillis());
        String fileName = "service_endpoint.yaml";
        String resolved = io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.FileNameGeneratorUtil.resolveContractFileName(nonExistentDir, fileName);
        Assert.assertEquals(resolved, fileName, "Should return original name if dir does not exist");
    }

    @Test
    public void testResolveContractFileNameWithNullDir() {
        String fileName = "service_endpoint.yaml";
        String resolved = io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.FileNameGeneratorUtil.resolveContractFileName(null, fileName);
        Assert.assertEquals(resolved, fileName, "Should return original name if dir is null");
    }
}
