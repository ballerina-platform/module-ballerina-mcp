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

import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.FunctionTypeSymbol;
import io.ballerina.compiler.api.symbols.ParameterKind;
import io.ballerina.compiler.api.symbols.ParameterSymbol;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.openapi.service.mapper.type.TypeMapper;
import io.ballerina.openapi.service.mapper.type.TypeMapperImpl;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.swagger.v3.core.util.Json;
import io.swagger.v3.core.util.OpenAPISchema2JsonSchema;
import io.swagger.v3.oas.models.media.Schema;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

import static io.ballerina.stdlib.mcp.plugin.RemoteFunctionAnalysisTask.EMPTY_STRING;
import static io.ballerina.stdlib.mcp.plugin.Utils.hasHttpHeaderAnnotation;
import static io.ballerina.stdlib.mcp.plugin.Utils.getMcpArgumentHeaderName;
import static io.ballerina.stdlib.mcp.plugin.Utils.isHttpHeadersType;
import static io.ballerina.stdlib.mcp.plugin.Utils.isHttpRequestType;
import static io.ballerina.stdlib.mcp.plugin.Utils.isMetaParameter;
import static io.ballerina.stdlib.mcp.plugin.Utils.isSessionType;

/**
 * Utility class for generating and manipulating function tool parameter schemas.
 */
public class SchemaUtils {
    private static final String STRING = "string";
    private static final String BYTE = "byte";
    private static final String NUMBER = "number";

    private SchemaUtils() {
    }

    public static String getParameterSchema(FunctionSymbol functionSymbol, SyntaxNodeAnalysisContext context)
            throws SchemaGenerationException {
        FunctionTypeSymbol functionTypeSymbol = functionSymbol.typeDescriptor();
        List<ParameterSymbol> parameterSymbolList =
                functionTypeSymbol.params().orElse(Collections.emptyList());

        Map<String, String> individualParamSchema = new HashMap<>();
        List<String> requiredParams = new ArrayList<>();
        TypeMapper typeMapper = new TypeMapperImpl(context);
        for (ParameterSymbol parameterSymbol : parameterSymbolList) {
            try {
                // Session, Meta, http:Headers, http:Request, and @http:Header parameters are injected
                // by the runtime and are not part of the tool input schema
                if (isSessionType(parameterSymbol.typeDescriptor())
                        || isMetaParameter(parameterSymbol.typeDescriptor())
                        || isHttpHeadersType(parameterSymbol.typeDescriptor())
                        || isHttpRequestType(parameterSymbol.typeDescriptor())
                        || hasHttpHeaderAnnotation(parameterSymbol)) {
                    continue;
                }

                String parameterName = parameterSymbol.getName().orElseThrow();
                if (parameterSymbol.paramKind() != ParameterKind.DEFAULTABLE) {
                    requiredParams.add(parameterName);
                }
                @SuppressWarnings("rawtypes")
                Schema schema = typeMapper.getSchema(parameterSymbol.typeDescriptor());
                String parameterDescription = Utils.getParameterDescription(functionSymbol, parameterName);
                schema.setDescription(parameterDescription);
                String jsonSchema = SchemaUtils.getJsonSchema(schema);
                Optional<String> headerName = getMcpArgumentHeaderName(parameterSymbol);
                if (headerName.isPresent()) {
                    jsonSchema = addMcpHeader(jsonSchema, headerName.get());
                }
                individualParamSchema.put(parameterName, jsonSchema);
            } catch (RuntimeException e) {
                throw new SchemaGenerationException(e);
            }
        }
        String properties = individualParamSchema.entrySet().stream()
                .map(entry -> String.format("\"%s\": %s", entry.getKey(), entry.getValue()))
                .collect(Collectors.joining(", ", "{", "}"));

        String required = requiredParams.stream()
                .map(paramName -> String.format("\"%s\"", paramName))
                .collect(Collectors.joining(", ", "[", "]"));
        return String.format("{\"type\":\"object\",\"required\":%s,\"properties\":%s}",
                required, properties);
    }

    private static String addMcpHeader(String jsonSchema, String headerName) {
        return jsonSchema.substring(0, jsonSchema.length() - 1)
                + ",\"x-mcp-header\":\"" + headerName + "\"}";
    }

    public static String getReturnSchema(FunctionSymbol functionSymbol, SyntaxNodeAnalysisContext context)
            throws SchemaGenerationException {
        TypeSymbol returnType = functionSymbol.typeDescriptor().returnTypeDescriptor().orElse(null);
        if (returnType == null) {
            return null;
        }
        TypeMapper typeMapper = new TypeMapperImpl(context);
        List<String> schemas = getSuccessfulReturnSchemas(returnType, typeMapper);
        if (schemas.isEmpty()) {
            return null;
        }
        if (schemas.size() == 1) {
            return schemas.get(0);
        }
        return schemas.stream().collect(Collectors.joining(",", "{\"anyOf\":[", "]}"));
    }

