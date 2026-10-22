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

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.ballerina.compiler.api.symbols.ArrayTypeSymbol;
import io.ballerina.compiler.api.symbols.EnumSymbol;
import io.ballerina.compiler.api.symbols.FunctionSymbol;
import io.ballerina.compiler.api.symbols.FunctionTypeSymbol;
import io.ballerina.compiler.api.symbols.ParameterKind;
import io.ballerina.compiler.api.symbols.ParameterSymbol;
import io.ballerina.compiler.api.symbols.RecordFieldSymbol;
import io.ballerina.compiler.api.symbols.RecordTypeSymbol;
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
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.StringJoiner;
import java.util.stream.Collectors;

import static io.ballerina.stdlib.mcp.plugin.v2.RemoteFunctionAnalysisTask.EMPTY_STRING;
import static io.ballerina.stdlib.mcp.plugin.endpointyaml.generator.EndpointYamlGenerator.unescapeIdentifier;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.hasHttpHeaderAnnotation;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.getMcpArgumentHeaderName;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.isAuthContextType;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.isContextType;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.isHttpHeadersType;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.isHttpRequestType;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.isInputRequiredResultType;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.isMetaParameter;
import static io.ballerina.stdlib.mcp.plugin.v2.Utils.isSessionType;

/**
 * Utility class for generating and manipulating function tool parameter schemas.
 */
public class SchemaUtils {
    private static final String NIL_SCHEMA = "{\"type\":\"null\"}";
    private static final String STRING = "string";
    private static final String BYTE = "byte";
    private static final String NUMBER = "number";
    private static final String INTEGER = "integer";
    private static final String BOOLEAN = "boolean";
    private static final String ARRAY = "array";
    private static final String OBJECT = "object";
    private static final String TYPE = "type";
    private static final String ENUM = "enum";
    private static final String NULLABLE = "nullable";
    private static final String ITEMS = "items";
    private static final String DESCRIPTION = "description";
    private static final String PROPERTIES = "properties";
    private static final String REQUIRED = "required";

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
                // Session, Meta, AuthContext, Context, http:Headers, http:Request, and @http:Header parameters are
                // injected by the runtime and are not part of the tool input schema
                if (isSessionType(parameterSymbol.typeDescriptor())
                        || isMetaParameter(parameterSymbol.typeDescriptor())
                        || isAuthContextType(parameterSymbol.typeDescriptor())
                        || isContextType(parameterSymbol.typeDescriptor())
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
        // A tool that can only return nil has no output to describe, so it stays unstructured.
        if (schemas.stream().allMatch(NIL_SCHEMA::equals)) {
            return null;
        }
        if (schemas.size() == 1) {
            return schemas.get(0);
        }
        return schemas.stream().collect(Collectors.joining(",", "{\"anyOf\":[", "]}"));
    }

