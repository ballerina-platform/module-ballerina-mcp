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

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.Operation;
import io.swagger.v3.oas.models.PathItem;
import io.swagger.v3.oas.models.Paths;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.responses.ApiResponse;
import io.swagger.v3.oas.models.responses.ApiResponses;

/**
 * Generates a minimal OpenAPI specification for the MCP Service.
 * <p>
 * The spec carries just enough information (info, a placeholder path, and servers
 * filled in by {@link ServersMapper}) for downstream tooling to derive the host,
 * port, and base path of the MCP endpoint.
 */
public final class McpServiceOpenAPISchema {

    private McpServiceOpenAPISchema() {
    }

    public static OpenAPI generate() {
        Operation postOperation = new Operation()
                .operationId("postMessage")
                .summary("MCP JSON-RPC endpoint")
                .description("Accepts MCP JSON-RPC requests over Streamable HTTP.")
                .responses(new ApiResponses()
                        .addApiResponse("200", new ApiResponse().description("OK")));

        PathItem mcpPath = new PathItem().post(postOperation);

        return new OpenAPI()
                .info(new Info()
                        .title("MCP Service API")
                        .version("1.0.0")
                        .description("OpenAPI specification for the MCP Service endpoint."))
                .paths(new Paths().addPathItem("/", mcpPath));
    }
}
