/*
 * Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
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

package io.ballerina.stdlib.mcp.plugin.v2;

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.NodeFactory;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.NodeParser;
import io.ballerina.projects.DocumentId;
import io.ballerina.stdlib.mcp.plugin.DocumentRewriter;
import io.ballerina.stdlib.mcp.plugin.McpModule;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import static io.ballerina.compiler.syntax.tree.SyntaxKind.CLOSE_BRACE_TOKEN;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.OPEN_BRACE_TOKEN;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.TOOL_ANNOTATION_NAME;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.getToolAnnotationNode;

/**
 * Updates MCP tool annotations in Ballerina source files, and replaces the record type arguments of
 * {@code mcp:elicitForm} calls with their generated form schemas.
 * 
 * <p>This modifier takes the analysis results from {@link RemoteFunctionAnalysisTask} and
 * {@link ElicitFormAnalysisTask} and applies them to the source code.</p>
 */
public class McpSourceModifier {
    private final Map<DocumentId, ModifierContext> modifierContextMap;

    /**
     * Creates a new source modifier with the given modifier context map.
     * 
     * @param modifierContextMap map containing analysis results for each document
     */
    McpSourceModifier(Map<DocumentId, ModifierContext> modifierContextMap) {
        this.modifierContextMap = modifierContextMap;
    }

    public Set<DocumentId> documentIds() {
        return modifierContextMap.keySet();
    }

    /**
     * Returns the rewriter of the given document. Tool annotations are only generated when the document can
     * reference this module's annotations; form schemas need no prefix.
     *
     * @param documentId    the document
     * @param semanticModel the semantic model of the document's module
     * @param modulePart    the root node of the document
     * @return the rewriter, or empty if the document has no analysis results
     */
    public Optional<DocumentRewriter> rewriter(DocumentId documentId, SemanticModel semanticModel,
                                               ModulePartNode modulePart) {
        ModifierContext modifierContext = modifierContextMap.get(documentId);
        if (modifierContext == null) {
            return Optional.empty();
        }
        Optional<String> modulePrefix = McpModule.V2.prefixIn(semanticModel, modulePart);
        return Optional.of(new V2DocumentRewriter(semanticModel, modifierContext, modulePrefix.orElse(null)));
    }

    private static final class V2DocumentRewriter implements DocumentRewriter {
        private final SemanticModel semanticModel;
        private final ModifierContext modifierContext;
        private final String modulePrefix;

        V2DocumentRewriter(SemanticModel semanticModel, ModifierContext modifierContext, String modulePrefix) {
            this.semanticModel = semanticModel;
            this.modifierContext = modifierContext;
            this.modulePrefix = modulePrefix;
        }

        @Override
        public Optional<ExpressionNode> rewriteArgument(ExpressionNode original) {
            return Optional.ofNullable(modifierContext.getFormSchemaMap().get(original))
                    .map(NodeParser::parseExpression);
        }

        @Override
        public FunctionDefinitionNode rewriteFunction(FunctionDefinitionNode original,
                                                      FunctionDefinitionNode transformed) {
            ToolAnnotationConfig config = modifierContext.getAnnotationConfigMap().get(original);
            if (config == null || modulePrefix == null) {
                return transformed;
            }
            // The analysis results are keyed by the original nodes, so annotations are looked up on those.
            MetadataNode newMetadata = createOrUpdateMetadata(original, getModifiedAnnotation(config));
            return transformed.modify().withMetadata(newMetadata).apply();
        }

        private AnnotationNode getModifiedAnnotation(ToolAnnotationConfig config) {
            String mappingConstructorExpression = generateConfigMappingConstructor(config);
            String annotationString = "@" + modulePrefix + ":" + TOOL_ANNOTATION_NAME + mappingConstructorExpression;
            return NodeParser.parseAnnotation(annotationString);
        }

        private String generateConfigMappingConstructor(ToolAnnotationConfig config) {
            return generateConfigMappingConstructor(config, OPEN_BRACE_TOKEN.stringValue(),
                    CLOSE_BRACE_TOKEN.stringValue());
        }

        private String generateConfigMappingConstructor(ToolAnnotationConfig config, String openBraceSource,
                                                        String closeBraceSource) {
            StringBuilder sb = new StringBuilder();
            sb.append(openBraceSource);
            String desc = config.description().replaceAll("\\R", " ");
            sb.append("description:").append(desc).append(",");
            sb.append("schema:").append(config.schema()).append(",");
            sb.append("outputSchema:").append(config.outputSchema()).append(",");
            sb.append("structuredOutput:").append(config.structuredOutput());
            // Scopes are enforced by the server only; they are carried through unchanged.
            if (config.scopes() != null) {
                sb.append(",scopes:").append(config.scopes());
            }
            sb.append(closeBraceSource);
            return sb.toString();
        }

        private MetadataNode createOrUpdateMetadata(FunctionDefinitionNode functionDefinitionNode,
                                                    AnnotationNode modifiedAnnotationNode) {
            if (functionDefinitionNode.metadata().isEmpty()) {
                return createMetadata(modifiedAnnotationNode);
            }

            MetadataNode existingMetadata = functionDefinitionNode.metadata().get();
            Optional<AnnotationNode> toolAnnotationNode = getToolAnnotationNode(semanticModel, functionDefinitionNode);

            if (toolAnnotationNode.isPresent()) {
                return modifyMetadata(existingMetadata, toolAnnotationNode.get(), modifiedAnnotationNode);
            } else {
                return modifyWithToolAnnotation(existingMetadata, modifiedAnnotationNode);
            }
        }

        private MetadataNode modifyWithToolAnnotation(MetadataNode metadata, AnnotationNode annotationNode) {
            List<AnnotationNode> updatedAnnotations = new ArrayList<>();
            metadata.annotations().forEach(updatedAnnotations::add);
            updatedAnnotations.add(annotationNode);
            return metadata.modify()
                    .withAnnotations(NodeFactory.createNodeList(updatedAnnotations))
                    .apply();
        }

        private MetadataNode modifyMetadata(MetadataNode metadata, AnnotationNode toolAnnotationNode,
                                            AnnotationNode modifiedAnnotationNode) {
            List<AnnotationNode> updatedAnnotations = new ArrayList<>();
            for (AnnotationNode annotation : metadata.annotations()) {
                if (annotation.equals(toolAnnotationNode)) {
                    updatedAnnotations.add(modifiedAnnotationNode);
                } else {
                    updatedAnnotations.add(annotation);
                }
            }
            return metadata.modify().withAnnotations(NodeFactory.createNodeList(updatedAnnotations)).apply();
        }

        private MetadataNode createMetadata(AnnotationNode annotationNode) {
            NodeList<AnnotationNode> annotationNodeList = NodeFactory.createNodeList(annotationNode);
            return NodeFactory.createMetadataNode(null, annotationNodeList);
        }
    }
}
