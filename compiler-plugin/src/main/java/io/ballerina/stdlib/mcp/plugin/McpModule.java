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
import io.ballerina.compiler.api.symbols.ModuleSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.syntax.tree.ImportDeclarationNode;
import io.ballerina.compiler.syntax.tree.ImportPrefixNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;

import java.util.Optional;

/**
 * The modules of the {@code ballerina/mcp} package that the compiler plugin processes. Each rule set handles only
 * code whose defining symbols belong to its own module, matched by org and exact module name.
 */
public enum McpModule {
    ROOT("mcp"),
    V2("mcp.v2");

    private static final String BALLERINA_ORG = "ballerina";
    private static final String IGNORED_PREFIX = "_";

    private final String moduleName;

    McpModule(String moduleName) {
        this.moduleName = moduleName;
    }

    public String moduleName() {
        return moduleName;
    }

    /**
     * Returns whether the given symbol is defined in this module.
     *
     * @param symbol the symbol to check
     * @return true if the symbol's module is this module
     */
    public boolean defines(Symbol symbol) {
        return symbol.getModule().map(this::isModule).orElse(false);
    }

    private boolean isModule(ModuleSymbol module) {
        return BALLERINA_ORG.equals(module.id().orgName()) && moduleName.equals(module.id().moduleName());
    }

    /**
     * Returns the prefix that the document binds to this module, if code in the document can reference it.
     *
     * @param semanticModel the semantic model of the document's module
     * @param modulePart    the root node of the document
     * @return the import prefix, or empty if the module is not imported or is imported as {@code _}
     */
    public Optional<String> prefixIn(SemanticModel semanticModel, ModulePartNode modulePart) {
        for (ImportDeclarationNode importNode : modulePart.imports()) {
            Optional<Symbol> symbol = semanticModel.symbol(importNode);
            if (symbol.isEmpty() || !(symbol.get() instanceof ModuleSymbol module) || !isModule(module)) {
                continue;
            }
            String prefix = importNode.prefix().map(ImportPrefixNode::prefix).map(token -> token.text())
                    .orElseGet(() -> importNode.moduleName().get(importNode.moduleName().size() - 1).text());
            return IGNORED_PREFIX.equals(prefix) ? Optional.empty() : Optional.of(prefix);
        }
        return Optional.empty();
    }
}
