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

import io.ballerina.compiler.api.symbols.ConstantSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.values.ConstantValue;
import io.ballerina.compiler.syntax.tree.AnnotationNode;
import io.ballerina.compiler.syntax.tree.BinaryExpressionNode;
import io.ballerina.compiler.syntax.tree.BracedExpressionNode;
import io.ballerina.compiler.syntax.tree.ExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.MappingFieldNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.SpecificFieldNode;
import io.ballerina.compiler.syntax.tree.SpreadFieldNode;
import io.ballerina.compiler.syntax.tree.UnaryExpressionNode;
import io.ballerina.projects.Document;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;

import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/** Reads known annotation values without guessing the values of runtime expressions. */
final class AnnotationValues {
    private static final Value UNKNOWN = new Value(false, null);

    private AnnotationValues() {
    }

    record Value(boolean known, Object value) {
    }

    static Value field(AnnotationNode annotation, String name, Object defaultValue,
                       SyntaxNodeAnalysisContext context) {
        return annotation.annotValue().map(mapping -> field(mapping, name, new Value(true, defaultValue), context))
                .orElse(new Value(true, defaultValue));
    }

    private static Value field(MappingConstructorExpressionNode mapping, String name, Value defaultValue,
                               SyntaxNodeAnalysisContext context) {
        Value result = defaultValue;
        for (MappingFieldNode field : mapping.fields()) {
            if (field instanceof SpecificFieldNode specific) {
                String key = specific.fieldName().toSourceCode().trim().replace("\"", "");
                if (name.equals(key)) {
                    result = constant(specific.valueExpr().map(Node.class::cast)
                            .orElse(specific.fieldName()), context);
                }
            } else if (field instanceof SpreadFieldNode spread) {
                if (spread.valueExpr() instanceof MappingConstructorExpressionNode nested) {
                    result = field(nested, name, result, context);
                } else {
                    Value supplied = constant(spread.valueExpr(), context);
                    if (supplied.known() && supplied.value() instanceof Map<?, ?> values) {
                        if (values.containsKey(name)) {
                            result = new Value(true, unwrap(values.get(name)));
                        }
                    } else {
                        result = UNKNOWN;
                    }
                }
            } else {
                result = UNKNOWN;
            }
        }
        return result;
    }

    private static Value constant(Node expression, SyntaxNodeAnalysisContext context) {
        String source = expression.toSourceCode().trim();
        if ("true".equals(source) || "false".equals(source)) {
            return new Value(true, Boolean.valueOf(source));
        }
        if ("()".equals(source)) {
            return new Value(true, null);
        }
        if (source.startsWith("\"") && source.endsWith("\"") && !source.contains("\\")) {
            return new Value(true, source.substring(1, source.length() - 1));
        }
        if (expression instanceof MappingConstructorExpressionNode) {
            return new Value(true, expression);
        }
        if (expression instanceof BracedExpressionNode braced) {
            return constant(braced.expression(), context);
        }
        if (expression instanceof UnaryExpressionNode unary) {
            Value operand = constant(unary.expression(), context);
            if ("!".equals(unary.unaryOperator().text()) && operand.known()
                    && operand.value() instanceof Boolean enabled) {
                return new Value(true, !enabled);
            }
            return UNKNOWN;
        }
        if (expression instanceof BinaryExpressionNode binary) {
            Value left = constant(binary.lhsExpr(), context);
            Value right = constant(binary.rhsExpr(), context);
            if (!left.known() || !right.known()
                    || !isScalarConstant(left.value()) || !isScalarConstant(right.value())) {
                return UNKNOWN;
            }
            return switch (binary.operator().text()) {
                case "==", "===" -> new Value(true, Objects.equals(left.value(), right.value()));
                case "!=", "!==" -> new Value(true, !Objects.equals(left.value(), right.value()));
                case "&&" -> left.value() instanceof Boolean first && right.value() instanceof Boolean second
                        ? new Value(true, first && second) : UNKNOWN;
                case "||" -> left.value() instanceof Boolean first && right.value() instanceof Boolean second
                        ? new Value(true, first || second) : UNKNOWN;
                default -> UNKNOWN;
            };
        }
        Optional<Symbol> symbol = expression instanceof ExpressionNode
                ? context.semanticModel().symbol(expression) : Optional.empty();
        if (symbol.isEmpty()) {
            Document document = context.currentPackage().module(context.moduleId()).document(context.documentId());
            symbol = context.semanticModel().symbol(document, expression.lineRange().startLine());
        }
        if (symbol.isPresent() && symbol.get() instanceof ConstantSymbol constant) {
            return new Value(true, unwrap(constant.constValue()));
        }
        return UNKNOWN;
    }

    private static boolean isScalarConstant(Object value) {
        return value == null || value instanceof Boolean || value instanceof String;
    }

    private static Object unwrap(Object value) {
        return value instanceof ConstantValue constant ? unwrap(constant.value()) : value;
    }
}
