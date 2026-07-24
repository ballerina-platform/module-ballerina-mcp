#!/usr/bin/env python3
"""Mock MCP stdio server used by the stdio transport tests.

Speaks newline-delimited JSON-RPC on stdin/stdout. Misbehavior modes are
enabled via environment variables:

  MOCK_EMIT_NOTIFICATION=1    emit a notification before every response
  MOCK_EMIT_BLANK_LINES=1     emit blank lines around every response
  MOCK_RESPONSE_DELAY=<secs>  sleep before responding
  MOCK_EXIT_AFTER_INITIALIZE=1  exit right after answering initialize
  MOCK_PROTOCOL_VERSION=<v>   protocol version reported by initialize
  MOCK_DELAY_ONLY_FIRST=1     apply MOCK_RESPONSE_DELAY to the first response only
  MOCK_STDERR_SPAM=1          write ~2MB to stderr at startup
  MOCK_EMIT_IDLE_NOTIFICATION=1 emit a notification after receiving notifications/initialized
  MOCK_CONCURRENT_RESPONSES=1 process tools/call requests concurrently and respond out of order
  MOCK_CONCURRENT_REQUEST_TARGET=<n> wait for n concurrent tools/call requests before responding
  MOCK_CLOSE_STDIN_AFTER_INITIALIZE=1  close stdin (read end) around the initialize
                              response but stay alive, so the client's write of
                              notifications/initialized fails with a broken pipe
  MOCK_FLOOD_NOTIFICATIONS=<n>  emit n notifications on stdout just before the
                              initialize response (used to exceed the client's
                              bounded stdout queue and exercise backpressure)
  MOCK_EXIT_AFTER_FLOOD=1      exit after flooding notifications, before initialize responds

Tools: "echo" echoes its arguments back; "cwd" returns the server's working directory.
"""
import json
import os
import sys
import threading
import time

EMIT_NOTIFICATION = os.environ.get("MOCK_EMIT_NOTIFICATION") == "1"
EMIT_BLANK_LINES = os.environ.get("MOCK_EMIT_BLANK_LINES") == "1"
RESPONSE_DELAY = float(os.environ.get("MOCK_RESPONSE_DELAY", "0"))
EXIT_AFTER_INITIALIZE = os.environ.get("MOCK_EXIT_AFTER_INITIALIZE") == "1"
PROTOCOL_VERSION = os.environ.get("MOCK_PROTOCOL_VERSION", "2025-06-18")
DELAY_ONLY_FIRST = os.environ.get("MOCK_DELAY_ONLY_FIRST") == "1"
STDERR_SPAM = os.environ.get("MOCK_STDERR_SPAM") == "1"
EMIT_IDLE_NOTIFICATION = os.environ.get("MOCK_EMIT_IDLE_NOTIFICATION") == "1"
CONCURRENT_RESPONSES = os.environ.get("MOCK_CONCURRENT_RESPONSES") == "1"
CONCURRENT_REQUEST_TARGET = int(os.environ.get("MOCK_CONCURRENT_REQUEST_TARGET", "0"))
CONCURRENT_REQUEST_CONDITION = threading.Condition()
CONCURRENT_REQUEST_COUNT = 0
SEND_LOCK = threading.Lock()
CLOSE_STDIN_AFTER_INITIALIZE = os.environ.get("MOCK_CLOSE_STDIN_AFTER_INITIALIZE") == "1"
FLOOD_NOTIFICATIONS = int(os.environ.get("MOCK_FLOOD_NOTIFICATIONS", "0"))
EXIT_AFTER_FLOOD = os.environ.get("MOCK_EXIT_AFTER_FLOOD") == "1"


def send(payload):
    try:
        with SEND_LOCK:
            if EMIT_BLANK_LINES:
                sys.stdout.write("\n")
            sys.stdout.write(json.dumps(payload) + "\n")
            if EMIT_BLANK_LINES:
                sys.stdout.write("\n")
            sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)


