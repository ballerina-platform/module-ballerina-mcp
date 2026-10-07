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
const cached = new Client({ name: 'typescript-cached', version: '1' }, { versionNegotiation: { mode: { pin: '2026-07-28' } } });
try {
    await cached.connect(new StreamableHTTPClientTransport(new URL('/cached', baseUrl)));
    const first = await cached.listTools();
    assert.equal(first.ttlMs, 60000);
    assert.equal(first.cacheScope, 'public');
    const again = await cached.listTools();
    const refreshed = await cached.listTools(undefined, { cacheMode: 'refresh' });
    assert.equal(again.tools[0].description, first.tools[0].description, 'expected a cached tools/list');
    assert.notEqual(refreshed.tools[0].description, first.tools[0].description, 'expected a refetched tools/list');
    console.log('TypeScript cached tools/list PASS');
} finally {
    await cached.close();
}
