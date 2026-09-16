"""Serve the Ballerina client fixture using FastMCP or the official Python SDK."""
import sys
from typing import Annotated

from pydantic import Field

if sys.argv[1] == 'fastmcp':
    from fastmcp import FastMCP
    server = FastMCP('fastmcp-interop')
else:
    from mcp.server.mcpserver import MCPServer
    server = MCPServer('python-sdk-interop')


@server.tool()
def add(firstValue: int, secondValue: int) -> int:
    return firstValue + secondValue


@server.tool()
def echo(region: Annotated[str, Field(json_schema_extra={'x-mcp-header': 'Region'})]) -> str:
    return region


server.run(transport='http' if sys.argv[1] == 'fastmcp' else 'streamable-http',
           host='127.0.0.1', port=int(sys.argv[2]), json_response=False)
