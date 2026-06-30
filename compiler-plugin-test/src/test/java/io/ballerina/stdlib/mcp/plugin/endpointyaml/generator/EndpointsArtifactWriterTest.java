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

package io.ballerina.stdlib.mcp.plugin.endpointyaml.generator;

import io.ballerina.projects.Package;
import io.ballerina.projects.PackageCompilation;
import io.ballerina.projects.plugins.CompilationAnalysisContext;
import io.ballerina.tools.diagnostics.Diagnostic;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Stream;

/**
 * Unit tests for {@link EndpointsArtifactWriter}, covering the merge behavior of the consolidated
 * {@code endpoints.yaml}: aggregation, preservation of other modules' entries, idempotent rebuilds, and the
 * unreadable-artifact error path. These exercise the writer directly so they need neither a {@code bal build} nor a
 * fixture package.
 */
public class EndpointsArtifactWriterTest {

    private static final String ARTIFACT = "artifact";
    private static final String ENDPOINTS_FILE = "endpoints.yaml";
    private static final String NOT_READABLE_CODE = "ENDPOINTS_ARTIFACT_NOT_READABLE";

    @Test
    public void testWriteCreatesFileWhenNoneExists() throws IOException {
        Path target = Files.createTempDirectory("mcp-writer");
        try {
            CapturingContext context = new CapturingContext();
            new EndpointsArtifactWriter().write(target, List.of(new Endpoint(9091, "/mcp", "mcp")), context);

            String yaml = Files.readString(endpointsFile(target));
            Assert.assertTrue(yaml.contains("endpoints:"), "Top-level endpoints key should be present");
            Assert.assertTrue(yaml.contains("port: 9091"), "Port should be written");
            Assert.assertTrue(yaml.contains("basePath: \"/mcp\""), "Base path should be written");
            Assert.assertEquals(countOccurrences(yaml, "type: \"mcp\""), 1, "Exactly one MCP entry expected");
            Assert.assertTrue(context.diagnostics.isEmpty(), "No diagnostics expected on a clean write");
        } finally {
            deleteRecursively(target);
        }
    }

    @Test
    public void testMergePreservesForeignEntriesAndReplacesStaleMcp() throws IOException {
        Path target = Files.createTempDirectory("mcp-writer");
        try {
            // An existing file as another module (HTTP) plus a previous build would have left it: a REST entry with a
            // field MCP does not model (schemaPath), and a stale MCP entry from the last build.
            seed(target,
                    "endpoints:\n"
                            + "- port: 8080\n  basePath: \"/api\"\n  type: \"REST\"\n  schemaPath: \"main_api.yaml\"\n"
                            + "- port: 1111\n  basePath: \"/old\"\n  type: \"mcp\"\n");

            CapturingContext context = new CapturingContext();
            new EndpointsArtifactWriter().write(target, List.of(new Endpoint(9091, "/mcp", "mcp")), context);

            String yaml = Files.readString(endpointsFile(target));
            Assert.assertTrue(context.diagnostics.isEmpty(), "A well-formed file should merge without diagnostics");
            // Other module's entry preserved verbatim, including the field MCP does not model.
            Assert.assertTrue(yaml.contains("type: \"REST\""), "Other module's entry must be preserved");
            Assert.assertTrue(yaml.contains("schemaPath: \"main_api.yaml\""),
                    "Foreign field schemaPath must round-trip unchanged");
            // Stale MCP entry dropped; current one written.
            Assert.assertFalse(yaml.contains("port: 1111"), "Stale MCP entry must be dropped");
            Assert.assertFalse(yaml.contains("/old"), "Stale MCP base path must be dropped");
            Assert.assertTrue(yaml.contains("port: 9091"), "Current MCP entry must be written");
            Assert.assertEquals(countOccurrences(yaml, "type: \"mcp\""), 1,
                    "MCP entry must be replaced, not duplicated");
        } finally {
            deleteRecursively(target);
        }
    }

