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


import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.syntax.tree.ListenerDeclarationNode;
import io.ballerina.compiler.syntax.tree.NodeVisitor;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

/**
 * Holds the {@link ModuleMemberVisitor} of each module in the package and resolves
 * listener and variable declarations across module boundaries.
 */
public class PackageMemberVisitor extends NodeVisitor {

    private Map<String, ModuleMemberVisitor> moduleVisitors = new LinkedHashMap<>();

    /**
     * Replaces the tracked module visitors with the given mapping.
     *
     * @param moduleVisitors the module visitors keyed by module name
     */
    public void setModuleVisitors(Map<String, ModuleMemberVisitor> moduleVisitors) {
        this.moduleVisitors = new LinkedHashMap<>(moduleVisitors);
    }

    /**
     * Registers a new visitor for the given module and returns the updated, unmodifiable mapping.
     *
     * @param moduleName    the module name
     * @param semanticModel the semantic model of the module
     * @return the updated module visitors keyed by module name
     */
    public Map<String, ModuleMemberVisitor> createModuleVisitor(String moduleName,
                                                                SemanticModel semanticModel) {
        ModuleMemberVisitor visitor = new ModuleMemberVisitor(semanticModel);
        this.moduleVisitors.put(moduleName, visitor);
        return Collections.unmodifiableMap(new LinkedHashMap<>(this.moduleVisitors));
    }

    /**
     * Returns the visitor for the given module, if present.
     *
     * @param moduleName the module name
     * @return the module visitor, or empty if the module is not tracked
     */
    public Optional<ModuleMemberVisitor> getModuleVisitor(String moduleName) {
        if (moduleVisitors.containsKey(moduleName)) {
            return Optional.of(moduleVisitors.get(moduleName));
        }
        return Optional.empty();
    }

    /**
     * Resolves a listener declaration by name within the given module.
     *
     * @param moduleName   the module name
     * @param listenerName the listener variable name
     * @return the listener declaration, or empty if not found
     */
    public Optional<ListenerDeclarationNode> getListenerDeclaration(String moduleName, String listenerName) {
        return getModuleVisitor(moduleName)
                .flatMap(moduleVisitor -> moduleVisitor.getListenerDeclaration(listenerName));
    }

    /**
     * Resolves the declared value of a variable or constant within the given module.
     *
     * @param moduleName   the module name
     * @param variableName the variable or constant name
     * @return the declared value, or empty if not found
     */
    public Optional<ModuleMemberVisitor.VariableDeclaredValue> getVariableDeclaredValue(String moduleName,
                                                                                        String variableName) {
        return getModuleVisitor(moduleName)
                .flatMap(moduleVisitor -> moduleVisitor.getVariableDeclaredValue(variableName));
    }
}
