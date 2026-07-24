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
import io.ballerina.runtime.api.utils.JsonUtils;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BDecimal;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * Native helper for the MCP stdio client transport.
 * <p>
 * Manages the lifecycle of an MCP server subprocess and provides line-oriented,
 * UTF-8 encoded access to its stdin/stdout pipes:
 * <ul>
 *     <li>Spawns the subprocess via {@link ProcessBuilder} and stores the process,
 *     its stdin writer, response waiters, and server-message queue as native data on the transport object.</li>
 *     <li>A dedicated daemon reader thread routes stdout messages to blocking queues so
 *     reads support timeouts and never block Ballerina scheduler threads
 *     (all blocking calls run inside {@link Environment#yieldAndRun}).</li>
 *     <li>Termination follows the MCP stdio shutdown sequence: close stdin, wait,
 *     SIGTERM, wait, then SIGKILL — force-killing descendant processes too, since
 *     launcher commands such as {@code uvx}/{@code npx} spawn the real server as a
 *     grandchild that would otherwise be orphaned.</li>
 * </ul>
 * This class is not instantiable.
 */
public final class StdioProcessHelper {

    /** Native data key for the server {@link Process}. */
    private static final String PROCESS_NATIVE_KEY = "stdioProcess";
    /** Native data key for the {@link BufferedWriter} wrapping the server's stdin. */
    private static final String STDIN_WRITER_NATIVE_KEY = "stdioStdinWriter";
    /** Native data key for the queue of server-initiated stdout messages. */
    private static final String SERVER_MESSAGE_QUEUE_NATIVE_KEY = "stdioServerMessageQueue";
    /** Native data key for response waiters, keyed by JSON-RPC request ID. */
    private static final String RESPONSE_WAITERS_NATIVE_KEY = "stdioResponseWaiters";
    /** Native data key for the stdout reader {@link Thread}. */
    private static final String READER_THREAD_NATIVE_KEY = "stdioReaderThread";

    /**
     * Maximum number of stdout lines buffered ahead of the consumer. Once full, the reader
     * blocks, which propagates backpressure through the OS pipe to the child rather than
     * accumulating an unbounded number of lines in this queue.
     */
    private static final int LINE_QUEUE_CAPACITY = 1024;

    /** Queue sentinel signalling that the server closed its stdout (EOF). */
    private static final Object EOF_SENTINEL = new Object();

    /** stderr handling mode: forward the child's stderr to the parent's stderr. */
    private static final String STDERR_MODE_INHERIT = "inherit";

    /** Error type names defined in the module's {@code error.bal}. */
    private static final String STDIO_TRANSPORT_ERROR = "StdioTransportError";
    private static final String PROCESS_SPAWN_ERROR = "ProcessSpawnError";
    private static final String READ_TIMEOUT_ERROR = "ReadTimeoutError";
    private static final String STDIO_READ_ERROR = "StdioReadError";
    private static final String STDIO_WRITE_ERROR = "StdioWriteError";
    private static final String PROCESS_TERMINATION_ERROR = "ProcessTerminationError";

    /** Live server processes, force-destroyed by the JVM shutdown hook to avoid leaks. */
    private static final Set<Process> LIVE_PROCESSES = ConcurrentHashMap.newKeySet();

    static {
        Runtime.getRuntime().addShutdownHook(new Thread(() -> LIVE_PROCESSES.forEach(process -> {
            List<ProcessHandle> descendants = process.toHandle().descendants().toList();
            descendants.forEach(ProcessHandle::destroyForcibly);
            process.destroyForcibly();
        }), "mcp-stdio-shutdown-hook"));
    }

    // Private constructor to prevent instantiation.
    private StdioProcessHelper() {}

    /**
     * Spawns the MCP server subprocess and attaches its handles to the transport object.
     *
     * @param transport  The Ballerina transport object holding native state.
     * @param command    Executable to launch.
     * @param args       Arguments passed to the executable.
     * @param envVars    Environment variables overlaid on the inherited environment.
     * @param cwd        Working directory for the subprocess, or null for the current directory.
     * @param stderrMode Either {@code inherit} or {@code discard}.
     * @return           Null on success, or a Ballerina error if the process cannot be spawned.
     */
    public static Object startServerProcess(BObject transport, BString command, BArray args,
                                            BMap<BString, Object> envVars, Object cwd, BString stderrMode) {
        List<String> commandLine = new ArrayList<>();
        commandLine.add(command.getValue());
        for (String argument : args.getStringArray()) {
            commandLine.add(argument);
        }

        ProcessBuilder processBuilder = new ProcessBuilder(commandLine);
        if (cwd instanceof BString workingDirectory) {
            processBuilder.directory(new File(workingDirectory.getValue()));
        }
        Map<String, String> processEnvironment = processBuilder.environment();
        for (BString envKey : envVars.getKeys()) {
            processEnvironment.put(envKey.getValue(), envVars.get(envKey).toString());
        }
        if (STDERR_MODE_INHERIT.equals(stderrMode.getValue())) {
            processBuilder.redirectError(ProcessBuilder.Redirect.INHERIT);
        } else {
            processBuilder.redirectError(ProcessBuilder.Redirect.DISCARD);
        }

        Process serverProcess;
        try {
            serverProcess = processBuilder.start();
        } catch (IOException e) {
            return ModuleUtils.createTypedError(PROCESS_SPAWN_ERROR,
                    "Failed to spawn MCP server process '" + command.getValue() + "': " + e.getMessage());
        }

        BufferedWriter stdinWriter = new BufferedWriter(
                new OutputStreamWriter(serverProcess.getOutputStream(), StandardCharsets.UTF_8));
        LinkedBlockingQueue<Object> serverMessageQueue = new LinkedBlockingQueue<>(LINE_QUEUE_CAPACITY);
        ConcurrentHashMap<String, LinkedBlockingQueue<Object>> responseWaiters = new ConcurrentHashMap<>();
        Thread readerThread = startReaderThread(serverProcess, serverMessageQueue, responseWaiters);

        transport.addNativeData(PROCESS_NATIVE_KEY, serverProcess);
        transport.addNativeData(STDIN_WRITER_NATIVE_KEY, stdinWriter);
        transport.addNativeData(SERVER_MESSAGE_QUEUE_NATIVE_KEY, serverMessageQueue);
        transport.addNativeData(RESPONSE_WAITERS_NATIVE_KEY, responseWaiters);
        transport.addNativeData(READER_THREAD_NATIVE_KEY, readerThread);
        LIVE_PROCESSES.add(serverProcess);
        return null;
    }

    /**
     * Writes one JSON-RPC message line to the server's stdin and flushes.
     *
     * @param env       The Ballerina runtime environment.
     * @param transport The Ballerina transport object holding native state.
     * @param line      The serialized message, without a trailing newline.
     * @return          Null on success, or a Ballerina error on write failure.
     */
    public static Object writeMessageLine(Environment env, BObject transport, BString line) {
        BufferedWriter stdinWriter = (BufferedWriter) transport.getNativeData(STDIN_WRITER_NATIVE_KEY);
        if (stdinWriter == null) {
            return ModuleUtils.createTypedError(STDIO_TRANSPORT_ERROR, "Server process has not been started.");
        }
        return env.yieldAndRun(() -> {
            synchronized (stdinWriter) {
                try {
                    stdinWriter.write(line.getValue());
                    stdinWriter.write('\n');
                    stdinWriter.flush();
                    return null;
                } catch (IOException e) {
                    return ModuleUtils.createTypedError(STDIO_WRITE_ERROR,
                            "Failed to write message to server process stdin: " + e.getMessage());
                }
            }
        });
    }

    /** Registers a response waiter before its request is written to stdin. */
    public static Object registerResponseWaiter(BObject transport, Object requestId) {
        ConcurrentHashMap<String, LinkedBlockingQueue<Object>> responseWaiters = getResponseWaiters(transport);
        if (responseWaiters == null) {
            return ModuleUtils.createTypedError(STDIO_TRANSPORT_ERROR, "Server process has not been started.");
        }
        String requestKey = requestKey(requestId);
        if (responseWaiters.putIfAbsent(requestKey, new LinkedBlockingQueue<>(1)) != null) {
            return ModuleUtils.createTypedError(STDIO_TRANSPORT_ERROR,
                    "A response waiter is already registered for request id " + requestId + ".");
        }
        return null;
    }

    /** Waits for the correlated response that the reader routed to the given request ID. */
    public static Object awaitResponse(Environment env, BObject transport, Object requestId, BDecimal timeoutSeconds) {
        ConcurrentHashMap<String, LinkedBlockingQueue<Object>> responseWaiters = getResponseWaiters(transport);
        if (responseWaiters == null) {
            return ModuleUtils.createTypedError(STDIO_TRANSPORT_ERROR, "Server process has not been started.");
        }
        LinkedBlockingQueue<Object> responseQueue = responseWaiters.get(requestKey(requestId));
        if (responseQueue == null) {
            return ModuleUtils.createTypedError(STDIO_TRANSPORT_ERROR,
                    "No response waiter is registered for request id " + requestId + ".");
        }
        long timeoutMillis = (long) (timeoutSeconds.decimalValue().doubleValue() * 1000);
        return env.yieldAndRun(() -> {
            try {
                Object queueItem = responseQueue.poll(timeoutMillis, TimeUnit.MILLISECONDS);
                if (queueItem == null) {
                    return ModuleUtils.createTypedError(READ_TIMEOUT_ERROR,
                            "No response received from server process within " + timeoutSeconds + " seconds.");
                }
                if (queueItem == EOF_SENTINEL) {
                    return null;
                }
                return StringUtils.fromString((String) queueItem);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return ModuleUtils.createTypedError(STDIO_READ_ERROR,
                        "Interrupted while waiting for a server response.");
            }
        });
    }

    /** Removes a response waiter after it receives a response or fails. */
    public static void unregisterResponseWaiter(BObject transport, Object requestId) {
        ConcurrentHashMap<String, LinkedBlockingQueue<Object>> responseWaiters = getResponseWaiters(transport);
        if (responseWaiters != null) {
            responseWaiters.remove(requestKey(requestId));
        }
    }

    /** Retrieves the next server-initiated message, waiting until one arrives or stdout closes. */
    public static Object readServerMessage(Environment env, BObject transport) {
        LinkedBlockingQueue<Object> serverMessageQueue = getServerMessageQueue(transport);
        if (serverMessageQueue == null) {
            return ModuleUtils.createTypedError(STDIO_TRANSPORT_ERROR, "Server process has not been started.");
        }
        return env.yieldAndRun(() -> {
            try {
                Object queueItem = serverMessageQueue.take();
                if (queueItem == EOF_SENTINEL) {
                    serverMessageQueue.put(EOF_SENTINEL);
                    return null;
                }
                return StringUtils.fromString((String) queueItem);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return ModuleUtils.createTypedError(STDIO_READ_ERROR,
                        "Interrupted while waiting for a server-initiated message.");
            }
        });
    }

    /**
     * Terminates the server subprocess following the MCP stdio shutdown sequence:
     * close stdin → wait → destroy (SIGTERM) → wait → destroy forcibly (SIGKILL).
     * Descendant processes are force-killed before the force-kill of the direct child,
     * since killing only a launcher (e.g. uvx) would orphan the actual server.
     *
     * @param env          The Ballerina runtime environment.
     * @param transport    The Ballerina transport object holding native state.
     * @param graceSeconds Grace period applied at each stage of the sequence.
     * @return             Null on success, or a Ballerina error if the process could not be terminated.
     */
    public static Object terminateServerProcess(Environment env, BObject transport, BDecimal graceSeconds) {
        Process serverProcess = (Process) transport.getNativeData(PROCESS_NATIVE_KEY);
        BufferedWriter stdinWriter = (BufferedWriter) transport.getNativeData(STDIN_WRITER_NATIVE_KEY);
        Thread readerThread = (Thread) transport.getNativeData(READER_THREAD_NATIVE_KEY);
        if (serverProcess == null) {
            return null;
        }
        // Wake the reader in case it is blocked enqueuing onto a full queue with no consumer,
        // so it does not linger after the process is gone.
        if (readerThread != null) {
            readerThread.interrupt();
        }
        signalEof(transport);
        long graceMillis = (long) (graceSeconds.decimalValue().doubleValue() * 1000);
        return env.yieldAndRun(() -> {
            List<ProcessHandle> descendants = serverProcess.toHandle().descendants().toList();
            try {
                if (stdinWriter != null) {
                    synchronized (stdinWriter) {
                        try {
                            stdinWriter.close();
                        } catch (IOException ignored) {
                            // The pipe may already be broken if the process exited; proceed with termination.
                        }
                    }
                }
                boolean exited = serverProcess.waitFor(graceMillis, TimeUnit.MILLISECONDS);
                if (!exited) {
                    serverProcess.destroy();
                    exited = serverProcess.waitFor(graceMillis, TimeUnit.MILLISECONDS);
                }
                if (!exited) {
                    descendants.forEach(ProcessHandle::destroyForcibly);
                    serverProcess.destroyForcibly();
                    exited = serverProcess.waitFor(graceMillis, TimeUnit.MILLISECONDS);
                }
                // Reap descendants that survived their parent regardless of how it exited.
                descendants.stream().filter(ProcessHandle::isAlive).forEach(ProcessHandle::destroyForcibly);
                LIVE_PROCESSES.remove(serverProcess);
                if (!exited) {
                    return ModuleUtils.createTypedError(PROCESS_TERMINATION_ERROR,
                            "Server process did not terminate after SIGKILL.");
                }
                return null;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return ModuleUtils.createTypedError(PROCESS_TERMINATION_ERROR,
                        "Interrupted while waiting for the server process to terminate.");
            }
        });
    }

    /**
     * Reports whether the server subprocess is currently alive.
     *
     * @param transport The Ballerina transport object holding native state.
     * @return          True if the process has been started and has not yet exited.
     */
    public static boolean isServerProcessAlive(BObject transport) {
        Process serverProcess = (Process) transport.getNativeData(PROCESS_NATIVE_KEY);
        return serverProcess != null && serverProcess.isAlive();
    }

    /**
     * Returns the exit code of the server subprocess.
     *
     * @param transport The Ballerina transport object holding native state.
     * @return          The exit code as a Ballerina int, or null if the process is still alive or was never started.
     */
    public static Object serverProcessExitCode(BObject transport) {
        Process serverProcess = (Process) transport.getNativeData(PROCESS_NATIVE_KEY);
        if (serverProcess == null || serverProcess.isAlive()) {
            return null;
        }
        return (long) serverProcess.exitValue();
    }

    /**
     * Starts and returns the daemon thread that routes correlated responses to their waiters and
     * queues server-initiated messages for subscribers. Blank lines are skipped. Enqueues block
     * on a full server-message queue, applying backpressure instead of growing memory without bound.
     */
    private static Thread startReaderThread(Process serverProcess, LinkedBlockingQueue<Object> serverMessageQueue,
                                            ConcurrentHashMap<String, LinkedBlockingQueue<Object>> responseWaiters) {
        Thread readerThread = new Thread(() -> {
            try (BufferedReader stdoutReader = new BufferedReader(
                    new InputStreamReader(serverProcess.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = stdoutReader.readLine()) != null) {
                    if (!line.isBlank()) {
                        String responseKey = getResponseKey(line);
                        if (responseKey != null) {
                            LinkedBlockingQueue<Object> responseQueue = responseWaiters.get(responseKey);
                            if (responseQueue != null) {
                                if (!responseQueue.offer(line)) {
                                    continue;
                                }
                            }
                            continue;
                        }
                        serverMessageQueue.put(line);
                    }
                }
            } catch (IOException ignored) {
                // Stream closed — treated the same as EOF.
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            signalEof(serverMessageQueue, responseWaiters);
        }, "mcp-stdio-reader-" + serverProcess.pid());
        readerThread.setDaemon(true);
        readerThread.start();
        return readerThread;
    }

    @SuppressWarnings("unchecked")
    private static ConcurrentHashMap<String, LinkedBlockingQueue<Object>> getResponseWaiters(BObject transport) {
        return (ConcurrentHashMap<String, LinkedBlockingQueue<Object>>) transport.getNativeData(
                RESPONSE_WAITERS_NATIVE_KEY);
    }

    @SuppressWarnings("unchecked")
    private static LinkedBlockingQueue<Object> getServerMessageQueue(BObject transport) {
        return (LinkedBlockingQueue<Object>) transport.getNativeData(SERVER_MESSAGE_QUEUE_NATIVE_KEY);
    }

    private static String getResponseKey(String line) {
        try {
            Object json = JsonUtils.parse(line);
            if (!(json instanceof BMap<?, ?> message)) {
                return null;
            }
            BString resultKey = StringUtils.fromString("result");
            BString errorKey = StringUtils.fromString("error");
            BString idKey = StringUtils.fromString("id");
            if (!message.containsKey(resultKey) && !message.containsKey(errorKey)) {
                return null;
            }
            Object responseId = message.get(idKey);
            return responseId == null ? null : requestKey(responseId);
        } catch (BError ignored) {
            return null;
        }
    }

    private static String requestKey(Object requestId) {
        if (requestId instanceof BString stringId) {
            return "string:" + stringId.getValue();
        }
        return "number:" + requestId;
    }

    private static void signalEof(BObject transport) {
        LinkedBlockingQueue<Object> serverMessageQueue = getServerMessageQueue(transport);
        ConcurrentHashMap<String, LinkedBlockingQueue<Object>> responseWaiters = getResponseWaiters(transport);
        if (serverMessageQueue != null) {
            serverMessageQueue.clear();
            if (!serverMessageQueue.offer(EOF_SENTINEL)) {
                throw new IllegalStateException("Unable to signal stdio server-message EOF.");
            }
        }
        if (responseWaiters != null) {
            responseWaiters.values().forEach(StdioProcessHelper::signalResponseEof);
        }
    }

    private static void signalEof(LinkedBlockingQueue<Object> serverMessageQueue,
                                  ConcurrentHashMap<String, LinkedBlockingQueue<Object>> responseWaiters) {
        // A full server-message queue must not delay requests from observing that stdout closed.
        responseWaiters.values().forEach(StdioProcessHelper::signalResponseEof);
        try {
            serverMessageQueue.put(EOF_SENTINEL);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static void signalResponseEof(LinkedBlockingQueue<Object> responseQueue) {
        if (!responseQueue.offer(EOF_SENTINEL)) {
            // A correlated response is already queued and must be delivered before EOF.
            return;
        }
    }
}
