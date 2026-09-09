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

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.networknt.schema.JsonSchema;
import com.networknt.schema.JsonSchemaFactory;
import com.networknt.schema.SchemaLocation;
import com.networknt.schema.SpecVersion;
import com.networknt.schema.resource.ClasspathSchemaLoader;
import io.ballerina.runtime.api.values.BString;

/** JSON Schema 2020-12 validation with local-only resolution and bounded input trees. */
public final class ProtocolSchema {
    private static final String DIALECT = "https://json-schema.org/draft/2020-12/schema";
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final JsonSchemaFactory FACTORY = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012,
            builder -> builder.schemaLoaders(loaders -> loaders.add(absoluteIri -> {
                String location = absoluteIri.toString();
                if (location.startsWith("classpath:draft/2020-12/")) {
                    return new ClasspathSchemaLoader().getSchema(absoluteIri);
                }
                throw new IllegalArgumentException("External schema references are disabled");
            })));

    private ProtocolSchema() {
    }

    public static Object validateProtocolSchema(BString schemaText, BString instanceText, boolean validateInstance) {
        try {
            if (schemaText.length() > 1048576 || instanceText.length() > 4194304) {
                return ModuleUtils.createParameterBindingError("Schema or instance exceeds validation size limits");
            }
            JsonNode schemaNode = MAPPER.readTree(schemaText.getValue());
            checkBounds(schemaNode, 0, new int[]{0});
            String dialect = schemaNode.path("$schema").asText(DIALECT);
            if (!DIALECT.equals(dialect) && !(DIALECT + "#").equals(dialect)) {
                return ModuleUtils.createParameterBindingError("Unsupported JSON Schema dialect: " + dialect);
            }
            JsonSchema metaSchema = FACTORY.getSchema(SchemaLocation.of(DIALECT));
            if (!metaSchema.validate(schemaNode).isEmpty()) {
                return ModuleUtils.createParameterBindingError("Invalid JSON Schema 2020-12 definition");
            }
            JsonSchema schema = FACTORY.getSchema(schemaNode);
            if (validateInstance) {
                JsonNode instance = MAPPER.readTree(instanceText.getValue());
                checkBounds(instance, 0, new int[]{0});
                if (!schema.validate(instance).isEmpty()) {
                    return ModuleUtils.createParameterBindingError("Value does not match the declared JSON Schema");
                }
            }
            return null;
        } catch (JsonProcessingException | IllegalArgumentException exception) {
            return ModuleUtils.createParameterBindingError("Schema validation failed: " + exception.getMessage());
        } catch (com.networknt.schema.JsonSchemaException exception) {
            return ModuleUtils.createParameterBindingError("Schema reference or validation failed");
        }
    }

    private static void checkBounds(JsonNode node, int depth, int[] count) {
        if (depth > 64 || ++count[0] > 10000) {
            throw new IllegalArgumentException("Schema or instance exceeds validation traversal limits");
        }
        if (node.isContainerNode()) {
            for (JsonNode child : node) {
                checkBounds(child, depth + 1, count);
            }
        }
    }
}
