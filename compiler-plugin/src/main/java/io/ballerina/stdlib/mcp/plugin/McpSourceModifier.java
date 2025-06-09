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

package io.ballerina.stdlib.mcp.plugin;

import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.MappingConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.ModuleMemberDeclarationNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeFactory;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.NodeParser;
import io.ballerina.compiler.syntax.tree.QualifiedNameReferenceNode;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxTree;
import io.ballerina.compiler.syntax.tree.Token;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.Module;
import io.ballerina.projects.plugins.ModifierTask;
import io.ballerina.projects.plugins.SourceModifierContext;
import io.ballerina.tools.text.TextDocument;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static io.ballerina.compiler.syntax.tree.SyntaxKind.CLOSE_BRACE_TOKEN;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.COLON_TOKEN;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.OBJECT_METHOD_DEFINITION;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.OPEN_BRACE_TOKEN;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.QUALIFIED_NAME_REFERENCE;
import static io.ballerina.compiler.syntax.tree.SyntaxKind.SERVICE_DECLARATION;
import static io.ballerina.stdlib.mcp.plugin.RemoteFunctionAnalysisTask.EMPTY_STRING;

public class McpSourceModifier implements ModifierTask<SourceModifierContext> {
    private final Map<DocumentId, ModifierContext> modifierContextMap;

    McpSourceModifier(Map<DocumentId, ModifierContext> modifierContextMap) {
        this.modifierContextMap = modifierContextMap;
    }

    @Override
    public void modify(SourceModifierContext context) {
        for (Map.Entry<DocumentId, ModifierContext> entry : modifierContextMap.entrySet()) {
            modifyDocumentWithTools(context, entry.getKey(), entry.getValue());
        }
    }

    private void modifyDocumentWithTools(SourceModifierContext context, DocumentId documentId,
                                         ModifierContext modifierContext) {
        Module module = context.currentPackage().module(documentId.moduleId());
        ModulePartNode rootNode = module.document(documentId).syntaxTree().rootNode();
        ModulePartNode updatedRoot = modifyModulePartRoot(rootNode, modifierContext, documentId);
        updateDocument(context, module, documentId, updatedRoot);
    }

    private ModulePartNode modifyModulePartRoot(ModulePartNode modulePartNode,
                                                ModifierContext modifierContext, DocumentId documentId) {
        List<ModuleMemberDeclarationNode> modifiedMembers = getModifiedModuleMembers(modulePartNode.members(),
                modifierContext, documentId);
        return modulePartNode.modify().withMembers(NodeFactory.createNodeList(modifiedMembers)).apply();
    }

    private List<ModuleMemberDeclarationNode> getModifiedModuleMembers(NodeList<ModuleMemberDeclarationNode> members,
                                                                       ModifierContext modifierContext,
                                                                       DocumentId documentId) {
        Map<AnnotationNode, AnnotationNode> modifiedAnnotations = getModifiedAnnotations(modifierContext);
        List<ModuleMemberDeclarationNode> modifiedMembers = new ArrayList<>();

        for (ModuleMemberDeclarationNode member : members) {
            modifiedMembers.add(getModifiedModuleMember(member, modifiedAnnotations));
        }

        return modifiedMembers;
    }

    private Map<AnnotationNode, AnnotationNode> getModifiedAnnotations(ModifierContext modifierContext) {
        Map<AnnotationNode, AnnotationNode> updatedAnnotationMap = new HashMap<>();
        for (Map.Entry<AnnotationNode, ToolAnnotationConfig> entry : modifierContext
                .getAnnotationConfigMap().entrySet()) {
            updatedAnnotationMap.put(entry.getKey(), getModifiedAnnotation(entry.getKey(), entry.getValue()));
        }
        return updatedAnnotationMap;
    }

