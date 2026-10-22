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

import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;

import java.util.Optional;

/**
 * One module's source rewrites for one document. Nodes passed as {@code original} are from the unmodified tree, which
 * the analysis tasks keyed their results by.
 */
public interface DocumentRewriter {

    /**
     * Returns the expression that replaces the given function argument, if any.
     *
     * @param original the argument expression in the unmodified tree
     * @return the replacement expression
     */
    default Optional<ExpressionNode> rewriteArgument(ExpressionNode original) {
        return Optional.empty();
    }

    /**
     * Rewrites a function definition.
     *
     * @param original    the function in the unmodified tree
     * @param transformed the function with its nested rewrites already applied
     * @return the rewritten function, or {@code transformed} if this module does not rewrite it
     */
    default FunctionDefinitionNode rewriteFunction(FunctionDefinitionNode original,
                                                   FunctionDefinitionNode transformed) {
        return transformed;
    }
}
