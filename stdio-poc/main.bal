// POC: MCP stdio client transport in Ballerina.
//
// Proves that Ballerina can spawn a long-running MCP server subprocess
// (`uvx mcp-server-fetch`) and speak newline-delimited JSON-RPC over its
// stdin/stdout pipes, using Java interop (java.lang.ProcessBuilder).
//
// Why interop: ballerina/os `Process` exposes no stdin writer and no
// streaming stdout reader (only waitForExit/output-after-exit), and
// ballerina/io channels can only be created from files or byte arrays.

import ballerina/io;
import ballerina/jballerina.java;

const string JSONRPC_VERSION = "2.0";
const string PROTOCOL_VERSION = "2025-06-18";

type JsonRpcOutbound record {|
    string jsonrpc = JSONRPC_VERSION;
    int id?;
    string method;
    map<json> params?;
|};

public function main() returns error? {
    io:println("Starting MCP server subprocess: uvx mcp-server-fetch");
    handle commandList = newArrayList();
    _ = addToList(commandList, element = java:fromString("uvx"));
    _ = addToList(commandList, element = java:fromString("mcp-server-fetch"));

    handle processBuilder = newProcessBuilder(commandList);
    // Let server logs (stderr) pass through to our terminal; per MCP spec stderr is for logging.
    _ = redirectError(processBuilder, redirectTarget = getInheritRedirect());
    handle serverProcess = check startProcess(processBuilder);

    // Child stdin (we write requests here).
    handle stdinWriter = newBufferedWriter(check newOutputStreamWriter(getOutputStream(serverProcess),
            charsetName = java:fromString("UTF-8")));
    // Child stdout (we read responses here).
    handle stdoutReader = newBufferedReader(check newInputStreamReader(getInputStream(serverProcess),
            charsetName = java:fromString("UTF-8")));

    do {
        // 1. initialize handshake
        JsonRpcOutbound initializeRequest = {
            id: 1,
            method: "initialize",
            params: {
                protocolVersion: PROTOCOL_VERSION,
                capabilities: {},
                clientInfo: {name: "ballerina-stdio-poc", version: "0.1.0"}
            }
        };
        check sendMessage(stdinWriter, message = initializeRequest);
        string initializeResponse = check readMessage(stdoutReader);
        io:println("\n<< initialize response:\n" + initializeResponse);

        // 2. initialized notification (no id, no response expected)
        JsonRpcOutbound initializedNotification = {method: "notifications/initialized"};
        check sendMessage(stdinWriter, message = initializedNotification);

        // 3. tools/list
        JsonRpcOutbound listToolsRequest = {id: 2, method: "tools/list"};
        check sendMessage(stdinWriter, message = listToolsRequest);
        string listToolsResponse = check readMessage(stdoutReader);
        io:println("\n<< tools/list response:\n" + listToolsResponse);

        // 4. tools/call — fetch https://example.com
        JsonRpcOutbound callToolRequest = {
            id: 3,
            method: "tools/call",
            params: {
                name: "fetch",
                arguments: {url: "https://example.com", max_length: 500}
            }
        };
        check sendMessage(stdinWriter, message = callToolRequest);
        string callToolResponse = check readMessage(stdoutReader);
        io:println("\n<< tools/call response:\n" + callToolResponse);

        io:println("\nPOC successful: full MCP handshake + tool call over stdio.");
    } on fail error failure {
        destroyProcess(serverProcess);
        return failure;
    }

    destroyProcess(serverProcess);
}

# Serializes a JSON-RPC message and writes it as a single line to the child's stdin.
#
# + stdinWriter - Buffered writer wrapping the child process stdin
# + message - The JSON-RPC message to send
# + return - An error if the write fails
function sendMessage(handle stdinWriter, JsonRpcOutbound message) returns error? {
    string serializedMessage = message.toJsonString();
    io:println(">> " + serializedMessage);
    check writeString(stdinWriter, content = java:fromString(serializedMessage + "\n"));
    check flushWriter(stdinWriter);
}

# Blocks until one newline-delimited JSON-RPC message arrives on the child's stdout.
#
# + stdoutReader - Buffered reader wrapping the child process stdout
# + return - The raw JSON line, or an error on EOF / read failure
function readMessage(handle stdoutReader) returns string|error {
    while true {
        handle responseLine = check readLine(stdoutReader);
        if java:isNull(responseLine) {
            return error("Child process closed stdout (EOF) — server exited unexpectedly.");
        }
        string? responseText = java:toString(responseLine);
        if responseText is () {
            return error("Failed to convert response line to string.");
        }
        // Skip blank lines between newline-delimited messages.
        if responseText.trim().length() > 0 {
            return responseText;
        }
    }
}

// ---- Java interop bindings ----

function newArrayList() returns handle = @java:Constructor {
    'class: "java.util.ArrayList",
    paramTypes: []
} external;

function addToList(handle listHandle, handle element) returns boolean = @java:Method {
    name: "add",
    'class: "java.util.ArrayList",
    paramTypes: ["java.lang.Object"]
} external;

function newProcessBuilder(handle commandList) returns handle = @java:Constructor {
    'class: "java.lang.ProcessBuilder",
    paramTypes: ["java.util.List"]
} external;

function getInheritRedirect() returns handle = @java:FieldGet {
    name: "INHERIT",
    'class: "java.lang.ProcessBuilder$Redirect"
} external;

function redirectError(handle processBuilder, handle redirectTarget) returns handle = @java:Method {
    name: "redirectError",
    'class: "java.lang.ProcessBuilder",
    paramTypes: ["java.lang.ProcessBuilder$Redirect"]
} external;

function startProcess(handle processBuilder) returns handle|error = @java:Method {
    name: "start",
    'class: "java.lang.ProcessBuilder"
} external;

function getOutputStream(handle processHandle) returns handle = @java:Method {
    name: "getOutputStream",
    'class: "java.lang.Process"
} external;

function getInputStream(handle processHandle) returns handle = @java:Method {
    name: "getInputStream",
    'class: "java.lang.Process"
} external;

function destroyProcess(handle processHandle) = @java:Method {
    name: "destroy",
    'class: "java.lang.Process"
} external;

function newOutputStreamWriter(handle outputStream, handle charsetName) returns handle|error = @java:Constructor {
    'class: "java.io.OutputStreamWriter",
    paramTypes: ["java.io.OutputStream", "java.lang.String"]
} external;

function newBufferedWriter(handle writerHandle) returns handle = @java:Constructor {
    'class: "java.io.BufferedWriter",
    paramTypes: ["java.io.Writer"]
} external;

function writeString(handle writerHandle, handle content) returns error? = @java:Method {
    name: "write",
    'class: "java.io.Writer",
    paramTypes: ["java.lang.String"]
} external;

function flushWriter(handle writerHandle) returns error? = @java:Method {
    name: "flush",
    'class: "java.io.Writer"
} external;

function newInputStreamReader(handle inputStream, handle charsetName) returns handle|error = @java:Constructor {
    'class: "java.io.InputStreamReader",
    paramTypes: ["java.io.InputStream", "java.lang.String"]
} external;

function newBufferedReader(handle readerHandle) returns handle = @java:Constructor {
    'class: "java.io.BufferedReader",
    paramTypes: ["java.io.Reader"]
} external;

function readLine(handle readerHandle) returns handle|error = @java:Method {
    name: "readLine",
    'class: "java.io.BufferedReader"
} external;