    private static List<String> getSuccessfulReturnSchemas(TypeSymbol returnType, TypeMapper typeMapper)
            throws SchemaGenerationException {
        // An input-required result is an interim answer, not tool output.
        if (isInputRequiredResultType(returnType)) {
            return Collections.emptyList();
        }
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
            return List.of(NIL_SCHEMA);
        }
        try {
            @SuppressWarnings("rawtypes")
            Schema schema = typeMapper.getSchema(returnType);
            return List.of(getJsonSchema(schema));
        } catch (RuntimeException e) {
            throw new SchemaGenerationException(e);
        }
    }

    /**
     * Generates the form schema of a record type, as Ballerina source for an {@code mcp:FormSchema} value.
     *
     * @param recordType the record type whose fields become form fields
     * @param context    the analysis context
     * @return the form schema as a mapping constructor
     * @throws UnsupportedFormFieldException if a field has a type a form schema cannot express
     */
    public static String getFormSchema(RecordTypeSymbol recordType, SyntaxNodeAnalysisContext context)
            throws UnsupportedFormFieldException {
        TypeMapper typeMapper = new TypeMapperImpl(context);
        ObjectNode properties = Json.mapper().createObjectNode();
        ArrayNode required = Json.mapper().createArrayNode();
        for (Map.Entry<String, RecordFieldSymbol> entry : recordType.fieldDescriptors().entrySet()) {
            String fieldName = unescapeIdentifier(entry.getKey());
            RecordFieldSymbol field = entry.getValue();
            ObjectNode fieldSchema = getFormField(typeMapper, field.typeDescriptor())
                    .orElseThrow(() -> new UnsupportedFormFieldException(fieldName));
            orderEnumOptions(fieldSchema, field.typeDescriptor());
            String description = Utils.getDescription(field);
            if (description != null) {
                fieldSchema.put(DESCRIPTION, description);
            }
            properties.set(fieldName, fieldSchema);
            if (!field.isOptional() && !field.hasDefaultValue()) {
                required.add(fieldName);
            }
        }
        ObjectNode formSchema = Json.mapper().createObjectNode().put(TYPE, OBJECT);
        formSchema.set(PROPERTIES, properties);
        if (!required.isEmpty()) {
            formSchema.set(REQUIRED, required);
        }
        return toBallerinaSource(formSchema);
    }

    private static Optional<ObjectNode> getFormField(TypeMapper typeMapper, TypeSymbol fieldType) {
        try {
            return Optional.ofNullable(toFormField(Json.mapper().readTree(
                    getJsonSchema(typeMapper.getSchema(fieldType)))));
        } catch (RuntimeException | JsonProcessingException e) {
            return Optional.empty();
        }
    }

    // Keeps the parts of a generated field schema that the form schema subset can express; null if none fit.
    private static ObjectNode toFormField(JsonNode schema) {
        // A form field cannot be nil; an optional field is how a form leaves a value out.
        if (schema.path(NULLABLE).asBoolean(false)) {
            return null;
        }
        String type = schema.path(TYPE).isTextual() ? schema.get(TYPE).asText() : null;
        JsonNode options = schema.get(ENUM);
        ObjectNode formField = Json.mapper().createObjectNode().put(TYPE, type);
        if (STRING.equals(type)) {
            if (options == null) {
                return formField;
            }
            return isStringOptions(options) ? formField.set(ENUM, options) : null;
        }
        if (options != null) {
            return null;
        }
        if (INTEGER.equals(type) || NUMBER.equals(type) || BOOLEAN.equals(type)) {
            return formField;
        }
        if (ARRAY.equals(type)) {
            JsonNode items = schema.path(ITEMS);
            if (!STRING.equals(items.path(TYPE).asText()) || !isStringOptions(items.get(ENUM))) {
                return null;
            }
            formField.putObject(ITEMS).put(TYPE, STRING).set(ENUM, items.get(ENUM));
            return formField;
        }
        return null;
    }

    // Enum members are not listed in declaration order, so the options are put back in source order.
    private static void orderEnumOptions(ObjectNode formField, TypeSymbol fieldType) {
        TypeSymbol optionType = fieldType;
        if (Utils.getRawType(fieldType) instanceof ArrayTypeSymbol arrayType) {
            optionType = arrayType.memberTypeDescriptor();
        }
        if (!(optionType instanceof TypeReferenceTypeSymbol typeReference)
                || !(typeReference.definition() instanceof EnumSymbol enumSymbol)) {
            return;
        }
        ArrayNode options = Json.mapper().createArrayNode();
        enumSymbol.members().stream()
                .sorted(Comparator.comparingInt(member -> member.getLocation()
                        .map(location -> location.textRange().startOffset()).orElse(0)))
                .forEach(member -> options.add(member.constValue().toString()));
        ObjectNode optionHolder = formField.has(ITEMS) ? (ObjectNode) formField.get(ITEMS) : formField;
        optionHolder.set(ENUM, options);
    }

    private static boolean isStringOptions(JsonNode options) {
        if (options == null || !options.isArray() || options.isEmpty()) {
            return false;
        }
        for (JsonNode option : options) {
            if (!option.isTextual()) {
                return false;
            }
        }
        return true;
    }

    // JSON escapes are not all valid Ballerina string escapes, so the source is written out directly.
    private static String toBallerinaSource(JsonNode node) {
        if (node.isObject()) {
            StringJoiner fields = new StringJoiner(",", "{", "}");
            node.fields().forEachRemaining(field ->
                    fields.add(toBallerinaString(field.getKey()) + ":" + toBallerinaSource(field.getValue())));
            return fields.toString();
        }
        if (node.isArray()) {
            StringJoiner members = new StringJoiner(",", "[", "]");
            node.forEach(member -> members.add(toBallerinaSource(member)));
            return members.toString();
        }
        return node.isTextual() ? toBallerinaString(node.asText()) : node.toString();
    }

    private static String toBallerinaString(String value) {
        StringBuilder literal = new StringBuilder("\"");
        value.codePoints().forEach(codePoint -> {
            switch (codePoint) {
                case '"' -> literal.append("\\\"");
                case '\\' -> literal.append("\\\\");
                case '\n' -> literal.append("\\n");
                case '\r' -> literal.append("\\r");
                case '\t' -> literal.append("\\t");
                default -> {
                    if (Character.isISOControl(codePoint)) {
                        literal.append(String.format("\\u{%X}", codePoint));
                    } else {
                        literal.appendCodePoint(codePoint);
                    }
                }
            }
        });
        return literal.append('"').toString();
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