def send_concurrent_tool_response(message):
    global CONCURRENT_REQUEST_COUNT
    with CONCURRENT_REQUEST_CONDITION:
        CONCURRENT_REQUEST_COUNT += 1
        if CONCURRENT_REQUEST_COUNT >= CONCURRENT_REQUEST_TARGET:
            CONCURRENT_REQUEST_CONDITION.notify_all()
        while CONCURRENT_REQUEST_COUNT < CONCURRENT_REQUEST_TARGET:
            CONCURRENT_REQUEST_CONDITION.wait()
    arguments = message.get("params", {}).get("arguments", {})
    call_index = arguments.get("callIndex", 0)
    # Reverse the completion order so the client must correlate by ID, not arrival order.
    time.sleep((24 - int(call_index)) * 0.005)
    send({
        "jsonrpc": "2.0",
        "id": message["id"],
        "result": {
            "content": [{"type": "text", "text": json.dumps(arguments)}],
            "isError": False,
        },
    })


def main():
    if STDERR_SPAM:
        spam_chunk = "x" * 65536
        for _ in range(32):
            sys.stderr.write(spam_chunk)
        sys.stderr.flush()
    responses_sent = 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        message = json.loads(line)
        method = message.get("method")
        message_id = message.get("id")
        if message_id is None:
            if EMIT_IDLE_NOTIFICATION and method == "notifications/initialized":
                send({"jsonrpc": "2.0", "method": "notifications/resources/list_changed"})
            continue  # notification — nothing to send back
        if CONCURRENT_RESPONSES and method == "tools/call":
            threading.Thread(target=send_concurrent_tool_response, args=(message,), daemon=True).start()
            continue
        if RESPONSE_DELAY and (not DELAY_ONLY_FIRST or responses_sent == 0):
            time.sleep(RESPONSE_DELAY)
        responses_sent += 1
        if EMIT_NOTIFICATION:
            send({"jsonrpc": "2.0", "method": "notifications/tools/list_changed"})
        if method == "initialize":
            for _ in range(FLOOD_NOTIFICATIONS):
                send({"jsonrpc": "2.0", "method": "notifications/message"})
            if EXIT_AFTER_FLOOD:
                return
            if CLOSE_STDIN_AFTER_INITIALIZE:
                # Close the read end at the OS level before responding so that, by
                # the time the client reads this response and writes
                # notifications/initialized, its write fails with a broken pipe
                # (no exit race). os.close on the fd is more forceful than
                # sys.stdin.close(), which can leave the descriptor lingering.
                os.close(0)
            send({
                "jsonrpc": "2.0",
                "id": message_id,
                "result": {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "mock-stdio-server", "version": "0.1.0"},
                },
            })
            if EXIT_AFTER_INITIALIZE:
                return
            if CLOSE_STDIN_AFTER_INITIALIZE:
                # Stay alive (stdout open) so termination is driven by the client.
                while True:
                    time.sleep(0.1)
        elif method == "tools/list":
            send({
                "jsonrpc": "2.0",
                "id": message_id,
                "result": {
                    "tools": [{
                        "name": "echo",
                        "description": "Echoes back the given arguments.",
                        "inputSchema": {"type": "object"},
                    }],
                },
            })
        elif method == "tools/call":
            tool_name = message.get("params", {}).get("name")
            arguments = message.get("params", {}).get("arguments", {})
            result_text = os.getcwd() if tool_name == "cwd" else json.dumps(arguments)
            send({
                "jsonrpc": "2.0",
                "id": message_id,
                "result": {
                    "content": [{"type": "text", "text": result_text}],
                    "isError": False,
                },
            })
        else:
            send({
                "jsonrpc": "2.0",
                "id": message_id,
                "error": {"code": -32601, "message": "Method not found"},
            })


if __name__ == "__main__":
    main()
