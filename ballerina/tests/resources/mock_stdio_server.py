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

Tools: "echo" echoes its arguments back; "cwd" returns the server's working directory.
"""
import json
import os
import sys
import time

EMIT_NOTIFICATION = os.environ.get("MOCK_EMIT_NOTIFICATION") == "1"
EMIT_BLANK_LINES = os.environ.get("MOCK_EMIT_BLANK_LINES") == "1"
RESPONSE_DELAY = float(os.environ.get("MOCK_RESPONSE_DELAY", "0"))
EXIT_AFTER_INITIALIZE = os.environ.get("MOCK_EXIT_AFTER_INITIALIZE") == "1"
PROTOCOL_VERSION = os.environ.get("MOCK_PROTOCOL_VERSION", "2025-06-18")
DELAY_ONLY_FIRST = os.environ.get("MOCK_DELAY_ONLY_FIRST") == "1"
STDERR_SPAM = os.environ.get("MOCK_STDERR_SPAM") == "1"


def send(payload):
    if EMIT_BLANK_LINES:
        sys.stdout.write("\n")
    sys.stdout.write(json.dumps(payload) + "\n")
    if EMIT_BLANK_LINES:
        sys.stdout.write("\n")
    sys.stdout.flush()


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
            continue  # notification — nothing to send back
        if RESPONSE_DELAY and (not DELAY_ONLY_FIRST or responses_sent == 0):
            time.sleep(RESPONSE_DELAY)
        responses_sent += 1
        if EMIT_NOTIFICATION:
            send({"jsonrpc": "2.0", "method": "notifications/tools/list_changed"})
        if method == "initialize":
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
