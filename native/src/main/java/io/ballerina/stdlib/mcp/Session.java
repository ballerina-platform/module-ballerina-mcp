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

import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;
import org.ballerinalang.langlib.value.EnsureType;

/**
 * Utility class for Session operations in Ballerina via Java interop.
 */
public final class Session {
    private static final BString SESSION_ENTRIES = StringUtils.fromString("entries");

    private Session() {
    }

    /**
     * Retrieves and casts a value from the session to the specified type.
     *
     * @param sessionObj The Ballerina session object
     * @param key        The key identifying the entry
     * @param targetType The expected type of the entry
     * @return The cast value or an error if the entry is missing or of the wrong type
     */
    public static Object getWithType(BObject sessionObj, BString key, BTypedesc targetType) {
        BMap<BString, Object> members = sessionObj.getMapValue(SESSION_ENTRIES);
        try {
            Object value = members.getOrThrow(key);
            Object convertedType = EnsureType.ensureType(value, targetType);
            if (convertedType instanceof BError) {
                return ModuleUtils.createError("type conversion failed for value of key: " + key.getValue());
            }
            return convertedType;
        } catch (RuntimeException e) {
            return ModuleUtils.createError("no member found for key: " + key.getValue());
        }
    }
}
