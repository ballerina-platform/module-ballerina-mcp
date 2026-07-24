# Proposal: stdio Client Transport for Ballerina MCP

- Status: Draft
- Scope: **Client transport only** — stdio server (listener) support is explicitly deferred.
- Spec reference: [MCP 2025-11-25 — Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- POC: [`stdio-poc/`](../../stdio-poc/main.bal) — verified working against `uvx mcp-server-fetch` (full `initialize` → `notifications/initialized` → `tools/list` → `tools/call` cycle).

## 1. Feasibility findings (from POC)

The central question was whether Ballerina can spawn a long-lived subprocess and stream
JSON-RPC lines over its stdin/stdout. Findings:

| Option | Verdict |
|---|---|
| `ballerina/os` | **Not possible.** `os:Process` exposes only `waitForExit()`, `output()` (runs process to completion first), and `exit()`. No stdin writer, no incremental stdout reader. |
| `ballerina/io` | **Not sufficient alone.** Has the right abstractions (`ReadableCharacterChannel.lineStream()`, `WritableCharacterChannel.writeLine()`), but byte channels can only be constructed from file paths or in-memory `byte[]` — there is no public bridge from a process pipe or `java.io.InputStream` into an `io` channel. |
| Java interop (`java.lang.ProcessBuilder`) | **Works.** The POC drives the full MCP lifecycle against `uvx mcp-server-fetch` using interop bindings to `ProcessBuilder`, `BufferedWriter` (child stdin), and `BufferedReader` (child stdout). |

Conclusion: implement the transport on `java.lang.ProcessBuilder` via a **native Java helper
class** in the existing `native/` module (the module already ships `mcp-native.jar` with
helpers like `SseEventStreamHelper`, so there is no new packaging cost). A pure-`.bal` FFI
approach (as in the POC) also works, but the native helper is preferred because it can:

- run blocking `readLine()` off the Ballerina scheduler threads (`Environment.yieldAndRun`),
- implement read timeouts and the spec's graceful-shutdown sequence (`waitFor(timeout)` → `destroy()` → `destroyForcibly()`),
- handle the env-map / working-directory plumbing without `handle`-typed spaghetti in Ballerina code.

## 2. Spec requirements checklist (stdio, client side)

From the 2025-11-25 transport spec:

- [ ] Client launches the MCP server as a **subprocess**.
- [ ] Messages are **newline-delimited JSON-RPC**, UTF-8; messages MUST NOT contain embedded newlines (guaranteed by JSON string escaping — `toJsonString()` never emits raw newlines).
- [ ] Client MUST NOT write anything to the server's stdin that is not a valid MCP message.
- [ ] Server logs arrive on **stderr**; client MAY capture, forward, or ignore them.
- [ ] Client MUST NOT read protocol messages from anywhere but the server's stdout; blank lines between messages should be tolerated (observed in the wild with `mcp-server-fetch`).
- [ ] **Shutdown**: (1) close the child's stdin, (2) wait for exit, (3) `SIGTERM` if it doesn't exit within a grace period, (4) `SIGKILL` as last resort.
- [ ] **No session management** — the session is the process lifetime. No `Mcp-Session-Id`, no `MCP-Protocol-Version` header; the protocol version is negotiated purely via `initialize`.

## 3. Architecture

Mirror the existing layering (`StreamableHttpClient` → `StreamableHttpClientTransport` → http client), adding a parallel stdio stack:

```
StdioClient                     (public API, mirrors StreamableHttpClient minus HTTP headers)
  └── StdioClientTransport      (Ballerina class: line framing, request/response correlation)
        └── StdioProcessHelper  (native Java: ProcessBuilder, pipes, blocking reads, shutdown)
```

### 3.1 New files

| File | Contents |
|---|---|
| `ballerina/stdio_client.bal` | `public distinct isolated client class StdioClient` |
| `ballerina/stdio_client_transport.bal` | `isolated class StdioClientTransport` + `StdioClientTransportConfig` |
| `native/.../StdioProcessHelper.java` | Process lifecycle + pipe I/O native helper |
| `ballerina/tests/stdio_*.bal` | Unit/integration tests against a mock stdio server |
| Changes to `ballerina/error.bal` | stdio error hierarchy |
| Changes to `ballerina/utils.bal` (or new `client_utils.bal`) | Shared client logic extracted from `StreamableHttpClient` |

### 3.2 Configuration

```ballerina
# Configuration for launching an MCP server as a subprocess over stdio.
public type StdioClientTransportConfig record {|
    # Executable to launch (e.g. "uvx", "npx", "python").
    string command;
    # Arguments passed to the executable (e.g. ["mcp-server-fetch"]).
    string[] args = [];
    # Environment variables for the subprocess. By default the child inherits
    # the parent environment; entries here are added/overridden on top.
    map<string> env = {};
    # Working directory for the subprocess. Defaults to the current directory.
    string cwd?;
    # Seconds to wait for a response line before failing the request.
    decimal readTimeout = 60;
    # Maximum number of requests awaiting responses at the same time.
    int maxConcurrentRequests = 32;
    # Grace period (seconds) between closing stdin / SIGTERM / SIGKILL during shutdown.
    decimal shutdownTimeout = 5;
    # How to handle the child's stderr: forward to parent stderr (default) or discard.
    "inherit"|"discard" stderrMode = "inherit";
|};
```

This maps 1:1 onto the conventional `mcpServers` JSON config shape (`command`, `args`, `env`),
so users can translate configs like:

```json
{ "mcpServers": { "fetch": { "command": "uvx", "args": ["mcp-server-fetch"] } } }
```

into:

```ballerina
mcp:StdioClient mcpClient = check new (command = "uvx", args = ["mcp-server-fetch"]);
```

### 3.3 `StdioClient` (public API)

Mirrors `StreamableHttpClient` so the two clients are drop-in analogous:

```ballerina
public distinct isolated client class StdioClient {
    public isolated function init(*StdioClientTransportConfig config) returns ClientError?;
    isolated remote function initialize(Implementation clientInfo = ..., ClientCapabilities capabilities = {}) returns ClientError?;
    isolated remote function listTools() returns ListToolsResult|ClientError;
    isolated remote function callTool(CallToolParams params) returns CallToolResult|ClientError;
    isolated remote function subscribeToServerMessages() returns stream<JsonRpcMessage, StreamError?>|ClientError;
    isolated remote function close() returns ClientError?;
}
```

Differences from the HTTP client:

- No `headers` parameters (HTTP-specific).
- No session-ID handling; `initialize` always runs the handshake (no reconnect short-circuit).
- `close()` performs process shutdown instead of HTTP `DELETE`.
- `subscribeToServerMessages()` exposes one live stream of server-initiated messages from the
  transport (see §3.5), including messages received while the client is idle. The stream must be
  closed before a subsequent subscription is opened.

**Shared-logic refactor:** `initialize` handshake validation (protocol-version check, capability
capture), request-ID generation, and result-type dispatch are copy-identical between the two
clients. Extract into module-level functions (e.g. `validateInitializeResult`,
`buildJsonRpcRequest`) used by both, rather than introducing an abstract transport interface —
the two `sendMessage` signatures differ (headers), so a common object-type interface is a
larger refactor deferred until a third transport appears.

### 3.4 `StdioClientTransport`

```ballerina
isolated class StdioClientTransport {
    isolated function init(*StdioClientTransportConfig config) returns StdioTransportError?;
    // Requests: write line, then await the response with the matching id.
    // Notifications: write line, return ().
    isolated function sendMessage(JsonRpcMessage message) returns JsonRpcMessage|StdioTransportError?;
    // Opens the single stream of server-initiated messages (notifications / requests).
    isolated function establishMessageStream() returns stream<JsonRpcMessage, StreamError?>|StdioTransportError;
    // Spec shutdown sequence: close stdin → waitFor(shutdownTimeout) → destroy → destroyForcibly.
    isolated function terminateProcess() returns StdioTransportError?;
    isolated function isServerAlive() returns boolean;
}
```

Framing and correlation rules:

- Serialize with `message.toJsonString()` + `"\n"`, flush after every write.
- Read loop: `readLine()`; skip blank lines; parse into `JsonRpcMessage` (reuse the union +
  `fromJsonStringWithType()` pattern from `JsonRpcMessageStreamTransformer`); a parse failure is
  a recoverable `TypeConversionError` on that message, not a transport failure.
- **Correlation:** the dedicated reader routes each JSON-RPC response to a per-request queue
  by its ID, so up to `maxConcurrentRequests` requests may await independent responses at once.
  Server notifications and requests are routed to a separate bounded queue consumed by one
  `establishMessageStream()` subscriber, even while no client request is in flight. Unknown
  responses are dropped.
- **EOF** (`readLine()` returns null) means the server died: fail the in-flight request with
  `ServerProcessExitedError` (including the exit code) and mark the transport closed.

### 3.5 Native helper: `StdioProcessHelper.java`

Follows the `SseEventStreamHelper` pattern — static methods, state stashed on the Ballerina
object via `addNativeData`:

```java
public final class StdioProcessHelper {
    // Stores Process, BufferedWriter (stdin), BufferedReader (stdout) as native data.
    public static Object startProcess(BObject transport, BString command, BArray args,
                                      BMap<BString, BString> env, Object cwd, BString stderrMode);
    // Blocking ops run via env.yieldAndRun(...) so Ballerina scheduler threads are never blocked.
    public static Object writeLine(Environment env, BObject transport, BString line);
    public static Object readLine(Environment env, BObject transport, BDecimal timeoutSeconds); // returns BString | null(EOF) | BError(timeout/IO)
    public static Object terminateProcess(Environment env, BObject transport, BDecimal graceSeconds);
    public static boolean isAlive(BObject transport);
    public static long exitCode(BObject transport);
}
```

Implementation notes:

- `ProcessBuilder(command + args)`, `directory(cwd)`, `environment().putAll(env)`.
- stderr: `Redirect.INHERIT` or `Redirect.DISCARD` per config (POC used INHERIT; server logs
  visibly flowing to the terminal matches other SDKs' default behavior).
- UTF-8 explicitly on both `InputStreamReader` and `OutputStreamWriter`.
- **Read timeout**: `readLine` cannot be interrupted portably; implement with a dedicated
  reader thread per process pumping lines into a `LinkedBlockingQueue<String>`, with the
  Ballerina-facing `readLine` doing `queue.poll(timeout, SECONDS)` inside `yieldAndRun`. The
  reader thread also observes EOF and enqueues sentinels for pending response waiters and the
  server-message stream.
- **Shutdown** (`terminateProcess`): close stdin writer → `process.waitFor(grace, SECONDS)` →
  `destroy()` (SIGTERM) → `waitFor(grace)` → `destroyForcibly()` (SIGKILL). Also interrupt/join
  the reader thread.
- **Kill the whole process tree, not just the direct child.** Verified empirically: `uvx`
  spawns the actual Python server as a *grandchild*. SIGTERM on `uvx` propagates and cleans up
  both, but SIGKILL (`destroyForcibly`) orphans the grandchild (reparented to PID 1, still
  running). Before force-killing, enumerate `process.toHandle().descendants()` and destroy
  those first (`destroyForcibly` on each), then the direct child.
- GraalVM: `ProcessBuilder` is fully supported in native images; no reflection is introduced,
  so `graalvmCompatible = true` stands.

### 3.6 Error types (`error.bal` additions)

```ballerina
# Error for failures during stdio transport operations.
public type StdioTransportError distinct TransportError & ClientError;
# Error when the server subprocess cannot be launched.
public type ProcessSpawnError distinct StdioTransportError;
# Error when the server subprocess exits or closes stdout unexpectedly.
public type ServerProcessExitedError distinct StdioTransportError;
# Error when a response is not received within the configured read timeout.
public type ReadTimeoutError distinct StdioTransportError;
# Error for failures while writing to the server subprocess stdin.
public type StdioWriteError distinct StdioTransportError;
# Error for failures during subprocess termination.
public type ProcessTerminationError distinct StdioTransportError;
```

## 4. Testing strategy

1. **Mock stdio server** in `ballerina/tests/resources/`: a small self-contained script
   (Python 3, already a CI-safe dependency, or a prebuilt Ballerina jar) that implements
   `initialize`/`tools/list`/`tools/call` over stdio with canned responses, plus misbehavior
   modes triggered by env var: emit blank lines, emit garbage lines, delay responses (timeout
   test), exit mid-request (EOF test), write junk to stderr.
2. **Unit tests**: config validation; JSON-RPC framing (no embedded newlines); correlation
   (interleaved notification before response is queued, response still returned); error mapping
   for spawn failure (nonexistent command), timeout, EOF.
3. **Lifecycle tests**: `close()` terminates the child (assert not alive); double-close is
   idempotent; child killed externally → next call returns `ServerProcessExitedError`.
4. **Manual/integration** (not CI-gated): `uvx mcp-server-fetch` end-to-end, as in the POC.
5. `ballerina-tests/` integration suite gets a stdio variant mirroring the existing
   client tests where applicable.

## 5. Delivery phases

1. **Phase 1 — transport core**: `StdioProcessHelper.java`, `StdioClientTransport`, error
   types. Exit criteria: POC flow reproducible through the transport class.
2. **Phase 2 — public client**: `StdioClient`, shared-logic extraction from
   `StreamableHttpClient` (no behavior change to HTTP client), `subscribeToServerMessages`.
3. **Phase 3 — robustness**: read timeouts, spec shutdown sequence, EOF/exit-code surfacing,
   stderr modes, blank/garbage line tolerance.
4. **Phase 4 — tests, docs, example**: mock-server test suite, module README + changelog,
   an `examples/` entry (e.g. stdio fetch client), API docs.

## 6. Deferred / follow-ups

- **stdio server (listener) support** — different shape entirely (read own stdin, single
  client, no `http:Listener`); deferred per scope.
- **Server→client requests** (`ping`, sampling, elicitation, roots) — currently also
  unsupported over HTTP; stdio surfaces them via `subscribeToServerMessages` for now.
- **Common `Transport` abstraction / unified `Client`** — revisit when a third transport or
  the server work lands.
- **Windows validation** — `ProcessBuilder` + pipes work on Windows, but `.cmd`/`.bat`
  resolution for `npx` needs an explicit test pass.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Blocking reads starving Ballerina scheduler threads | All blocking calls go through `Environment.yieldAndRun` in the native helper; reader thread owns the actual block. |
| Zombie child processes if the Ballerina program crashes | Reader thread is daemon; register a JVM shutdown hook in the helper that force-destroys live processes (including descendants). |
| Orphaned grandchildren on force-kill (launcher commands like `uvx`/`npx`) | Kill `descendants()` before `destroyForcibly()` — see §3.5; verified that SIGKILL on `uvx` alone orphans the Python server. |
| Servers that emit non-JSON lines on stdout | Tolerate blank lines (observed with `mcp-server-fetch`); surface parse failures per-message, not as transport death. |
| Large single-line responses | `BufferedReader.readLine` handles arbitrary length; memory-bound only — same exposure as the HTTP client. Verified with a ~19 KB single-line response. |

## 8. Verification status

Verified empirically (POC on macOS, Ballerina 2201.13.4, runtime API 2201.12.0):

- ✅ Full MCP lifecycle over stdio (`initialize` → `initialized` → `tools/list` → `tools/call`) against `uvx mcp-server-fetch`.
- ✅ Blank lines between messages occur in practice and must be skipped.
- ✅ `Environment.yieldAndRun(Supplier<T>)` exists in `ballerina-runtime` 2201.12.0 (confirmed via `javap`).
- ✅ Large single-line responses (~19 KB) read correctly through `BufferedReader.readLine`.
- ✅ SIGTERM on `uvx` cleans up its Python grandchild; SIGKILL orphans it → descendants-kill required (§3.5).
- ✅ No leftover processes after normal `Process.destroy()` shutdown.

Verified by the Phase 1 implementation (`StdioClientTransport` + `StdioProcessHelper`, mock-server test suite in `ballerina/tests/stdio_transport_test.bal`):

- ✅ POC flow reproduced through the transport class against both the mock server and real `uvx mcp-server-fetch` (Phase 1 exit criterion).
- ✅ Response/notification interleaving: interleaved notifications are buffered, the correlated response is still returned.
- ✅ Read-timeout path returns a typed `ReadTimeoutError`.
- ✅ `env` overlay via `ProcessBuilder` (mock misbehavior modes are driven by env vars).
- ✅ Typed module errors created from native code via `ErrorCreator.createError(module, typeName, ...)` satisfy multi-level `distinct` error checks.
- ✅ EOF / server-death surfaces as `ServerProcessExitedError` (or `StdioWriteError` when the write hits the dead pipe first).
- ✅ Shutdown is idempotent and leaves no leftover processes.

Verified by the Phase 3 robustness suite (`ballerina/tests/stdio_robustness_test.bal`):

- ✅ Concurrency: 24 parallel `callTool`s (2× the machine's carrier threads) all complete with correctly correlated responses — blocked reads yield instead of starving the scheduler.
- ✅ Read-timeout recovery: a response arriving after its request timed out is discarded on the next request's cycle; the next request still receives its own response.
- ✅ `cwd` via `ProcessBuilder` (script resolved relative to the configured cwd, verified by a `cwd` tool).
- ✅ Long-lived session: 60 sequential tool calls on one subprocess, each response matched to its request.
- ✅ stderr flood (~2MB) does not backpressure the session — inherit/discard modes never create a stderr pipe.

Still open (needs CI / other platforms):

- ⬜ Windows: `.cmd`/`.bat` launcher resolution (`npx`), process-tree termination semantics.
- ⬜ GraalVM native image build with the new helper (`ProcessBuilder` is supported; needs the existing native-image CI job to pass).
