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

import express, { Request, Response } from 'express';
import cors from 'cors';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';

interface WeatherInfo {
  city: string;
  country: string;
  temperature: number;
  condition: string;
  humidity: number;
  windSpeed: number;
}

interface ForecastDay {
  day: string;
  temperature: number;
  condition: string;
  humidity: number;
}

// Create a stateless MCP server for weather information
const server = new McpServer({
  name: 'weather-info-server',
  version: '1.0.0'
}, {
  capabilities: {
    logging: {},
    tools: {}
  }
});

// Mock weather data for different cities
const weatherData: Record<string, WeatherInfo> = {
  'new-york': {
    city: 'New York',
    country: 'USA',
    temperature: 22,
    condition: 'Partly Cloudy',
    humidity: 65,
    windSpeed: 12
  },
  'london': {
    city: 'London',
    country: 'UK',
    temperature: 18,
    condition: 'Rainy',
    humidity: 80,
    windSpeed: 8
  },
  'tokyo': {
    city: 'Tokyo',
    country: 'Japan',
    temperature: 25,
    condition: 'Sunny',
    humidity: 55,
    windSpeed: 6
  },
  'colombo': {
    city: 'Colombo',
    country: 'Sri Lanka',
    temperature: 30,
    condition: 'Tropical',
    humidity: 75,
    windSpeed: 10
  }
};

// Register weather information tool
server.registerTool(
  'get-weather',
  {
    title: 'Get Weather Information',
    description: 'Get current weather information for a specified city',
    inputSchema: {
      city: z.string().describe('City name (supported: new-york, london, tokyo, colombo)'),
    },
  },
  async ({ city }: { city: string }): Promise<CallToolResult> => {
    const cityKey = city.toLowerCase().replace(/\s+/g, '-');
    const weather = weatherData[cityKey];

    if (!weather) {
      return {
        content: [
          {
            type: 'text',
            text: `Weather information not available for "${city}". Supported cities: New York, London, Tokyo, Colombo`,
          },
        ],
        isError: true,
      };
    }

    return {
      content: [
        {
          type: 'text',
          text: `Weather in ${weather.city}, ${weather.country}:
🌡️ Temperature: ${weather.temperature}°C
🌤️ Condition: ${weather.condition}
💧 Humidity: ${weather.humidity}%
💨 Wind Speed: ${weather.windSpeed} km/h`,
        },
      ],
    };
  }
);

// Register weather forecast tool
server.registerTool(
  'get-forecast',
  {
    title: 'Get Weather Forecast',
    description: 'Get 3-day weather forecast for a specified city',
    inputSchema: {
      city: z.string().describe('City name (supported: new-york, london, tokyo, colombo)'),
    },
  },
  async ({ city }: { city: string }): Promise<CallToolResult> => {
    const cityKey = city.toLowerCase().replace(/\s+/g, '-');
    const weather = weatherData[cityKey];

    if (!weather) {
      return {
        content: [
          {
            type: 'text',
            text: `Weather forecast not available for "${city}". Supported cities: New York, London, Tokyo, Colombo`,
          },
        ],
        isError: true,
      };
    }

    // Generate mock forecast based on current weather
    const forecast: ForecastDay[] = [];
    for (let i = 1; i <= 3; i++) {
      const tempVariation = Math.floor(Math.random() * 6) - 3; // -3 to +3 degrees
      const conditions = ['Sunny', 'Partly Cloudy', 'Cloudy', 'Rainy'];
      const randomCondition = conditions[Math.floor(Math.random() * conditions.length)];

      forecast.push({
        day: `Day +${i}`,
        temperature: weather.temperature + tempVariation,
        condition: randomCondition,
        humidity: weather.humidity + (Math.floor(Math.random() * 20) - 10)
      });
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
    inputSchema: {},
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

// Stateless MCP handler - creates new transport for each request
app.post('/mcp', async (req: Request, res: Response) => {
  try {

    // Create a new transport for each request (stateless)
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined
    });

    // Connect server to transport
    await server.connect(transport);

    // Handle the request
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
        id: req.body?.id || null,
      });
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
