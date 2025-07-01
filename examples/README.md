# Ballerina MCP Module Examples

## Overview

Explore a collection of examples demonstrating how the Ballerina MCP module enables you to build Model Context Protocol (MCP) servers and clients efficiently. These examples highlight various tools and capabilities, showcasing how MCP can be leveraged for different AI-driven tasks.

## Examples

### MCP Weather Server

**Location:** `servers/mcp-weather-server/`

A sample MCP server that exposes weather-related tools.

**Features:**
- Current weather tool - Get weather conditions for a location
- Weather forecast tool - Get multi-day weather forecast
- Uses fake/mock weather data for demonstration

**Available Tools:**
- `getCurrentWeather(location: string)` - Returns current weather
- `getWeatherForecast(location: string, days: int)` - Returns weather forecast

**How to run:**
```bash
cd servers/mcp-weather-server
bal run
```

Server starts at `http://localhost:9090/mcp`

### MCP Weather Client Demo

**Location:** `clients/mcp-weather-client-demo/`

A sample MCP client that connects to the weather server, discovers tools, and calls them.

**Features:**
- Connects to MCP server
- Lists available tools
- Calls tools with sample parameters
- Demonstrates proper client cleanup

**How to run:**
```bash
# Start the server first
cd servers/mcp-weather-server
bal run

# In another terminal, run the client
cd clients/mcp-weather-client-demo
bal run
```
