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
import io.ballerina.compiler.syntax.tree.ModuleMemberDeclarationNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.NamedArgumentNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeFactory;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.NodeParser;
import io.ballerina.compiler.syntax.tree.PositionalArgumentNode;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxTree;
import io.ballerina.compiler.syntax.tree.TreeModifier;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.Module;
import io.ballerina.projects.plugins.ModifierTask;
import io.ballerina.projects.plugins.SourceModifierContext;
import io.ballerina.tools.text.TextDocument;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static io.ballerina.compiler.syntax.tree.SyntaxKind.CLOSE_BRACE_TOKEN;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.OBJECT_METHOD_DEFINITION;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.OPEN_BRACE_TOKEN;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.SERVICE_DECLARATION;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.MCP_PACKAGE_NAME;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.TOOL_ANNOTATION_NAME;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.getToolAnnotationNode;

/**
 * Source modifier task that updates MCP tool annotations in Ballerina source files.
 * 
 * <p>This modifier takes the analysis results from {@link RemoteFunctionAnalysisTask}
 * and applies the generated tool annotations to the source code by modifying function metadata.</p>
 */
public class McpSourceModifier implements ModifierTask<SourceModifierContext> {
    private final Map<DocumentId, ModifierContext> modifierContextMap;

    /**
     * Creates a new source modifier with the given modifier context map.
     * 
     * @param modifierContextMap map containing analysis results for each document
     */
    McpSourceModifier(Map<DocumentId, ModifierContext> modifierContextMap) {
        this.modifierContextMap = modifierContextMap;
    }

    /**
     * Modifies source files by updating MCP tool annotations based on analysis results.
     * 
     * @param context the source modifier context
     */
    @Override
    public void modify(SourceModifierContext context) {
        for (Map.Entry<DocumentId, ModifierContext> entry : modifierContextMap.entrySet()) {
            modifyDocumentWithTools(context, entry.getKey(), entry.getValue());
        }
    }

    private void modifyDocumentWithTools(SourceModifierContext context, DocumentId documentId,
                                         ModifierContext modifierContext) {
        Module module = context.currentPackage().module(documentId.moduleId());
        SemanticModel semanticModel = context.compilation().getSemanticModel(documentId.moduleId());
        ModulePartNode rootNode = module.document(documentId).syntaxTree().rootNode();
        ModulePartNode updatedRoot = modifyModulePartRoot(semanticModel, rootNode, modifierContext, documentId);
        updateDocument(context, module, documentId, updatedRoot);
    }

    private ModulePartNode modifyModulePartRoot(SemanticModel semanticModel, ModulePartNode modulePartNode,
                                                ModifierContext modifierContext, DocumentId documentId) {
        List<ModuleMemberDeclarationNode> modifiedMembers = getModifiedModuleMembers(semanticModel,
                modulePartNode.members(), modifierContext);
        return modulePartNode.modify().withMembers(NodeFactory.createNodeList(modifiedMembers)).apply();
    }

    private List<ModuleMemberDeclarationNode> getModifiedModuleMembers(SemanticModel semanticModel,
                                                                       NodeList<ModuleMemberDeclarationNode> members,
                                                                       ModifierContext modifierContext) {
        Map<FunctionDefinitionNode, AnnotationNode> modifiedAnnotations = getModifiedAnnotations(modifierContext);
        FormSchemaModifier formSchemaModifier = new FormSchemaModifier(modifierContext.getFormSchemaMap());
        List<ModuleMemberDeclarationNode> modifiedMembers = new ArrayList<>();

        for (ModuleMemberDeclarationNode member : members) {
            modifiedMembers.add(getModifiedModuleMember(semanticModel, member, modifiedAnnotations,
                    formSchemaModifier));
        }

        return modifiedMembers;
    }

    private Map<FunctionDefinitionNode, AnnotationNode> getModifiedAnnotations(ModifierContext modifierContext) {
        Map<FunctionDefinitionNode, AnnotationNode> updatedAnnotationMap = new HashMap<>();
        for (Map.Entry<FunctionDefinitionNode, ToolAnnotationConfig> entry : modifierContext
                .getAnnotationConfigMap().entrySet()) {
            updatedAnnotationMap.put(entry.getKey(), getModifiedAnnotation(entry.getValue()));
        }
        return updatedAnnotationMap;
    }

