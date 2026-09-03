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
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.flags.SymbolFlags;
import io.ballerina.runtime.api.types.ArrayType;
import io.ballerina.runtime.api.types.Field;
import io.ballerina.runtime.api.types.Parameter;
import io.ballerina.runtime.api.types.RecordType;
import io.ballerina.runtime.api.types.RemoteMethodType;
import io.ballerina.runtime.api.types.ServiceType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.types.TypeTags;
import io.ballerina.runtime.api.types.UnionType;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.utils.ValueUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
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

    private static final String ANNOTATION_MCP_TOOL = "Tool";
    private static final String TYPE_TEXT_CONTENT = "TextContent";
    private static final String TEXT_VALUE_NAME = "text";
    private static final String MCP_SERVICE_FIELD = "mcpService";

    // MCP Session and Meta-related constants
    private static final String MCP_PACKAGE_NAME = "mcp";
    private static final String SESSION_TYPE_NAME = "Session";
    private static final String META_TYPE_NAME = "Meta";
    private static final String META_FIELD_NAME = "_meta";
    private static final String CALL_TOOL_PARAMS_TYPE_NAME = "CallToolParams";

    // Advanced service remote method names
    private static final String ON_CALL_TOOL_METHOD = "onCallTool";
    private static final String ON_LIST_TOOLS_METHOD = "onListTools";

    // HTTP Headers-related constants
    private static final String HTTP_PACKAGE_NAME = "http";
    private static final String HEADERS_TYPE_NAME = "Headers";
    private static final String REQUEST_TYPE_NAME = "Request";

    // @http:Header annotation-related constants
    private static final String PARAM_ANNOT_PREFIX = "$param$.";
    private static final String FIELD_ANNOT_PREFIX = "$field$.";
    private static final String HEADER_ANNOTATION_NAME = "Header";
    private static final String ANNOTATION_NAME_FIELD = "name";
    private static final String BALLERINA_ORG = "ballerina";
    private static final String COLON = ":";
    private static final String ORG_SEPARATOR = "/";

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
    public static Object invokeOnCallTool(Environment env, BObject mcpService, BMap<?, ?> params, Object session) {
        return env.getRuntime().callMethod(mcpService, "onCallTool", null, params, session);
    }

    /**
     * Invoke the 'onCallTool' remote method of a Streamable HTTP advanced service. The method's
     * declared parameters are inspected and bound flexibly (CallToolParams, Session, http:Headers,
     * http:Request, and '@http:Header' parameters), mirroring how basic service tools are bound.
     *
     * @param env                    The Ballerina runtime environment.
     * @param mcpService             The MCP service object.
     * @param params                 The CallToolParams for the tool invocation.
     * @param session                The session object (or null).
     * @param headers                The HTTP headers of the request.
     * @param request                The HTTP request.
     * @param headerValues           Header values keyed by lower-cased name, for '@http:Header' binding.
     * @param treatNilableAsOptional Whether a missing header binds a nilable '@http:Header' param to nil.
     * @return                       Result of remote method invocation, or a binding error.
     */
    public static Object invokeAdvancedOnCallTool(Environment env, BObject mcpService, BMap<?, ?> params,
                                                  Object session, BObject headers, BObject request,
                                                  BMap<?, ?> headerValues, boolean treatNilableAsOptional) {
        Optional<RemoteMethodType> method = getRemoteMethod(mcpService, ON_CALL_TOOL_METHOD);
        if (method.isEmpty()) {
            return ModuleUtils.createError("Remote method '" + ON_CALL_TOOL_METHOD + "' not found");
        }
        Object argsOrError = buildAdvancedArgs(method.get(), params, session, headers, request, headerValues,
                treatNilableAsOptional);
        if (argsOrError instanceof BError) {
            return argsOrError;
        }
        return env.getRuntime().callMethod(mcpService, ON_CALL_TOOL_METHOD, null, (Object[]) argsOrError);
    }

    /**
     * Invoke the 'onListTools' remote method of a Streamable HTTP advanced service. The method's
     * declared parameters are inspected and bound flexibly (http:Headers, http:Request, and
     * '@http:Header' parameters).
     *
     * @param env                    The Ballerina runtime environment.
     * @param mcpService             The MCP service object.
     * @param headers                The HTTP headers of the request.
     * @param request                The HTTP request.
     * @param headerValues           Header values keyed by lower-cased name, for '@http:Header' binding.
     * @param treatNilableAsOptional Whether a missing header binds a nilable '@http:Header' param to nil.
     * @return                       Result of remote method invocation, or a binding error.
     */
    public static Object invokeAdvancedOnListTools(Environment env, BObject mcpService, BObject headers,
                                                   BObject request, BMap<?, ?> headerValues,
                                                   boolean treatNilableAsOptional) {
        Optional<RemoteMethodType> method = getRemoteMethod(mcpService, ON_LIST_TOOLS_METHOD);
        if (method.isEmpty()) {
            return ModuleUtils.createError("Remote method '" + ON_LIST_TOOLS_METHOD + "' not found");
        }
        Object argsOrError = buildAdvancedArgs(method.get(), null, null, headers, request, headerValues,
                treatNilableAsOptional);
        if (argsOrError instanceof BError) {
            return argsOrError;
        }
        return env.getRuntime().callMethod(mcpService, ON_LIST_TOOLS_METHOD, null, (Object[]) argsOrError);
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
                                                    Object session, BObject headers, BObject request,
                                                    BMap<?, ?> headerValues, boolean treatNilableAsOptional,
                                                    BTypedesc typed) {
        BString toolName = (BString) params.get(fromString(NAME_FIELD_NAME));

        Optional<RemoteMethodType> method = getRemoteMethods(mcpService).stream()
                .filter(rmt -> rmt.getName().equals(toolName.getValue()))
                .findFirst();

        if (method.isEmpty()) {
            return ModuleUtils
                    .createError("RemoteMethodType with name '" + toolName.getValue() + "' not found");
        }

        // Extract metadata from params
        Object meta = params.get(fromString(META_FIELD_NAME));

        Object argsOrError =
                buildArgsForMethod(method.get(), (BMap<?, ?>) params.get(fromString(ARGUMENTS_FIELD_NAME)), session,
                        meta, headers, request, headerValues, treatNilableAsOptional);

        if (argsOrError instanceof BError) {
            return argsOrError;
        }

        Object[] args = (Object[]) argsOrError;
        Object result;
        try {
            result = env.getRuntime().callMethod(mcpService, toolName.getValue(), null, args);
        } catch (BError panic) {
            result = panic;
        }

        return createCallToolResult(typed, result);
    }

    /**
     * Adds an MCP service to the dispatcher service by storing it in a private field.
     *
     * @param dispatcherService The dispatcher service object.
     * @param mcpService        The MCP service object to store.
     * @return                  null if successful, error otherwise.
     */
    public static Object addMcpServiceToDispatcher(BObject dispatcherService, BObject mcpService) {
        try {
            dispatcherService.addNativeData(MCP_SERVICE_FIELD, mcpService);
            return null;
        } catch (Exception e) {
            return ModuleUtils.createError("Failed to add MCP service to dispatcher: " + e.getMessage());
        }
    }

    /**
     * Retrieves the MCP service from the dispatcher service.
     *
     * @param dispatcherService The dispatcher service object.
     * @return                  The MCP service object or an error if not found.
     */
    public static Object getMcpServiceFromDispatcher(BObject dispatcherService) {
        try {
            Object mcpService = dispatcherService.getNativeData(MCP_SERVICE_FIELD);
            if (mcpService == null) {
                return ModuleUtils.createError("MCP service not found in dispatcher");
            }
            return mcpService;
        } catch (Exception e) {
            return ModuleUtils.createError("Failed to get MCP service from dispatcher: " + e.getMessage());
        }
    }

    private static List<RemoteMethodType> getRemoteMethods(BObject mcpService) {
        ServiceType serviceType = (ServiceType) mcpService.getOriginalType();
        return List.of(serviceType.getRemoteMethods());
    }

    private static Optional<RemoteMethodType> getRemoteMethod(BObject mcpService, String name) {
        return getRemoteMethods(mcpService).stream()
                .filter(rmt -> rmt.getName().equals(name))
                .findFirst();
    }

    /**
     * Builds the argument array for an advanced service remote method ('onCallTool'/'onListTools') by
     * inspecting its declared parameters and injecting the matching value. 'callToolParams' is null
     * for 'onListTools' (which has no CallToolParams parameter).
     */
    private static Object buildAdvancedArgs(RemoteMethodType method, Object callToolParams, Object session,
                                            Object headers, Object request, BMap<?, ?> headerValues,
                                            boolean treatNilableAsOptional) {
        List<Parameter> params = List.of(method.getParameters());
        Object[] args = new Object[params.size()];
        for (int i = 0; i < params.size(); i++) {
            Parameter param = params.get(i);
            BMap<?, ?> headerAnnotation = getHeaderAnnotation(method, param.name);

            if (isCallToolParamsParameter(param)) {
                args[i] = callToolParams;
            } else if (isSessionParameter(param)) {
                args[i] = session;
            } else if (isHeadersParameter(param)) {
                args[i] = headers;
            } else if (isRequestParameter(param)) {
                args[i] = request;
            } else if (headerAnnotation != null) {
                Object headerValueOrError = bindHeaderParam(param.type, param.name, headerAnnotation, headerValues,
                        treatNilableAsOptional);
                if (headerValueOrError instanceof BError) {
                    return headerValueOrError;
                }
                args[i] = headerValueOrError;
            } else {
                // The compiler plugin rejects any other parameter shape; guard defensively.
                return ModuleUtils.createError("Unsupported parameter '" + param.name + "' in method '"
                        + method.getName() + "'");
            }
        }
        return args;
    }

    private static boolean isCallToolParamsParameter(Parameter param) {
        return isParameterOfType(param, MCP_PACKAGE_NAME, CALL_TOOL_PARAMS_TYPE_NAME);
    }

    private static BMap<BString, Object> createToolRecord(ArrayType toolsArrayType, RemoteMethodType remoteMethod,
                                                          BMap<?, ?> annotationValue) {
        RecordType toolRecordType = (RecordType) TypeUtils.getImpliedType(toolsArrayType.getElementType());
        BMap<BString, Object> tool = ValueCreator.createRecordValue(toolRecordType);

        tool.put(fromString(NAME_FIELD_NAME), fromString(remoteMethod.getName()));
        tool.put(fromString(DESCRIPTION_FIELD_NAME), annotationValue.get(fromString(DESCRIPTION_FIELD_NAME)));
        tool.put(fromString(INPUT_SCHEMA_FIELD_NAME), annotationValue.get(fromString(SCHEMA_FIELD_NAME)));
        return tool;
    }

    private static Object buildArgsForMethod(RemoteMethodType method, BMap<?, ?> arguments, Object session,
                                             Object meta, Object headers, Object request, BMap<?, ?> headerValues,
                                             boolean treatNilableAsOptional) {
        List<Parameter> params = List.of(method.getParameters());
        Object[] args = new Object[params.size()];
        for (int i = 0; i < params.size(); i++) {
            Parameter param = params.get(i);
            BMap<?, ?> headerAnnotation = getHeaderAnnotation(method, param.name);

            if (isSessionParameter(param)) {
                args[i] = session;
            } else if (isMetaParameter(param)) {
                args[i] = meta;
            } else if (isHeadersParameter(param)) {
                args[i] = headers;
            } else if (isRequestParameter(param)) {
                args[i] = request;
            } else if (headerAnnotation != null) {
                Object headerValueOrError = bindHeaderParam(param.type, param.name, headerAnnotation, headerValues,
                        treatNilableAsOptional);
                if (headerValueOrError instanceof BError) {
                    return headerValueOrError;
                }
                args[i] = headerValueOrError;
            } else {
                String paramName = param.name;
                Object argValue = arguments == null ? null : arguments.get(fromString(paramName));

                // Check if the parameter is required (non-optional) but the value is null
                if (argValue == null && !isOptionalParameter(param)) {
                    return ModuleUtils.createParameterBindingError(
                            "missing required argument '" + paramName + "'");
                }

                Object convertedOrError = convertArgument(argValue, param.type, paramName);
                if (convertedOrError instanceof BError) {
                    return convertedOrError;
                }
                args[i] = convertedOrError;
            }
        }
        return args;
    }

    private static Object convertArgument(Object argValue, Type targetType, String paramName) {
        if (argValue == null) {
            return null;
        }
        try {
            return ValueUtils.convert(argValue, targetType);
        } catch (BError e) {
            return ModuleUtils.createParameterBindingError(
                    "invalid value for argument '" + paramName + "': " + e.getMessage());
        }
    }

    private static boolean isOptionalParameter(Parameter param) {
        Type paramType = param.type;

        if (paramType instanceof UnionType unionType) {
            return unionType.getMemberTypes().stream()
                    .anyMatch(type -> type.getTag() == TypeTags.NULL_TAG);
        }

        return false;
    }

    private static boolean isParameterOfType(Parameter param, String moduleName, String typeName) {
        Type paramType = param.type;
        return paramType.getPackage() != null
                && moduleName.equals(paramType.getPackage().getName())
                && typeName.equals(paramType.getName());
    }

    private static boolean isSessionParameter(Parameter param) {
        // Session is commonly declared nilable ('mcp:Session?'), so look through the union as well.
        return isMcpSessionType(param.type);
    }

    private static boolean isMcpSessionType(Type type) {
        if (type instanceof UnionType unionType) {
            return unionType.getMemberTypes().stream().anyMatch(McpServiceMethodHelper::isMcpSessionType);
        }
        return type.getPackage() != null
                && MCP_PACKAGE_NAME.equals(type.getPackage().getName())
                && SESSION_TYPE_NAME.equals(type.getName());
    }

    private static boolean isHeadersParameter(Parameter param) {
        return isParameterOfType(param, HTTP_PACKAGE_NAME, HEADERS_TYPE_NAME);
    }

    private static boolean isRequestParameter(Parameter param) {
        return isParameterOfType(param, HTTP_PACKAGE_NAME, REQUEST_TYPE_NAME);
    }

    /**
     * Returns the value of the '@http:Header' annotation attached to the given parameter, or null if the parameter is
     * not annotated with it.
     */
    private static BMap<?, ?> getHeaderAnnotation(RemoteMethodType method, String paramName) {
        Object annotations = method.getAnnotation(fromString(PARAM_ANNOT_PREFIX + paramName));
        if (!(annotations instanceof BMap<?, ?> annotationMap)) {
            return null;
        }
        Object headerAnnotation = findHttpHeaderAnnotation(annotationMap);
        if (headerAnnotation == null) {
            return null;
        }
        return headerAnnotation instanceof BMap<?, ?> headerAnnotationMap
                ? headerAnnotationMap : ValueCreator.createMapValue();
    }

    /**
     * Finds the 'ballerina/http:<version>:Header' entry in an annotation map without depending on the exact module
     * version segment of the key.
     */
    private static Object findHttpHeaderAnnotation(BMap<?, ?> annotationMap) {
        String httpPrefix = BALLERINA_ORG + ORG_SEPARATOR + HTTP_PACKAGE_NAME + COLON;
        for (Object key : annotationMap.getKeys()) {
            String keyName = key.toString();
            if (keyName.startsWith(httpPrefix) && keyName.endsWith(COLON + HEADER_ANNOTATION_NAME)) {
                return annotationMap.get(key);
            }
        }
        return null;
    }

    /**
     * Binds the value of an HTTP header (or a record of headers) to a '@http:Header' annotated parameter, mirroring the
     * semantics of '@http:Header' on http resources.
     */
    private static Object bindHeaderParam(Type paramType, String paramName, BMap<?, ?> annotation,
                                          BMap<?, ?> headerValues, boolean treatNilableAsOptional) {
        boolean readonlyParam = TypeUtils.getReferredType(paramType).getTag() == TypeTags.INTERSECTION_TAG;
        Type effectiveType = TypeUtils.getImpliedType(paramType);
        boolean nilable = false;
        if (effectiveType instanceof UnionType unionType) {
            List<Type> nonNilMembers = new ArrayList<>();
            for (Type member : unionType.getMemberTypes()) {
                if (member.getTag() == TypeTags.NULL_TAG) {
                    nilable = true;
                } else {
                    if (TypeUtils.getReferredType(member).getTag() == TypeTags.INTERSECTION_TAG) {
                        readonlyParam = true;
                    }
                    nonNilMembers.add(TypeUtils.getImpliedType(member));
                }
            }
            // A single non-nil member is bound directly; multiple members (enums and other
            // finite string unions) keep the union and rely on value conversion to validate
            if (nonNilMembers.size() == 1) {
                effectiveType = nonNilMembers.getFirst();
            }
        }

        if (effectiveType instanceof RecordType recordType) {
            return bindHeaderRecord(recordType, nilable, headerValues, treatNilableAsOptional, readonlyParam);
        }

        Object nameValue = annotation.get(fromString(ANNOTATION_NAME_FIELD));
        String headerName = nameValue instanceof BString headerNameValue
                ? headerNameValue.getValue() : paramName;
        return bindSingleHeader(effectiveType, headerName, nilable, headerValues, treatNilableAsOptional,
                readonlyParam);
    }

    private static Object bindSingleHeader(Type type, String headerName, boolean nilable, BMap<?, ?> headerValues,
                                           boolean treatNilableAsOptional, boolean readonlyValue) {
        Object values = headerValues.get(fromString(headerName.toLowerCase(Locale.ROOT)));
        if (values == null || ((BArray) values).getLength() == 0) {
            if (nilable && treatNilableAsOptional) {
                return null;
            }
            return ModuleUtils.createParameterBindingError("no header value found for '" + headerName + "'");
        }
        BArray headerValueArray = (BArray) values;
        try {
            if (TypeUtils.getImpliedType(type) instanceof ArrayType arrayType) {
                // Build into a mutable array (the declared one may be readonly) and freeze after
                Type elementType = arrayType.getElementType();
                BArray boundValues = ValueCreator.createArrayValue(
                        TypeCreator.createArrayType(TypeUtils.getImpliedType(elementType)));
                for (int i = 0; i < headerValueArray.getLength(); i++) {
                    boundValues.append(convertHeaderValue(elementType,
                            headerValueArray.getBString(i).getValue()));
                }
                if (readonlyValue) {
                    boundValues.freezeDirect();
                }
                return boundValues;
            }
            return convertHeaderValue(type, headerValueArray.getBString(0).getValue());
        } catch (NumberFormatException | BError e) {
            return ModuleUtils.createParameterBindingError(
                    "header binding failed for parameter '" + headerName + "'");
        }
    }

    private static Object convertHeaderValue(Type targetType, String value) {
        int typeTag = TypeUtils.getImpliedType(targetType).getTag();
        return switch (typeTag) {
            case TypeTags.STRING_TAG -> fromString(value);
            case TypeTags.INT_TAG -> Long.parseLong(value);
            case TypeTags.FLOAT_TAG -> Double.parseDouble(value);
            case TypeTags.DECIMAL_TAG -> ValueCreator.createDecimalValue(value);
            case TypeTags.BOOLEAN_TAG -> Boolean.parseBoolean(value);
            // Finite types, enums, and other string-constant unions: conversion both casts
            // and validates that the header value is a member of the type
            default -> ValueUtils.convert(fromString(value), targetType);
        };
    }

    private static Object bindHeaderRecord(RecordType recordType, boolean nilableRecord, BMap<?, ?> headerValues,
                                           boolean treatNilableAsOptional, boolean readonlyRecord) {
        // For readonly records, populate a plain mutable map and convert to the readonly
        // record type at the end (the readonly record type cannot be mutated field by field)
        BMap<BString, Object> recordValue = readonlyRecord
                ? ValueCreator.createMapValue()
                : ValueCreator.createRecordValue(recordType);
        BMap<BString, Object> recordAnnotations = recordType.getAnnotations();
        for (Map.Entry<String, Field> entry : recordType.getFields().entrySet()) {
            String fieldName = entry.getKey();
            Field field = entry.getValue();
            boolean optionalField = SymbolFlags.isFlagOn(field.getFlags(), SymbolFlags.OPTIONAL);

            // A field-level '@http:Header {name: ...}' annotation overrides the header name
            String headerName = fieldName;
            if (recordAnnotations != null) {
                Object fieldAnnotations = recordAnnotations.get(fromString(FIELD_ANNOT_PREFIX + fieldName));
                if (fieldAnnotations instanceof BMap<?, ?> fieldAnnotationMap
                        && findHttpHeaderAnnotation(fieldAnnotationMap) instanceof BMap<?, ?> headerAnnotationMap) {
                    Object nameValue = headerAnnotationMap.get(fromString(ANNOTATION_NAME_FIELD));
                    if (nameValue instanceof BString headerNameValue) {
                        headerName = headerNameValue.getValue();
                    }
                }
            }

            Type fieldType = TypeUtils.getImpliedType(field.getFieldType());
            boolean nilable = false;
            if (fieldType instanceof UnionType unionType) {
                List<Type> nonNilMembers = new ArrayList<>();
                for (Type member : unionType.getMemberTypes()) {
                    if (member.getTag() == TypeTags.NULL_TAG) {
                        nilable = true;
                    } else {
                        nonNilMembers.add(TypeUtils.getImpliedType(member));
                    }
                }
                if (nonNilMembers.size() == 1) {
                    fieldType = nonNilMembers.get(0);
                }
            }

            Object values = headerValues.get(fromString(headerName.toLowerCase(Locale.ROOT)));
            if (values == null || ((BArray) values).getLength() == 0) {
                if (optionalField) {
                    continue;
                }
                if (nilable && treatNilableAsOptional) {
                    recordValue.put(fromString(fieldName), null);
                    continue;
                }
                // Consistent with http: a nilable header record binds to nil when a
                // required header is missing, instead of failing the request
                if (nilableRecord && treatNilableAsOptional) {
                    return null;
                }
                return ModuleUtils.createParameterBindingError("no header value found for '" + headerName + "'");
            }

            Object boundValue = bindSingleHeader(fieldType, headerName, nilable, headerValues,
                    treatNilableAsOptional, false);
            if (boundValue instanceof BError) {
                return boundValue;
            }
            recordValue.put(fromString(fieldName), boundValue);
        }
        if (readonlyRecord) {
            try {
                return ValueUtils.convert(recordValue, recordType);
            } catch (BError e) {
                return ModuleUtils.createParameterBindingError("header binding failed for record of headers");
            }
        }
        return recordValue;
    }

    private static boolean isMetaParameter(Parameter param) {
        Type paramType = param.type;

        // Direct Meta type check
        if (paramType.getPackage() != null
                && MCP_PACKAGE_NAME.equals(paramType.getPackage().getName())
                && META_TYPE_NAME.equals(paramType.getName())) {
            return true;
        }

        // Check if it's an optional Meta type (mcp:Meta?)
        if (paramType instanceof UnionType unionType) {
            return unionType.getMemberTypes().stream()
                    .anyMatch(type -> type.getPackage() != null
                            && MCP_PACKAGE_NAME.equals(type.getPackage().getName())
                            && META_TYPE_NAME.equals(type.getName()));
        }

        return false;
    }

    private static Object createCallToolResult(BTypedesc typed, Object result) {
        RecordType resultRecordType = (RecordType) typed.getDescribingType();
        BMap<BString, Object> callToolResult = ValueCreator.createRecordValue(resultRecordType);

        ArrayType contentArrayType = (ArrayType) resultRecordType.getFields().get(CONTENT_FIELD_NAME).getFieldType();
        BArray contentArray = ValueCreator.createArrayValue(contentArrayType);

        Type contentElementType = TypeUtils.getImpliedType(contentArrayType.getElementType());
        if (!(contentElementType instanceof UnionType contentUnionType)) {
            return ModuleUtils.createError(
                    "Expected content element type to be a union type, but found: "
                            + contentElementType.getClass().getName());
        }
        Optional<Type> textContentTypeOpt = contentUnionType.getMemberTypes().stream()
                .filter(type -> TYPE_TEXT_CONTENT.equals(type.getName()))
                .findFirst();
        if (textContentTypeOpt.isEmpty()) {
            return ModuleUtils
                    .createError("No member type named 'TextContent' found in content union type.");
        }
        RecordType textContentRecordType = (RecordType) TypeUtils.getImpliedType(textContentTypeOpt.get());
        BMap<BString, Object> textContent = ValueCreator.createRecordValue(textContentRecordType);
        textContent.put(fromString(TYPE_FIELD_NAME), fromString(TEXT_VALUE_NAME));
        textContent.put(fromString(TEXT_FIELD_NAME), fromString(result == null ? "" : result.toString()));
        contentArray.append(textContent);

        callToolResult.put(fromString(CONTENT_FIELD_NAME), contentArray);
        return callToolResult;
    }
}
