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
import io.ballerina.runtime.api.creators.ErrorCreator;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BStream;
import io.ballerina.runtime.api.values.BString;

import static io.ballerina.runtime.api.utils.StringUtils.fromString;

/**
 * Utility class for handling Server-Sent Events (SSE) streams in Ballerina via Java interop.
 * <p>
 * Provides static helper methods to:
 * <ul>
 *     <li>Attach an SSE stream to a Ballerina object as native data.</li>
 *     <li>Retrieve the next event from an SSE stream.</li>
 *     <li>Close the SSE stream and release resources.</li>
 * </ul>
 * This class is not instantiable.
 */
public final class SseEventStreamHelper {

    /** Native data key used to store the SSE stream in the Ballerina object. */
    private static final String SSE_STREAM_NATIVE_KEY = "sseStream";

    // Private constructor to prevent instantiation.
    private SseEventStreamHelper() {}

    /**
     * Attaches the provided SSE {@link BStream} as native data to the specified Ballerina object.
     *
     * @param object    The Ballerina object that will hold the SSE stream (native data).
     * @param sseStream The SSE stream instance to attach.
     */
    public static void attachSseStream(BObject object, BStream sseStream) {
        object.addNativeData(SSE_STREAM_NATIVE_KEY, sseStream);
    }

    /**
     * Retrieves the next event from the SSE stream attached to the given Ballerina object.
     * <p>
     * Invokes the "next" method on the stream's iterator object using the Ballerina runtime.
     *
     * @param env       The Ballerina runtime environment.
     * @param object    The Ballerina object holding the SSE stream as native data.
     * @return          The next SSE event record, null if the stream is exhausted,
     *                  or a Ballerina error object if unavailable.
     */
    public static Object getNextSseEvent(Environment env, BObject object) {
        BStream sseStream = (BStream) object.getNativeData(SSE_STREAM_NATIVE_KEY);
        if (sseStream == null) {
            BString errorMessage = fromString("Unable to obtain elements from stream. SSE stream not found.");
            return ErrorCreator.createError(errorMessage);
        }
        BObject iteratorObject = sseStream.getIteratorObj();
        // Use the Ballerina runtime to call the "next" method on the iterator and fetch the next event.
        return env.getRuntime().callMethod(iteratorObject, "next", null);
    }

    /**
     * Closes the SSE stream attached to the given Ballerina object.
     * <p>
     * Invokes the "close" method on the stream's iterator object using the Ballerina runtime.
     *
     * @param env       The Ballerina runtime environment.
     * @param object    The Ballerina object holding the SSE stream as native data.
     * @return          The result of the close operation (could be null or a Ballerina error object).
     */
    public static Object closeSseEventStream(Environment env, BObject object) {
        BStream sseStream = (BStream) object.getNativeData(SSE_STREAM_NATIVE_KEY);
        if (sseStream == null) {
            BString errorMessage = fromString("Unable to obtain elements from stream. SSE stream not found.");
            return ErrorCreator.createError(errorMessage);
        }
        BObject iteratorObject = sseStream.getIteratorObj();
        // Use the Ballerina runtime to call the "close" method on the iterator and release resources.
        return env.getRuntime().callMethod(iteratorObject, "close", null);
    }
}
