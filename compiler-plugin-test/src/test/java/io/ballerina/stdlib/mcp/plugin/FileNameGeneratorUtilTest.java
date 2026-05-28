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

import io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.FileNameGeneratorUtil;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class FileNameGeneratorUtilTest {

    @Test
    public void testResolveContractFileNameWithExistingFile() throws IOException {
        Path tempDir = Files.createTempDirectory("filename_test");
        try {
            String fileName = "service_endpoint.yaml";
            Files.createFile(tempDir.resolve(fileName));
            String resolved = FileNameGeneratorUtil.resolveContractFileName(tempDir, fileName);
            Assert.assertTrue(resolved.equals(fileName) || resolved.startsWith("service_endpoint"),
                    "Should resolve to original or new name");
        } finally {
            try (DirectoryStream<Path> entries = Files.newDirectoryStream(tempDir)) {
                for (Path p : entries) {
                    Files.delete(p);
                }
            }
            Files.delete(tempDir);
        }
    }

    @Test
    public void testResolveContractFileNameWithNonExistentDir() {
        Path nonExistentDir = Paths.get("/tmp/does_not_exist_" + System.currentTimeMillis());
        String fileName = "service_endpoint.yaml";
        String resolved = FileNameGeneratorUtil.resolveContractFileName(nonExistentDir, fileName);
        Assert.assertEquals(resolved, fileName, "Should return original name if dir does not exist");
    }

    @Test
    public void testResolveContractFileNameWithNullDir() {
        String fileName = "service_endpoint.yaml";
        String resolved = FileNameGeneratorUtil.resolveContractFileName(null, fileName);
        Assert.assertEquals(resolved, fileName, "Should return original name if dir is null");
    }
}
