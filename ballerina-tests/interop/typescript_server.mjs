import http from 'node:http';
import { McpServer, acceptedContent, createMcpHandler, inputRequired, inputResponse } from '@modelcontextprotocol/server';
import * as z from 'zod';

let toolListings = 0;

const handler = createMcpHandler(() => {
    const server = new McpServer({ name: 'typescript-interop', version: '1' }, {
        cacheHints: { 'tools/list': { ttlMs: 60000, cacheScope: 'public' } }
    });
    server.registerTool('add', {
        inputSchema: z.object({ firstValue: z.number().int(), secondValue: z.number().int() })
    }, async ({ firstValue, secondValue }) => ({ content: [{ type: 'text', text: String(firstValue + secondValue) }] }));
    server.registerTool('echo', {
        inputSchema: z.object({ region: z.string().meta({ 'x-mcp-header': 'Region' }) })
    }, async ({ region }) => ({ content: [{ type: 'text', text: region }] }));
    server.registerTool('listCount', { inputSchema: z.object({}) },
        async () => ({ content: [{ type: 'text', text: String(toolListings) }] }));
    server.registerTool('bookTable', { inputSchema: z.object({ name: z.string() }) }, async ({ name }, ctx) => {
        const answer = inputResponse(ctx.mcpReq.inputResponses, 'seats');
        const state = ctx.mcpReq.requestState();
        if (state === undefined || answer.kind !== 'elicit') {
            return inputRequired({
                inputRequests: {
                    seats: inputRequired.elicit({
                        message: `How many seats for ${name}?`,
                        requestedSchema: { type: 'object', properties: { seats: { type: 'integer' } }, required: ['seats'] }
                    })
                },
                requestState: name
            });
        }
        if (state !== name) throw new Error('Request state was altered');
        const content = acceptedContent(ctx.mcpReq.inputResponses, 'seats');
        const text = content ? `booked ${content.seats} for ${name}` : `not booked: ${answer.action}`;
        return { content: [{ type: 'text', text }] };
    });
    return server;
}, { responseMode: 'sse' });

http.createServer(async (request, response) => {
    try {
        // Modern requests name their method in a header, so listings are counted without reading the body.
        if (request.headers['mcp-method'] === 'tools/list') toolListings++;
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        const body = ['GET', 'HEAD'].includes(request.method) ? undefined : Buffer.concat(chunks);
        const result = await handler.fetch(new Request(`http://127.0.0.1:${process.argv[2]}${request.url}`, {
            method: request.method, headers: request.headers, body
        }));
        response.writeHead(result.status, Object.fromEntries(result.headers));
        if (result.body) {
            for await (const chunk of result.body) response.write(chunk);
        }
        response.end();
    } catch (error) {
        console.error(error);
        response.writeHead(500).end();
    }
}).listen(Number(process.argv[2]), '127.0.0.1');
