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

package io.ballerina.stdlib.mcp;

import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BDecimal;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

import static io.ballerina.runtime.api.utils.StringUtils.fromString;

/** Validates SEP-2243 annotations and mirrors only statically reachable primitive arguments. */
public final class ProtocolHeaders {
    private static final String PREFIX = "=?base64?";
    private static final Pattern TOKEN = Pattern.compile("[!#$%&'*+.^_`|~0-9A-Za-z-]+");
    private static final long MAX_INTEGER = 9007199254740991L;

    private ProtocolHeaders() {
    }

    public static BString encodeProtocolHeader(BString value) {
        String text = value.getValue();
        if (!safe(text) || sentinel(text)) {
            return fromString(PREFIX + Base64.getEncoder()
                    .encodeToString(text.getBytes(StandardCharsets.UTF_8)) + "?=");
        }
        return value;
    }

    public static Object decodeProtocolHeader(BString value) {
        String text = value.getValue();
        try {
            if (!safe(text)) {
                throw new IllegalArgumentException("Unsafe MCP header value");
            }
            if (!sentinel(text)) {
                return value;
            }
            byte[] decoded = Base64.getDecoder().decode(text.substring(PREFIX.length(), text.length() - 2));
            return fromString(StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(decoded)).toString());
        } catch (IllegalArgumentException | CharacterCodingException exception) {
            return ModuleUtils.createParameterBindingError("Invalid MCP header encoding");
        }
    }

    private static boolean sentinel(String value) {
        return value.startsWith(PREFIX) && value.endsWith("?=");
    }

    private static boolean safe(String value) {
        return value.equals(value.strip()) && value.chars().allMatch(c -> c >= 32 && c <= 126 || c == 9);
    }

    public static Object toolParameterHeaders(BMap<?, ?> schema, BMap<?, ?> arguments) {
        BMap<BString, Object> headers = ValueCreator.createMapValue(
                TypeCreator.createMapType(PredefinedTypes.TYPE_STRING));
        try {
            walk(schema, arguments, true, false, new HashSet<>(), headers, 0, new int[]{0});
            return headers;
        } catch (IllegalArgumentException exception) {
            return ModuleUtils.createParameterBindingError(exception.getMessage());
        }
    }

    private static Object get(BMap<?, ?> record, String key) {
        return record.get(fromString(key));
    }

    private static void walk(Object node, Object instance, boolean reachable, boolean property,
                             Set<String> names, BMap<BString, Object> headers, int depth, int[] count) {
        if (depth > 64 || ++count[0] > 10000) {
            throw new IllegalArgumentException("Tool schema exceeds traversal limits");
        }
        if (node instanceof BMap<?, ?> schema) {
            Object annotation = get(schema, "x-mcp-header");
            if (schema.containsKey(fromString("x-mcp-header"))) {
                if (!(annotation instanceof BString name) || !TOKEN.matcher(name.getValue()).matches()
                        || !reachable || !property) {
                    throw new IllegalArgumentException("Invalid or unreachable x-mcp-header annotation");
                }
                String key = "mcp-param-" + name.getValue().toLowerCase(Locale.ROOT);
                if (!names.add(key)) {
                    throw new IllegalArgumentException("Duplicate x-mcp-header name: " + name);
                }
                String type = String.valueOf(get(schema, "type"));
                if (!Set.of("string", "integer", "number", "boolean").contains(type)) {
                    throw new IllegalArgumentException(
                            "x-mcp-header requires string, integer, number or boolean type");
                }
                if (instance != null) {
                    boolean valid = switch (type) {
                        case "string" -> instance instanceof BString;
                        case "boolean" -> instance instanceof Boolean;
                        case "integer" -> instance instanceof Long number
                                && number >= -MAX_INTEGER && number <= MAX_INTEGER;
                        case "number" -> instance instanceof Double || instance instanceof BDecimal;
                        default -> false;
                    };
                    if (!valid) {
                        throw new IllegalArgumentException("Invalid argument for mirrored header: " + name);
                    }
                    headers.put(fromString(key), encodeProtocolHeader(fromString(instance.toString())));
                }
            }
            for (var entry : schema.entrySet()) {
                String key = entry.getKey().toString();
                Object child = entry.getValue();
                if ("properties".equals(key) && child instanceof BMap<?, ?> properties) {
                    for (var prop : properties.entrySet()) {
                        Object value = instance instanceof BMap<?, ?> arguments ? arguments.get(prop.getKey()) : null;
                        walk(prop.getValue(), value, reachable, true, names, headers, depth + 1, count);
                    }
                } else if (Set.of("$defs", "definitions", "patternProperties", "dependentSchemas").contains(key)
                        && child instanceof BMap<?, ?> schemas) {
                    for (Object nestedSchema : schemas.values()) {
                        walk(nestedSchema, null, false, false, names, headers, depth + 1, count);
                    }
                } else if (Set.of("items", "prefixItems", "additionalItems", "additionalProperties",
                        "unevaluatedProperties", "unevaluatedItems", "contains", "propertyNames", "allOf", "anyOf",
                        "oneOf", "not", "if", "then", "else", "contentSchema").contains(key)) {
                    walk(child, null, false, false, names, headers, depth + 1, count);
                }
            }
        } else if (node instanceof BArray values) {
            for (long index = 0; index < values.size(); index++) {
                walk(values.get(index), null, false, false, names, headers, depth + 1, count);
            }
        }
    }
}
