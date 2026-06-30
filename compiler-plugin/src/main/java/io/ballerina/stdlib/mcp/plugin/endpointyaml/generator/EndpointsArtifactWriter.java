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

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import com.fasterxml.jackson.dataformat.yaml.YAMLGenerator;
import io.ballerina.projects.plugins.CompilationAnalysisContext;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;
import io.ballerina.tools.text.LinePosition;
import io.ballerina.tools.text.LineRange;
import io.ballerina.tools.text.TextRange;

import java.io.IOException;
import java.io.Writer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;

/**
 * Writes the consolidated {@code endpoints.yaml} artifact under {@code target/artifact}.
 *
 * <p>All MCP services of the package are written into a single file. If the file already exists it is merged: entries
 * owned by other modules are preserved verbatim, previously written MCP entries are replaced with the current ones, and
 * an unrecognizable file is left untouched with an error diagnostic.
 */
public class EndpointsArtifactWriter {

    private static final String ARTIFACT = "artifact";
    private static final String ENDPOINTS_FILE = "endpoints.yaml";
    private static final String ENDPOINTS_KEY = "endpoints";
    private static final String MCP_TYPE = "mcp";

    private final ObjectMapper yamlMapper;

    public EndpointsArtifactWriter() {
        YAMLFactory yamlFactory = YAMLFactory.builder()
                .disable(YAMLGenerator.Feature.WRITE_DOC_START_MARKER)
                .build();
        this.yamlMapper = new ObjectMapper(yamlFactory);
        this.yamlMapper.findAndRegisterModules();
    }

    /**
     * Merges the given MCP endpoints into {@code target/artifact/endpoints.yaml}, creating the artifact directory if
     * needed.
     *
     * @param targetDir    the project's target directory
     * @param mcpEndpoints the MCP endpoints extracted from the package
     * @param context      the compilation analysis context used to report diagnostics
     * @throws IOException if the artifact directory or file cannot be written
     */
    public void write(Path targetDir, List<Endpoint> mcpEndpoints, CompilationAnalysisContext context)
            throws IOException {
        Path artifactDir = targetDir.resolve(ARTIFACT);
        Path endpointsFile = artifactDir.resolve(ENDPOINTS_FILE);

        List<Endpoint> merged = new ArrayList<>();
        if (Files.exists(endpointsFile)) {
            List<Endpoint> preserved = readForeignEntries(endpointsFile, context);
            if (preserved == null) {
                // The existing file could not be recognized; a diagnostic was reported, and we must not overwrite it.
                return;
            }
            merged.addAll(preserved);
        }
        merged.addAll(mcpEndpoints);

        Files.createDirectories(artifactDir);
        writeAtomically(artifactDir, endpointsFile, new EndpointWrapper(merged));
    }

    /**
     * Reads the entries owned by other modules from an existing artifact, dropping previously written MCP entries.
     *
     * @return the entries to preserve, or {@code null} if the file is not a recognizable endpoints document
     */
    private List<Endpoint> readForeignEntries(Path endpointsFile, CompilationAnalysisContext context) {
        JsonNode root;
        try {
            root = yamlMapper.readTree(endpointsFile.toFile());
        } catch (IOException e) {
            reportUnreadableArtifact(context, endpointsFile, e.getMessage());
            return null;
        }

        if (root == null || !root.isObject() || !root.has(ENDPOINTS_KEY) || !root.get(ENDPOINTS_KEY).isArray()) {
            reportUnreadableArtifact(context, endpointsFile,
                    "the file does not contain an `" + ENDPOINTS_KEY + "` list");
            return null;
        }

        List<Endpoint> preserved = new ArrayList<>();
        try {
            for (JsonNode entry : root.get(ENDPOINTS_KEY)) {
                Endpoint endpoint = yamlMapper.treeToValue(entry, Endpoint.class);
                if (!MCP_TYPE.equals(endpoint.getType())) {
                    preserved.add(endpoint);
                }
            }
        } catch (IOException e) {
            reportUnreadableArtifact(context, endpointsFile, e.getMessage());
            return null;
        }
        return preserved;
    }

    private void writeAtomically(Path artifactDir, Path endpointsFile, EndpointWrapper wrapper) throws IOException {
        Path tempFile = Files.createTempFile(artifactDir, ENDPOINTS_FILE, ".tmp");
        try (Writer writer = Files.newBufferedWriter(tempFile)) {
            yamlMapper.writeValue(writer, wrapper);
        }
        try {
            Files.move(tempFile, endpointsFile,
                    StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException atomicFailure) {
            // ATOMIC_MOVE is not supported on every filesystem; fall back to a plain replace.
            Files.move(tempFile, endpointsFile, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private void reportUnreadableArtifact(CompilationAnalysisContext context, Path endpointsFile, String detail) {
        DiagnosticInfo diagnosticInfo = new DiagnosticInfo(
                "ENDPOINTS_ARTIFACT_NOT_READABLE",
                "The existing endpoint artifact '" + endpointsFile + "' could not be parsed and will not be " +
                        "overwritten: " + detail,
                DiagnosticSeverity.ERROR
        );
        context.reportDiagnostic(DiagnosticFactory.createDiagnostic(diagnosticInfo, new NullLocation()));
    }

    /**
     * A {@link Location} placeholder for the unreadable-artifact diagnostic, which is not tied to a specific source
     * node.
     */
    private static class NullLocation implements Location {

        @Override
        public LineRange lineRange() {
            return LineRange.from("", LinePosition.from(0, 0), LinePosition.from(0, 0));
        }

        @Override
        public TextRange textRange() {
            return TextRange.from(0, 0);
        }
    }
}
