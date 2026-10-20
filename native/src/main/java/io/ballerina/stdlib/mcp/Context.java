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

package io.ballerina.stdlib.mcp;

import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.ValueUtils;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

/**
 * Native operations of the 'mcp:Context' class.
 */
public final class Context {
    private static final BString INPUT_RESPONSES = StringUtils.fromString("inputResponses");
    private static final BString ACTION = StringUtils.fromString("action");
    private static final BString CONTENT = StringUtils.fromString("content");
    private static final String ACCEPT = "accept";

    private Context() {
    }

    /**
     * Returns the content of an accepted answer converted to the given type.
     *
     * @param context     The 'mcp:Context' object
     * @param key         The key of the input request
     * @param contentType The type to convert the content to
     * @return The converted content, or null if the answer is missing, not accepted or does not convert
     */
    public static Object acceptedContent(BObject context, BString key, BTypedesc contentType) {
        BMap<?, ?> inputResponses = context.getMapValue(INPUT_RESPONSES);
        if (!(inputResponses.get(key) instanceof BMap<?, ?> answer)
                || !ACCEPT.equals(String.valueOf(answer.get(ACTION)))
                || !(answer.get(CONTENT) instanceof BMap<?, ?> content)) {
            return null;
        }
        try {
            return ValueUtils.convert(content, contentType.getDescribingType());
        } catch (BError conversionError) {
            return null;
        }
    }
}
