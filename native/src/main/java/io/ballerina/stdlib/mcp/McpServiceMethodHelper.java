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

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.ArrayType;
import io.ballerina.runtime.api.types.Parameter;
import io.ballerina.runtime.api.types.RecordType;
import io.ballerina.runtime.api.types.ReferenceType;
import io.ballerina.runtime.api.types.RemoteMethodType;
import io.ballerina.runtime.api.types.ServiceType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.types.UnionType;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

import java.util.List;
import java.util.Optional;

import static io.ballerina.runtime.api.utils.StringUtils.fromString;

/**
 * Utility class for invoking MCP service remote methods from Java via Ballerina interop.
 * <p>
 * Not instantiable.
 */
public final class McpServiceMethodHelper {

    private static final String TOOLS_FIELD_NAME = "tools";
    private static final String NAME_FIELD_NAME = "name";
    private static final String DESCRIPTION_FIELD_NAME = "description";
    private static final String SCHEMA_FIELD_NAME = "schema";
    private static final String INPUT_SCHEMA_FIELD_NAME = "inputSchema";
    private static final String ARGUMENTS_FIELD_NAME = "arguments";
    private static final String CONTENT_FIELD_NAME = "content";
    private static final String TYPE_FIELD_NAME = "type";
    private static final String TEXT_FIELD_NAME = "text";

    private static final String ANNOTATION_MCP_TOOL = "McpTool";
    private static final String TYPE_TEXT_CONTENT = "TextContent";
    private static final String TEXT_VALUE_NAME = "text";

    private McpServiceMethodHelper() {}

    /**
     * Invoke the 'onListTools' remote method on the given MCP service object.
     *
     * @param env        The Ballerina runtime environment.
     * @param mcpService The MCP service object.
     * @return           Result of remote method invocation.
     */
    public static Object invokeOnListTools(Environment env, BObject mcpService) {
        return env.getRuntime().callMethod(mcpService, "onListTools", null);
    }

    /**
     * Invoke the 'onCallTool' remote method on the given MCP service object with parameters.
     *
     * @param env        The Ballerina runtime environment.
     * @param mcpService The MCP service object.
     * @param params     Parameters for the tool invocation.
     * @return           Result of remote method invocation.
     */
    public static Object invokeOnCallTool(Environment env, BObject mcpService, BMap<?, ?> params) {
        return env.getRuntime().callMethod(mcpService, "onCallTool", null, params);
    }

    /**
     * Lists tool metadata for remote functions in the given MCP service.
     *
     * @param mcpService The MCP service object.
     * @param typed      The type descriptor for the result.
     * @return           Record containing the list of tools.
     */
    public static Object listToolsForRemoteFunctions(BObject mcpService, BTypedesc typed) {
        RecordType resultRecordType = (RecordType) typed.getDescribingType();
        BMap<BString, Object> result = ValueCreator.createRecordValue(resultRecordType);

        ArrayType toolsArrayType = (ArrayType) resultRecordType.getFields().get(TOOLS_FIELD_NAME).getFieldType();
        BArray tools = ValueCreator.createArrayValue(toolsArrayType);

        for (RemoteMethodType remoteMethod : getRemoteMethods(mcpService)) {
            remoteMethod.getAnnotations().entrySet().stream()
                    .filter(e -> e.getKey().getValue().contains(ANNOTATION_MCP_TOOL))
                    .findFirst()
                    .ifPresent(annotation -> tools.append(
                            createToolRecord(toolsArrayType, remoteMethod, (BMap<?, ?>) annotation.getValue())
                    ));
        }
        result.put(fromString(TOOLS_FIELD_NAME), tools);
        return result;
    }

    /**
     * Invokes a remote function (tool) by name with arguments.
     *
     * @param env        The Ballerina runtime environment.
     * @param mcpService The MCP service object.
     * @param params     The parameters for the tool invocation.
     * @param typed      The type descriptor for the result.
     * @return           Record containing the invocation result or an error.
     */
    public static Object callToolForRemoteFunctions(Environment env, BObject mcpService, BMap<?, ?> params,
                                                    BTypedesc typed) {
        BString toolName = (BString) params.get(fromString(NAME_FIELD_NAME));

        Optional<RemoteMethodType> method = getRemoteMethods(mcpService).stream()
                .filter(rmt -> rmt.getName().equals(toolName.getValue()))
                .findFirst();

        if (method.isEmpty()) {
            return ModuleUtils
                    .createError("RemoteMethodType with name '" + toolName.getValue() + "' not found");
        }

        Object[] args = buildArgsForMethod(method.get(), (BMap<?, ?>) params.get(fromString(ARGUMENTS_FIELD_NAME)));
        Object result = env.getRuntime().callMethod(mcpService, toolName.getValue(), null, args);

        return createCallToolResult(typed, result);
    }

    private static List<RemoteMethodType> getRemoteMethods(BObject mcpService) {
        ServiceType serviceType = (ServiceType) mcpService.getOriginalType();
        return List.of(serviceType.getRemoteMethods());
    }

    private static BMap<BString, Object> createToolRecord(ArrayType toolsArrayType, RemoteMethodType remoteMethod,
                                                          BMap<?, ?> annotationValue) {
        RecordType toolRecordType = (RecordType) ((ReferenceType) toolsArrayType.getElementType()).getReferredType();
        BMap<BString, Object> tool = ValueCreator.createRecordValue(toolRecordType);

        tool.put(fromString(NAME_FIELD_NAME), fromString(remoteMethod.getName()));
        tool.put(fromString(DESCRIPTION_FIELD_NAME), annotationValue.get(fromString(DESCRIPTION_FIELD_NAME)));
        tool.put(fromString(INPUT_SCHEMA_FIELD_NAME), annotationValue.get(fromString(SCHEMA_FIELD_NAME)));
        return tool;
    }

    private static Object[] buildArgsForMethod(RemoteMethodType method, BMap<?, ?> arguments) {
        List<Parameter> params = List.of(method.getParameters());
        Object[] args = new Object[params.size()];
        for (int i = 0; i < params.size(); i++) {
            String paramName = params.get(i).name;
            args[i] = arguments == null ? null : arguments.get(fromString(paramName));
        }
        return args;
    }

    private static Object createCallToolResult(BTypedesc typed, Object result) {
        RecordType resultRecordType = (RecordType) typed.getDescribingType();
        BMap<BString, Object> callToolResult = ValueCreator.createRecordValue(resultRecordType);

        ArrayType contentArrayType = (ArrayType) resultRecordType.getFields().get(CONTENT_FIELD_NAME).getFieldType();
        BArray contentArray = ValueCreator.createArrayValue(contentArrayType);

        UnionType contentUnionType = (UnionType) contentArrayType.getElementType();
        Optional<Type> textContentTypeOpt = contentUnionType.getMemberTypes().stream()
                .filter(type -> TYPE_TEXT_CONTENT.equals(type.getName()))
                .findFirst();
        if (textContentTypeOpt.isEmpty()) {
            return ModuleUtils
                    .createError("No member type named 'TextContent' found in content union type.");
        }
        RecordType textContentRecordType = (RecordType) ((ReferenceType) textContentTypeOpt.get()).getReferredType();
        BMap<BString, Object> textContent = ValueCreator.createRecordValue(textContentRecordType);
        textContent.put(fromString(TYPE_FIELD_NAME), fromString(TEXT_VALUE_NAME));
        textContent.put(fromString(TEXT_FIELD_NAME), fromString(result == null ? "" : result.toString()));
        contentArray.append(textContent);

        callToolResult.put(fromString(CONTENT_FIELD_NAME), contentArray);
        return callToolResult;
    }
}
