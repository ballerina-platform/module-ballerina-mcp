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

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.Runtime;
import io.ballerina.runtime.api.types.MethodType;
import io.ballerina.runtime.api.types.ObjectType;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BDecimal;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BStream;
import io.ballerina.runtime.api.values.BString;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * The stream an {@code onSubscribe} handler returned, read with a timeout.
 * <p>
 * Each {@code next()} of the user stream runs on its own virtual thread, so a server subscription can
 * wait for it with the keep-alive interval as the timeout, be woken for shutdown, and close the stream
 * while that {@code next()} is still pending.
 */
public final class SubscriptionSource {

    private static final String NATIVE_KEY = "subscriptionSource";
    private static final BString IDLE = StringUtils.fromString("idle");

    private final BObject iterator;
    private final Runtime runtime;
    private final CompletableFuture<Void> wakeSignal = new CompletableFuture<>();
    private final AtomicBoolean closed = new AtomicBoolean();
    private CompletableFuture<Object> pendingNext;

    private SubscriptionSource(BStream eventSource, Runtime runtime) {
        this.iterator = eventSource.getIteratorObj();
        this.runtime = runtime;
    }

    /**
     * Attaches the user stream to the server subscription that reads it.
     *
     * @param env         The Ballerina runtime environment.
     * @param owner       The server subscription.
     * @param eventSource The stream returned by {@code onSubscribe}.
     */
    public static void attachSubscriptionSource(Environment env, BObject owner, BStream eventSource) {
        owner.addNativeData(NATIVE_KEY, new SubscriptionSource(eventSource, env.getRuntime()));
    }

    /**
     * Waits for the next item of the user stream.
     *
     * @param env     The Ballerina runtime environment.
     * @param owner   The server subscription.
     * @param timeout Seconds to wait.
     * @return The next item, nil at the end, an error, or "idle" when the wait timed out or was woken.
     */
    public static Object pollSubscriptionSource(Environment env, BObject owner, BDecimal timeout) {
        SubscriptionSource source = (SubscriptionSource) owner.getNativeData(NATIVE_KEY);
        long timeoutMillis = Math.max(1L, (long) (timeout.floatValue() * 1000));
        CompletableFuture<Object> next = source.nextItem();
        return env.yieldAndRun(() -> source.await(next, timeoutMillis));
    }

    /**
     * Wakes a pending {@link #pollSubscriptionSource} and makes later ones return "idle" at once.
     *
     * @param owner The server subscription.
     */
    public static void wakeSubscriptionSource(BObject owner) {
        SubscriptionSource source = (SubscriptionSource) owner.getNativeData(NATIVE_KEY);
        source.wakeSignal.complete(null);
    }

    /**
     * Closes the user stream once, even while its {@code next()} is pending.
     *
     * @param env   The Ballerina runtime environment.
     * @param owner The server subscription.
     * @return The error the user stream's {@code close()} returned, if any.
     */
    public static Object closeSubscriptionSource(Environment env, BObject owner) {
        SubscriptionSource source = (SubscriptionSource) owner.getNativeData(NATIVE_KEY);
        source.wakeSignal.complete(null);
        if (!source.closed.compareAndSet(false, true)) {
            return null;
        }
        return env.yieldAndRun(source::callClose);
    }

    /**
     * Closes the user stream once without waiting for its {@code close()} to return.
     *
     * @param owner The server subscription.
     */
    public static void closeSubscriptionSourceLater(BObject owner) {
        SubscriptionSource source = (SubscriptionSource) owner.getNativeData(NATIVE_KEY);
        source.wakeSignal.complete(null);
        if (source.closed.compareAndSet(false, true)) {
            Thread.startVirtualThread(source::callClose);
        }
    }

    private synchronized CompletableFuture<Object> nextItem() {
        if (pendingNext == null) {
            CompletableFuture<Object> next = new CompletableFuture<>();
            pendingNext = next;
            Thread.startVirtualThread(() -> next.complete(callIterator("next")));
        }
        return pendingNext;
    }

    private Object await(CompletableFuture<Object> next, long timeoutMillis) {
        try {
            CompletableFuture.anyOf(next, wakeSignal).get(timeoutMillis, TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            return IDLE;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ModuleUtils.createError("Interrupted while waiting for a subscription event");
        } catch (ExecutionException e) {
            return ModuleUtils.createError("Subscription source failed");
        }
        if (!next.isDone()) {
            return IDLE;
        }
        synchronized (this) {
            pendingNext = null;
        }
        return next.join();
    }

    private Object callClose() {
        // close() is optional on a stream's iterator, e.g. on one made by toStream().
        ObjectType iteratorType = (ObjectType) TypeUtils.getImpliedType(iterator.getOriginalType());
        for (MethodType method : iteratorType.getMethods()) {
            if ("close".equals(method.getName())) {
                return callIterator("close");
            }
        }
        return null;
    }

    private Object callIterator(String method) {
        try {
            return runtime.callMethod(iterator, method, null);
        } catch (RuntimeException e) {
            // A panic in the user stream must not leak its detail to the subscriber.
            return ModuleUtils.createError("Subscription source failed");
        }
    }
}
