# Ballerina MCP Module Examples

## Overview

Explore a collection of examples demonstrating how the Ballerina MCP module enables you to build Model Context Protocol (MCP) servers and clients efficiently. These examples showcase all three session management modes (AUTO, STATELESS, STATEFUL) and various implementation patterns.

## Examples

### MCP Weather Server (AUTO Mode)

**Location:** `servers/mcp-weather-server/`

A sample MCP server demonstrating the Basic Service pattern with AUTO session mode for weather-related tools.

**Features:**
- Current weather tool - Get weather conditions for a location
- Weather forecast tool - Get multi-day weather forecast
- Uses AUTO session mode (automatically determined based on client behavior)
- Automatic tool discovery and schema generation
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

### MCP Crypto Server (STATELESS Mode)

**Location:** `servers/mcp-crypto-server/`

A sample MCP server demonstrating the Advanced Service pattern with STATELESS session mode for cryptographic operations.

**Features:**
- Hash text tool - Generate hash for text using various algorithms
- Base64 encode/decode tool - Encode or decode text using Base64
- Uses STATELESS session mode (no session management, each request is independent)
- Manual tool registration with Advanced Service pattern
- Supports multiple hash algorithms (MD5, SHA1, SHA256, SHA384, SHA512)

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

### MCP Shopping Cart Server (STATEFUL Mode)

**Location:** `servers/mcp-shopping-server/`

A comprehensive example demonstrating STATEFUL session mode with persistent shopping cart functionality.

**Features:**
- Session-based shopping cart management
- Persistent state across multiple requests within a session
- Demonstrates proper session parameter usage as first parameter
- Basic Service pattern with automatic tool discovery
- Thread-safe session storage

**Available Tools:**
- `addToCart(session: mcp:Session, productName: string, price: decimal)` - Add item to cart
- `viewCart(session: mcp:Session)` - View current cart contents
- `clearCart(session: mcp:Session)` - Clear all items from cart

**How to run:**
```bash
cd servers/mcp-shopping-server
bal run
```

Server starts at `http://localhost:9092/mcp`

### MCP Shopping Client Demo

**Location:** `clients/mcp-shopping-client-demo/`

A comprehensive client example demonstrating session-based interactions with parallel session execution.

**Features:**
- Connects to stateful shopping cart server
- Demonstrates proper session initialization and management
- Shows parallel session execution using Ballerina workers
- Illustrates session isolation with concurrent Alice and Bob sessions
- Error handling and proper client cleanup

**How to run:**
```bash
# Start the server first
cd servers/mcp-shopping-server
bal run

# In another terminal, run the client
cd clients/mcp-shopping-client-demo
bal run
```

## Common Testing Workflow

### Running All Examples

To test all examples systematically:

1. **Start all servers** (in separate terminals):
```bash
# Terminal 1 - Weather Server (AUTO mode)
cd servers/mcp-weather-server && bal run

# Terminal 2 - Crypto Server (STATELESS mode)
cd servers/mcp-crypto-server && bal run

# Terminal 3 - Shopping Server (STATEFUL mode)
cd servers/mcp-shopping-server && bal run
```

2. **Run corresponding clients** (in additional terminals):
```bash
# Test weather client
cd clients/mcp-weather-client-demo && bal run

# Test crypto client
cd clients/mcp-crypto-client-demo && bal run

# Test shopping client (with parallel sessions)
cd clients/mcp-shopping-client-demo && bal run
```

### Expected Server Ports

- **Weather Server**: `http://localhost:9090/mcp` (AUTO mode)
- **Crypto Server**: `http://localhost:9091/mcp` (STATELESS mode)
- **Shopping Server**: `http://localhost:9092/mcp` (STATEFUL mode)

### Common Build Commands

```bash
# Build all examples
./gradlew clean build

# Build without tests
./gradlew clean build -x test -x check

# Build and publish to local central
./gradlew clean build -x test -x check -PpublishToLocalCentral=true
```
