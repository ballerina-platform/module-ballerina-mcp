"""Serve the Ballerina client fixture using FastMCP or the official Python SDK."""
import sys
from typing import Annotated

import uvicorn
from pydantic import Field

if sys.argv[1] == 'fastmcp':
    from fastmcp import FastMCP
    server = FastMCP('fastmcp-interop')
else:
    from mcp.server import CacheHint
    from mcp.server.mcpserver import MCPServer
    server = MCPServer('python-sdk-interop', cache_hints={'tools/list': CacheHint(ttl_ms=60_000, scope='public')})

tool_listings = 0


@server.tool()
def add(firstValue: int, secondValue: int) -> int:
    return firstValue + secondValue


@server.tool()
def echo(region: Annotated[str, Field(json_schema_extra={'x-mcp-header': 'Region'})]) -> str:
    return region


@server.tool()
def listCount() -> int:
    return tool_listings


def count_tool_listings(app):
    # Modern requests name their method in a header, so listings are counted without reading the body.
    async def counted_app(scope, receive, send):
        global tool_listings
        if scope['type'] == 'http' and dict(scope['headers']).get(b'mcp-method') == b'tools/list':
            tool_listings += 1
        await app(scope, receive, send)
    return counted_app


if sys.argv[1] == 'fastmcp':
    app = server.http_app(transport='http', json_response=False)
else:
    app = server.streamable_http_app(json_response=False)
uvicorn.run(count_tool_listings(app), host='127.0.0.1', port=int(sys.argv[2]))