    private static List<String> getSuccessfulReturnSchemas(TypeSymbol returnType, TypeMapper typeMapper)
            throws SchemaGenerationException {
        if (returnType.typeKind() == TypeDescKind.TYPE_REFERENCE) {
            return getSuccessfulReturnSchemas(((TypeReferenceTypeSymbol) returnType).typeDescriptor(), typeMapper);
        }
        if (returnType.typeKind() == TypeDescKind.UNION) {
            List<String> schemas = new ArrayList<>();
            for (TypeSymbol member : ((UnionTypeSymbol) returnType).memberTypeDescriptors()) {
                schemas.addAll(getSuccessfulReturnSchemas(member, typeMapper));
            }
            return schemas;
        }
        if (returnType.typeKind() == TypeDescKind.ERROR || returnType.typeKind() == TypeDescKind.NEVER) {
            return Collections.emptyList();
        }
        if (returnType.typeKind() == TypeDescKind.NIL) {
            return List.of("{\"type\":\"null\"}");
        }
        try {
            @SuppressWarnings("rawtypes")
            Schema schema = typeMapper.getSchema(returnType);
            return List.of(getJsonSchema(schema));
        } catch (RuntimeException e) {
            throw new SchemaGenerationException(e);
        }
    }

    @SuppressWarnings("rawtypes")
    private static String getJsonSchema(Schema schema) {
        modifySchema(schema);
        OpenAPISchema2JsonSchema openAPISchema2JsonSchema = new OpenAPISchema2JsonSchema();
        openAPISchema2JsonSchema.process(schema);
        String newLineRegex = "\\R";
        String jsonCompressionRegex = "\\s*([{}\\[\\]:,])\\s*";
        return Json.pretty(schema.getJsonSchema())
                .replaceAll(newLineRegex, EMPTY_STRING)
                .replaceAll(jsonCompressionRegex, "$1");
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    private static void modifySchema(Schema schema) {
        if (schema == null) {
            return;
        }
        modifySchema(schema.getItems());
        modifySchema(schema.getNot());

        Map<String, Schema> properties = schema.getProperties();
        if (properties != null) {
            properties.values().forEach(SchemaUtils::modifySchema);
        }

        List<Schema> allOf = schema.getAllOf();
        if (allOf != null) {
            schema.setType(null);
            allOf.forEach(SchemaUtils::modifySchema);
        }

        List<Schema> anyOf = schema.getAnyOf();
        if (anyOf != null) {
            schema.setType(null);
            anyOf.forEach(SchemaUtils::modifySchema);
        }

        List<Schema> oneOf = schema.getOneOf();
        if (oneOf != null) {
            schema.setType(null);
            oneOf.forEach(SchemaUtils::modifySchema);
        }

        // Override default ballerina byte to json schema mapping
        if (BYTE.equals(schema.getFormat()) && STRING.equals(schema.getType())) {
            schema.setFormat(null);
            schema.setType(NUMBER);
        }
        removeUnwantedFields(schema);
    }

    @SuppressWarnings({"rawtypes", "unchecked"})
    private static void removeUnwantedFields(Schema schema) {
        schema.setSpecVersion(null);
        schema.setSpecVersion(null);
        schema.setContains(null);
        schema.set$id(null);
        schema.set$schema(null);
        schema.set$anchor(null);
        schema.setExclusiveMaximumValue(null);
        schema.setExclusiveMinimumValue(null);
        schema.setDiscriminator(null);
        schema.setTitle(null);
        schema.setMaximum(null);
        schema.setExclusiveMaximum(null);
        schema.setMinimum(null);
        schema.setExclusiveMinimum(null);
        schema.setMaxLength(null);
        schema.setMinLength(null);
        schema.setMaxItems(null);
        schema.setMinItems(null);
        schema.setMaxProperties(null);
        schema.setMinProperties(null);
        schema.setAdditionalProperties(null);
        schema.setAdditionalProperties(null);
        schema.set$ref(null);
        schema.set$ref(null);
        schema.setReadOnly(null);
        schema.setWriteOnly(null);
        schema.setExample(null);
        schema.setExample(null);
        schema.setExternalDocs(null);
        schema.setDeprecated(null);
        schema.setPrefixItems(null);
        schema.setContentEncoding(null);
        schema.setContentMediaType(null);
        schema.setContentSchema(null);
        schema.setPropertyNames(null);
        schema.setUnevaluatedProperties(null);
        schema.setMaxContains(null);
        schema.setMinContains(null);
        schema.setAdditionalItems(null);
        schema.setUnevaluatedItems(null);
        schema.setIf(null);
        schema.setElse(null);
        schema.setThen(null);
        schema.setDependentSchemas(null);
        schema.set$comment(null);
        schema.setExamples(null);
        schema.setExtensions(null);
        schema.setConst(null);
    }
}
