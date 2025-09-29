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
- Connects to MCP server using StreamableHttpClient
- Demonstrates client initialization with server info
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

### MCP Crypto Server

**Location:** `servers/mcp-crypto-server/`

A sample MCP server that exposes cryptographic tools using the advanced service pattern.

**Features:**
- Hash text tool - Generate hash for text using various algorithms
- Base64 encode/decode tool - Encode or decode text using Base64
- Supports multiple hash algorithms (MD5, SHA1, SHA256, SHA384, SHA512)
- Uses advanced service pattern with manual tool registration

**Available Tools:**
- `hashText` - Generate hash for text using various algorithms
- `encodeBase64` - Encode or decode text using Base64

**How to run:**
```bash
cd servers/mcp-crypto-server
bal run
```

Server starts at `http://localhost:9091/mcp`

### MCP Crypto Client Demo

**Location:** `clients/mcp-crypto-client-demo/`

A sample MCP client that connects to the crypto server, discovers tools, and calls them.

**Features:**
- Connects to MCP crypto server using StreamableHttpClient
- Demonstrates client initialization with server info
- Lists available tools
- Tests hash generation with different algorithms
- Tests Base64 encoding and decoding operations
- Demonstrates proper client cleanup

**How to run:**
```bash
# Start the server first
cd servers/mcp-crypto-server
bal run

# In another terminal, run the client
cd clients/mcp-crypto-client-demo
bal run
```

### MCP Session Management Demo

**Location:** `servers/mcp-session-demo/` and `clients/mcp-session-client-demo/`

A comprehensive example demonstrating the different session management modes in MCP.

**Server Features:**
- **Stateful Service** (Port 9090): Maintains session state with key-value storage
- **Stateless Service** (Port 9091): Independent request processing without sessions
- Demonstrates when to use each mode

**Client Features:**
- Shows proper stateful client initialization and session management
- Demonstrates stateless client usage without initialization
- Error handling and edge cases for both modes

**Available Tools:**

*Stateful Service:*
- `storeValue(key: string, value: anydata)` - Store data in session
- `getValue(key: string)` - Retrieve data from session
- `listKeys()` - List all session keys

*Stateless Service:*
- `calculate(operation: string, a: decimal, b: decimal)` - Math operations
- `getCurrentTime()` - Get server time
- `getRandomQuote()` - Get motivational quotes

**How to run:**
```bash
# Start the session demo server
cd servers/mcp-session-demo
bal run

# In another terminal, run the session client demo
cd clients/mcp-session-client-demo
bal run
```