    private AnnotationNode getModifiedAnnotation(AnnotationNode targetNode, ToolAnnotationConfig config) {
        String mappingConstructorExpression = generateConfigMappingConstructor(config);
        MappingConstructorExpressionNode mappingConstructorNode = (MappingConstructorExpressionNode) NodeParser
                .parseExpression(mappingConstructorExpression);

        Node annotationReference = targetNode.annotReference();
        if (annotationReference.kind() == QUALIFIED_NAME_REFERENCE) {
            QualifiedNameReferenceNode qualifiedNameReferenceNode = (QualifiedNameReferenceNode) annotationReference;
            String identifier = qualifiedNameReferenceNode.identifier().text().replaceAll("\\R", EMPTY_STRING);
            String modulePrefix = qualifiedNameReferenceNode.modulePrefix().text();
            annotationReference = NodeFactory.createQualifiedNameReferenceNode(
                    NodeFactory.createIdentifierToken(modulePrefix),
                    NodeFactory.createToken(COLON_TOKEN),
                    NodeFactory.createIdentifierToken(identifier)
            );
            Token closeBraceTokenWithNewLine = NodeFactory.createToken(
                    CLOSE_BRACE_TOKEN,
                    NodeFactory.createEmptyMinutiaeList(),
                    NodeFactory.createMinutiaeList(
                            NodeFactory.createEndOfLineMinutiae(System.lineSeparator())));
            mappingConstructorNode = mappingConstructorNode.modify().withCloseBrace(closeBraceTokenWithNewLine).apply();
        }
        return NodeFactory.createAnnotationNode(targetNode.atToken(), annotationReference, mappingConstructorNode);
    }

    private String generateConfigMappingConstructor(ToolAnnotationConfig config) {
        return generateConfigMappingConstructor(config, OPEN_BRACE_TOKEN.stringValue(),
                CLOSE_BRACE_TOKEN.stringValue());
    }

    private String generateConfigMappingConstructor(ToolAnnotationConfig config, String openBraceSource,
                                                    String closeBraceSource) {
        return openBraceSource + String.format("description:%s,schema:%s",
                config.description() != null ? config.description().replaceAll("\\R", " ") : "",
                config.schema()) + closeBraceSource;
    }

    private ModuleMemberDeclarationNode getModifiedModuleMember(ModuleMemberDeclarationNode member,
                                                                Map<AnnotationNode, AnnotationNode> modifiedAnnotations
    ) {

        if (member.kind() == SERVICE_DECLARATION) {
            return modifyServiceDeclaration((ServiceDeclarationNode) member, modifiedAnnotations);
        }
        return member;
    }

    private ModuleMemberDeclarationNode modifyServiceDeclaration(ServiceDeclarationNode classDefinitionNode,
                                                              Map<AnnotationNode, AnnotationNode> modifiedAnnotations) {
        NodeList<Node> members = classDefinitionNode.members();
        ArrayList<Node> modifiedMembers = new ArrayList<>();

        for (Node member : members) {
            if (member.kind() == OBJECT_METHOD_DEFINITION) {
                FunctionDefinitionNode methodDeclarationNode = (FunctionDefinitionNode) member;
                if (methodDeclarationNode.metadata().isPresent()) {
                    MetadataNode modifiedMetadata = modifyMetadata(methodDeclarationNode.metadata().get(),
                            modifiedAnnotations);
                    methodDeclarationNode = methodDeclarationNode.modify().withMetadata(modifiedMetadata).apply();
                }
                modifiedMembers.add(methodDeclarationNode);
            } else {
                modifiedMembers.add(member);
            }
        }
        return classDefinitionNode.modify().withMembers(NodeFactory.createNodeList(modifiedMembers)).apply();
    }

    private MetadataNode modifyMetadata(MetadataNode metadata,
                                        Map<AnnotationNode, AnnotationNode> modifiedAnnotations) {
        List<AnnotationNode> updatedAnnotations = new ArrayList<>();
        for (AnnotationNode annotation : metadata.annotations()) {
            updatedAnnotations.add(modifiedAnnotations.getOrDefault(annotation, annotation));
        }
        return metadata.modify().withAnnotations(NodeFactory.createNodeList(updatedAnnotations)).apply();
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
}
