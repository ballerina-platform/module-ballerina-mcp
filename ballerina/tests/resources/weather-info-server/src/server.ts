/**
 * Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { 
    Notification, 
    CallToolRequestSchema, 
    ListToolsRequestSchema, 
    LoggingMessageNotification, 
    ToolListChangedNotification, 
    JSONRPCNotification, 
    JSONRPCError, 
    InitializeRequestSchema 
} from "@modelcontextprotocol/sdk/types.js";
import { randomUUID } from "crypto";
import { Request, Response } from "express";

const SESSION_ID_HEADER_NAME = "mcp-session-id";
const JSON_RPC = "2.0";

export class MCPServer {
    server: Server;
    transports: {[sessionId: string]: StreamableHTTPServerTransport} = {};
    
    private toolInterval: NodeJS.Timeout | undefined;
    private singleGreetToolName = "single-greet";
    private multiGreetToolName = "multi-greet";

    constructor(server: Server) {
        this.server = server;
        this.setupTools();
    }

    async handleGetRequest(req: Request, res: Response) {
        console.log("get request received");
        
        const sessionId = req.headers['mcp-session-id'] as string | undefined;
        if (!sessionId || !this.transports[sessionId]) {
            res.status(400).json(this.createErrorResponse("Bad Request: invalid session ID or method."));
            return;
        }

        console.log(`Establishing SSE stream for session ${sessionId}`);
        const transport = this.transports[sessionId];
        await transport.handleRequest(req, res);
        await this.streamMessages(transport);
    }

    async handlePostRequest(req: Request, res: Response) {
        const sessionId = req.headers[SESSION_ID_HEADER_NAME] as string | undefined;

        console.log("post request received");
        console.log("body: ", req.body);

        try {
            // Reuse existing transport
            if (sessionId && this.transports[sessionId]) {
                const transport = this.transports[sessionId];
                await transport.handleRequest(req, res, req.body);
                return;
            }

            // Create new transport
            if (!sessionId && this.isInitializeRequest(req.body)) {
                const transport = new StreamableHTTPServerTransport({
                    sessionIdGenerator: () => randomUUID(),
                });

                await this.server.connect(transport);
                await transport.handleRequest(req, res, req.body);

                const newSessionId = transport.sessionId;
                if (newSessionId) {
                    this.transports[newSessionId] = transport;
                }
                return;
            }

            res.status(400).json(this.createErrorResponse("Bad Request: invalid session ID or method."));
        } catch (error) {
            console.error('Error handling MCP request:', error);
            res.status(500).json(this.createErrorResponse("Internal server error."));
        }
    }

    const forecastText = forecast.map(day =>
      `${day.day}: ${day.temperature}°C, ${day.condition}, ${day.humidity}% humidity`
    ).join('\n');

    return {
      content: [
        {
          type: 'text',
          text: `3-Day Forecast for ${weather.city}, ${weather.country}:
${forecastText}`,
        },
      ],
    };
  }
);

// Register city information tool
server.registerTool(
  'get-city-info',
  {
    title: 'Get City Information',
    description: 'Get general information about supported cities',
    inputSchema: z.object({}) as any,
  },
  async (): Promise<CallToolResult> => {
    const cities = Object.values(weatherData).map(weather =>
      `${weather.city}, ${weather.country}`
    ).join('\n• ');

    return {
      content: [
        {
          type: 'text',
          text: `Supported Cities:
• ${cities}

Use the city names (case-insensitive) with the weather tools.`,
        },
      ],
    };
  }
);

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;
const app = express();

app.use(express.json());
app.use(cors({
  origin: '*',
  exposedHeaders: ["Mcp-Session-Id"]
}));

// MCP handler - creates new transport for each request
// WARNING: Uses a single global McpServer instance with connect/close per request.
// Concurrent requests may interfere with each other.
app.post('/mcp', async (req: Request, res: Response) => {
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined
  });

  try {
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (error) {
    console.error('Error handling MCP request:', error);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: {
          code: -32603,
          message: 'Internal server error',
        },
        id: req.body?.id ?? null,
      });
    }
  } finally {
    // Reset connection state to allow next request
    try {
      await server.close();
    } catch {
      // Ignore cleanup errors
    }
  }
});

app.listen(PORT, () => {
  console.log(`Weather Info Server listening on port ${PORT}`);
  console.log(`MCP endpoint: http://localhost:${PORT}/mcp`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down Weather Info Server...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('Shutting down Weather Info Server...');
  process.exit(0);
});
