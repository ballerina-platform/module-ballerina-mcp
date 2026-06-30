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

import com.fasterxml.jackson.annotation.JsonAnyGetter;
import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Holds the extracted metadata of an MCP service endpoint: port, base path, and type.
 *
 * <p>The model is lenient about unknown fields so that the shared {@code endpoints.yaml} can carry entries written by
 * other modules (for example HTTP's {@code schemaPath}). Such fields are captured and serialized back verbatim, so
 * merging never drops another module's data.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonPropertyOrder({"port", "basePath", "type"})
public class Endpoint {

    private int port;
    private String basePath;
    private String type;
    private final Map<String, Object> additionalProperties = new LinkedHashMap<>();

    public Endpoint() {
    }

    public Endpoint(int port, String basePath, String type) {
        this.port = port;
        this.basePath = basePath;
        this.type = type;
    }

    public int getPort() {
        return port;
    }

    public void setPort(int port) {
        this.port = port;
    }

    public String getBasePath() {
        return basePath;
    }

    public void setBasePath(String basePath) {
        this.basePath = basePath;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    /**
     * Returns fields that are not modeled explicitly (for example another module's {@code schemaPath}), so they are
     * preserved on serialization.
     *
     * @return the unmodeled fields keyed by name
     */
    @JsonAnyGetter
    public Map<String, Object> getAdditionalProperties() {
        return new LinkedHashMap<>(additionalProperties);
    }

    /**
     * Captures a field that is not modeled explicitly so it round-trips unchanged.
     *
     * @param name  the field name
     * @param value the field value
     */
    @JsonAnySetter
    public void setAdditionalProperty(String name, Object value) {
        this.additionalProperties.put(name, value);
    }
}
