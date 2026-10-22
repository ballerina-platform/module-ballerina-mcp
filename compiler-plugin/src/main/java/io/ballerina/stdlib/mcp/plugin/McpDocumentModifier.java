/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
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

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.NamedArgumentNode;
import io.ballerina.compiler.syntax.tree.PositionalArgumentNode;
import io.ballerina.compiler.syntax.tree.SyntaxTree;
import io.ballerina.compiler.syntax.tree.TreeModifier;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.Module;
import io.ballerina.projects.plugins.ModifierTask;
import io.ballerina.projects.plugins.SourceModifierContext;
import io.ballerina.tools.text.TextDocument;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * Applies the source rewrites of both modules' rule sets in one pass per document, so that each rewrite is applied
 * exactly once even when a document uses both modules.
 */
public class McpDocumentModifier implements ModifierTask<SourceModifierContext> {
    private final McpSourceModifier sourceModifier;
    private final io.ballerina.stdlib.mcp.plugin.v2.McpSourceModifier v2SourceModifier;

    McpDocumentModifier(McpSourceModifier sourceModifier,
                        io.ballerina.stdlib.mcp.plugin.v2.McpSourceModifier v2SourceModifier) {
        this.sourceModifier = sourceModifier;
        this.v2SourceModifier = v2SourceModifier;
    }

    @Override
    public void modify(SourceModifierContext context) {
        Set<DocumentId> documentIds = new LinkedHashSet<>(sourceModifier.documentIds());
        documentIds.addAll(v2SourceModifier.documentIds());
        for (DocumentId documentId : documentIds) {
            Module module = context.currentPackage().module(documentId.moduleId());
            SemanticModel semanticModel = context.compilation().getSemanticModel(documentId.moduleId());
            ModulePartNode rootNode = module.document(documentId).syntaxTree().rootNode();

            List<DocumentRewriter> rewriters = new ArrayList<>();
            sourceModifier.rewriter(documentId, semanticModel, rootNode).ifPresent(rewriters::add);
            v2SourceModifier.rewriter(documentId, semanticModel, rootNode).ifPresent(rewriters::add);
            if (rewriters.isEmpty()) {
                continue;
            }
            ModulePartNode updatedRoot = (ModulePartNode) rootNode.apply(new RewritingTreeModifier(rewriters));
            updateDocument(context, module, documentId, updatedRoot);
        }
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

    private static class RewritingTreeModifier extends TreeModifier {
        private final List<DocumentRewriter> rewriters;

        RewritingTreeModifier(List<DocumentRewriter> rewriters) {
            this.rewriters = rewriters;
        }

        @Override
        public FunctionDefinitionNode transform(FunctionDefinitionNode node) {
            FunctionDefinitionNode transformed = super.transform(node);
            for (DocumentRewriter rewriter : rewriters) {
                transformed = rewriter.rewriteFunction(node, transformed);
            }
            return transformed;
        }

        @Override
        public PositionalArgumentNode transform(PositionalArgumentNode node) {
            return rewriteArgument(node.expression())
                    .map(expression -> node.modify().withExpression(expression).apply())
                    .orElseGet(() -> super.transform(node));
        }

        @Override
        public NamedArgumentNode transform(NamedArgumentNode node) {
            return rewriteArgument(node.expression())
                    .map(expression -> node.modify().withExpression(expression).apply())
                    .orElseGet(() -> super.transform(node));
        }

        private Optional<ExpressionNode> rewriteArgument(ExpressionNode original) {
            for (DocumentRewriter rewriter : rewriters) {
                Optional<ExpressionNode> rewritten = rewriter.rewriteArgument(original);
                if (rewritten.isPresent()) {
                    return rewritten;
                }
            }
            return Optional.empty();
        }
    }
}
