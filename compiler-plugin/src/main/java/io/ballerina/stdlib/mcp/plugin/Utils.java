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

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.Documentable;
import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.SymbolKind;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.MetadataNode;
import io.ballerina.compiler.syntax.tree.NodeList;

import java.util.Optional;

/**
 * Util class for the compiler plugin.
 */
public class Utils {
    public static final String BALLERINA_ORG = "ballerina";
    public static final String TOOL_ANNOTATION_NAME = "McpTool";
    public static final String MCP_PACKAGE_NAME = "mcp";

    private Utils() {
    }

    public static boolean isMcpToolAnnotation(AnnotationSymbol annotationSymbol) {
        return annotationSymbol.getModule().isPresent()
                && isMcpModuleSymbol(annotationSymbol.getModule().get())
                && annotationSymbol.getName().isPresent()
                && TOOL_ANNOTATION_NAME.equals(annotationSymbol.getName().get());
    }

    public static boolean isMcpModuleSymbol(Symbol symbol) {
        return symbol.getModule().isPresent()
                && MCP_PACKAGE_NAME.equals(symbol.getModule().get().id().moduleName())
                && BALLERINA_ORG.equals(symbol.getModule().get().id().orgName());
    }

    public static String getParameterDescription(FunctionSymbol functionSymbol, String parameterName) {
        if (functionSymbol.documentation().isEmpty()
                || functionSymbol.documentation().get().description().isEmpty()) {
            return null;
        }
        return functionSymbol.documentation().get().parameterMap().getOrDefault(parameterName, null);
    }

    public static String getDescription(Documentable documentable) {
        if (documentable.documentation().isEmpty()
                || documentable.documentation().get().description().isEmpty()) {
            return null;
        }
        return documentable.documentation().get().description().get();
    }

    public static String escapeDoubleQuotes(String input) {
        return input.replace("\"", "\\\"");
    }


    public static String addDoubleQuotes(String input) {
        return "\"" + input + "\"";
    }

    public static Optional<AnnotationNode> getToolAnnotationNode(SemanticModel semanticModel,
                                                                 FunctionDefinitionNode functionDefinitionNode) {
        Optional<MetadataNode> metadataNode = functionDefinitionNode.metadata();
        if (metadataNode.isEmpty()) {
            return Optional.empty();
        }

        NodeList<AnnotationNode> annotationNodes = metadataNode.get().annotations();
        return annotationNodes.stream()
                .filter(annotationNode ->
                        semanticModel.symbol(annotationNode)
                                .filter(symbol -> symbol.kind() == SymbolKind.ANNOTATION)
                                .filter(symbol -> Utils.isMcpToolAnnotation((AnnotationSymbol) symbol))
                                .isPresent()
                )
                .findFirst();
    }
}
