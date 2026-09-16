"""Run with fastmcp==4.0.0b5 and mcp==2.2.0 against the interop-server fixture."""
import sys

import anyio
from fastmcp import Client as FastMCPClient
from mcp.client import Client as SDKClient


async def main():
    base_url = sys.argv[1].rstrip('/')
    for client_type in (SDKClient, FastMCPClient):
        for mode in ('legacy', 'auto', '2026-07-28'):
            async with client_type(base_url + '/mcp', mode=mode) as client:
                result = await client.call_tool('add', {'firstValue': 2, 'secondValue': 3})
                assert result.content[0].text == '5', result
                print(client_type.__module__, mode, client.protocol_version, 'PASS')
        async with client_type(base_url + '/stateful', mode='auto') as client:
            first = await client.call_tool('sessionIdentity', {})
            second = await client.call_tool('sessionIdentity', {})
            assert client.protocol_version == '2025-11-25'
            assert first.content[0].text == second.content[0].text
            print(client_type.__module__, 'required-session fallback', 'PASS')
    async with SDKClient(base_url + '/modern', mode='auto') as client:
        result = await client.call_tool('scalar', {})
        assert result.structured_content == 42, result
        print('Python SDK scalar result PASS')


anyio.run(main)
