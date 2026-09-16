import assert from 'node:assert/strict';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';

const baseUrl = process.argv[2];
for (const mode of ['legacy', 'auto', { pin: '2026-07-28' }]) {
    const client = new Client({ name: 'typescript-interop', version: '1' }, { versionNegotiation: { mode } });
    try {
        await client.connect(new StreamableHTTPClientTransport(new URL('/mcp', baseUrl)));
        const result = await client.callTool({ name: 'add', arguments: { firstValue: 2, secondValue: 3 } });
        assert.equal(result.content[0].text, '5');
        console.log('TypeScript', JSON.stringify(mode), client.getNegotiatedProtocolVersion(), 'PASS');
    } finally {
        await client.close();
    }
}
const stateful = new Client({ name: 'typescript-stateful', version: '1' }, { versionNegotiation: { mode: 'auto' } });
try {
    await stateful.connect(new StreamableHTTPClientTransport(new URL('/stateful', baseUrl)));
    assert.equal(stateful.getNegotiatedProtocolVersion(), '2025-11-25');
    const first = await stateful.callTool({ name: 'sessionIdentity', arguments: {} });
    const second = await stateful.callTool({ name: 'sessionIdentity', arguments: {} });
    assert.equal(first.content[0].text, second.content[0].text);
    console.log('TypeScript required-session fallback PASS');
} finally {
    await stateful.close();
}
const modern = new Client({ name: 'typescript-modern', version: '1' }, { versionNegotiation: { mode: 'auto' } });
try {
    await modern.connect(new StreamableHTTPClientTransport(new URL('/modern', baseUrl)));
    const result = await modern.callTool({ name: 'scalar', arguments: {} });
    assert.equal(result.structuredContent, 42);
    console.log('TypeScript scalar result PASS');
} finally {
    await modern.close();
}
