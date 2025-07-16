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

import io.ballerina.projects.DocumentId;
import io.ballerina.projects.plugins.CodeModifier;
import io.ballerina.projects.plugins.CodeModifierContext;

import java.util.HashMap;
import java.util.Map;

import static io.ballerina.compiler.syntax.tree.SyntaxKind.OBJECT_METHOD_DEFINITION;

/**
 * Code modifier for processing MCP tool annotations on remote functions.
 * 
 * <p>This modifier analyzes object method definitions and automatically generates
 * or updates MCP tool annotations with schema information during compilation.</p>
 */
public class McpCodeModifier extends CodeModifier {
    private final Map<DocumentId, ModifierContext> modifierContextMap = new HashMap<>();

    @Override
    public void init(CodeModifierContext codeModifierContext) {
        codeModifierContext.addSyntaxNodeAnalysisTask(new RemoteFunctionAnalysisTask(modifierContextMap),
                OBJECT_METHOD_DEFINITION);
        codeModifierContext.addSourceModifierTask(new McpSourceModifier(modifierContextMap));
    }
}