    private AnnotationNode getModifiedAnnotation(ToolAnnotationConfig config) {
        String mappingConstructorExpression = generateConfigMappingConstructor(config);
        String annotationString = "@" + MCP_PACKAGE_NAME + ":" + TOOL_ANNOTATION_NAME + mappingConstructorExpression;
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

    private ModuleMemberDeclarationNode getModifiedModuleMember(
            SemanticModel semanticModel,
            ModuleMemberDeclarationNode member,
            Map<FunctionDefinitionNode, AnnotationNode> modifiedAnnotations,
            FormSchemaModifier formSchemaModifier) {

        if (member.kind() == SERVICE_DECLARATION && Utils.isMcpBasicService(semanticModel, member)) {
            return modifyServiceDeclaration(semanticModel, (ServiceDeclarationNode) member, modifiedAnnotations,
                    formSchemaModifier);
        }
        return formSchemaModifier.modify(member);
    }

    private ModuleMemberDeclarationNode modifyServiceDeclaration(
            SemanticModel semanticModel,
            ServiceDeclarationNode classDefinitionNode,
            Map<FunctionDefinitionNode, AnnotationNode> modifiedAnnotations,
            FormSchemaModifier formSchemaModifier) {

        NodeList<Node> members = classDefinitionNode.members();
        ArrayList<Node> modifiedMembers = new ArrayList<>();

        for (Node member : members) {
            if (member.kind() != OBJECT_METHOD_DEFINITION) {
                modifiedMembers.add(formSchemaModifier.modify(member));
                continue;
            }

            // The analysis results are keyed by the original nodes, so annotations are looked up on those.
            FunctionDefinitionNode functionDefinitionNode = (FunctionDefinitionNode) member;
            FunctionDefinitionNode modifiedFunction = formSchemaModifier.modify(functionDefinitionNode);
            AnnotationNode modifiedAnnotationNode = modifiedAnnotations.get(functionDefinitionNode);
            if (modifiedAnnotationNode == null) {
                modifiedMembers.add(modifiedFunction);
                continue;
            }

            MetadataNode newMetadata = createOrUpdateMetadata(
                    semanticModel, functionDefinitionNode, modifiedAnnotationNode);

            FunctionDefinitionNode updatedFunction = modifiedFunction.modify()
                    .withMetadata(newMetadata)
                    .apply();

            modifiedMembers.add(updatedFunction);
        }

        return classDefinitionNode.modify().withMembers(NodeFactory.createNodeList(modifiedMembers)).apply();
    }

    private MetadataNode createOrUpdateMetadata(
            SemanticModel semanticModel,
            FunctionDefinitionNode functionDefinitionNode,
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

    private void updateDocument(SourceModifierContext context, Module module, DocumentId documentId,
                                ModulePartNode updatedRoot) {
        SyntaxTree syntaxTree = module.document(documentId).syntaxTree().modifyWith(updatedRoot);
        TextDocument textDocument = syntaxTree.textDocument();
        if (module.documentIds().contains(documentId)) {
            context.modifySourceFile(textDocument, documentId);
        } else {
            context.modifyTestSourceFile(textDocument, documentId);
        }
    }

    /**
     * Replaces each record type argument of an {@code mcp:elicitForm} call with its generated form schema.
     */
    private static class FormSchemaModifier extends TreeModifier {
        private final Map<ExpressionNode, String> formSchemas;

        FormSchemaModifier(Map<ExpressionNode, String> formSchemas) {
            this.formSchemas = formSchemas;
        }

        @SuppressWarnings("unchecked")
        <T extends Node> T modify(T node) {
            return formSchemas.isEmpty() ? node : (T) node.apply(this);
        }

        @Override
        public PositionalArgumentNode transform(PositionalArgumentNode node) {
            return formSchemaOf(node.expression())
                    .map(formSchema -> node.modify().withExpression(formSchema).apply())
                    .orElseGet(() -> super.transform(node));
        }

        @Override
        public NamedArgumentNode transform(NamedArgumentNode node) {
            return formSchemaOf(node.expression())
                    .map(formSchema -> node.modify().withExpression(formSchema).apply())
                    .orElseGet(() -> super.transform(node));
        }

        private Optional<ExpressionNode> formSchemaOf(ExpressionNode argument) {
            return Optional.ofNullable(formSchemas.get(argument)).map(NodeParser::parseExpression);
        }
    }
}