    @Test
    public void testRepeatedWritesAreIdempotent() throws IOException {
        Path target = Files.createTempDirectory("mcp-writer");
        try {
            EndpointsArtifactWriter writer = new EndpointsArtifactWriter();
            List<Endpoint> endpoints = List.of(new Endpoint(9091, "/mcp", "mcp"));
            writer.write(target, endpoints, new CapturingContext());
            writer.write(target, endpoints, new CapturingContext());

            String yaml = Files.readString(endpointsFile(target));
            Assert.assertEquals(countOccurrences(yaml, "type: \"mcp\""), 1,
                    "Rebuilding must not duplicate the MCP entry");
        } finally {
            deleteRecursively(target);
        }
    }

    @Test
    public void testStructurallyUnexpectedFileReportsErrorAndIsLeftUntouched() throws IOException {
        Path target = Files.createTempDirectory("mcp-writer");
        try {
            String original = "someOtherTool:\n  data: value\n";
            seed(target, original);

            CapturingContext context = new CapturingContext();
            new EndpointsArtifactWriter().write(target, List.of(new Endpoint(9091, "/mcp", "mcp")), context);

            Assert.assertTrue(hasDiagnostic(context, NOT_READABLE_CODE),
                    "A file without an `endpoints` list must raise " + NOT_READABLE_CODE);
            Assert.assertEquals(Files.readString(endpointsFile(target)), original,
                    "An unrecognized file must be left untouched");
        } finally {
            deleteRecursively(target);
        }
    }

    @Test
    public void testMalformedYamlReportsErrorAndIsLeftUntouched() throws IOException {
        Path target = Files.createTempDirectory("mcp-writer");
        try {
            String original = "endpoints: [this is : not valid yaml\n  - broken";
            seed(target, original);

            CapturingContext context = new CapturingContext();
            new EndpointsArtifactWriter().write(target, List.of(new Endpoint(9091, "/mcp", "mcp")), context);

            Assert.assertTrue(hasDiagnostic(context, NOT_READABLE_CODE),
                    "A malformed YAML file must raise " + NOT_READABLE_CODE);
            Assert.assertEquals(Files.readString(endpointsFile(target)), original,
                    "A malformed file must be left untouched");
        } finally {
            deleteRecursively(target);
        }
    }

    private static Path endpointsFile(Path target) {
        return target.resolve(ARTIFACT).resolve(ENDPOINTS_FILE);
    }

    private static void seed(Path target, String content) throws IOException {
        Path artifactDir = Files.createDirectories(target.resolve(ARTIFACT));
        Files.writeString(artifactDir.resolve(ENDPOINTS_FILE), content);
    }

    private static boolean hasDiagnostic(CapturingContext context, String code) {
        return context.diagnostics.stream().anyMatch(d -> code.equals(d.diagnosticInfo().code()));
    }

    private static int countOccurrences(String haystack, String needle) {
        int count = 0;
        for (int i = haystack.indexOf(needle); i >= 0; i = haystack.indexOf(needle, i + needle.length())) {
            count++;
        }
        return count;
    }

    private static void deleteRecursively(Path root) throws IOException {
        if (!Files.exists(root)) {
            return;
        }
        try (Stream<Path> paths = Files.walk(root)) {
            paths.sorted(Comparator.reverseOrder()).forEach(path -> {
                try {
                    Files.delete(path);
                } catch (IOException e) {
                    throw new RuntimeException(e);
                }
            });
        }
    }

    /**
     * A {@link CompilationAnalysisContext} stub that records reported diagnostics. Only {@code reportDiagnostic} is
     * exercised by the writer; the other accessors are unused.
     */
    private static final class CapturingContext implements CompilationAnalysisContext {
        private final List<Diagnostic> diagnostics = new ArrayList<>();

        @Override
        public Package currentPackage() {
            return null;
        }

        @Override
        public PackageCompilation compilation() {
            return null;
        }

        @Override
        public void reportDiagnostic(Diagnostic diagnostic) {
            diagnostics.add(diagnostic);
        }
    }
}
