# Interop fixtures

Manual checks of the Ballerina client and server against the official Python and TypeScript SDKs and FastMCP.
Build the module first so `target/ballerina-runtime` holds the current `ballerina/mcp`, then install the peers:

```bash
npm ci
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

SDK clients against the Ballerina server (`interop-server`):

```bash
(cd ../interop-server && ../../target/ballerina-runtime/bin/bal run -- -CinteropPort=9310)
.venv/bin/python python_client.py http://127.0.0.1:9310
node typescript_client.mjs http://127.0.0.1:9310
```

The Ballerina client (`interop-client`) against SDK servers:

```bash
.venv/bin/python python_server.py mcp 9320       # or: python_server.py fastmcp 9321, node typescript_server.mjs 9322
(cd ../interop-client && ../../target/ballerina-runtime/bin/bal run -- -CinteropUrl=http://127.0.0.1:9320/mcp)
```

Each check prints `PASS`; a failed check exits with an error.

Form elicitation runs on the modern protocol in both directions through a `bookTable` tool that asks how many seats to book and keeps the guest's name in its request state:

- The Ballerina client answers it against each SDK server. The Python SDK and FastMCP servers encrypt their request state, so those round trips show the client echoes the state as an opaque token.
- The Python SDK and TypeScript clients answer it through their elicitation callbacks against the Ballerina server's `/elicitation` service, which signs its request state. Each client accepts once and declines once.
