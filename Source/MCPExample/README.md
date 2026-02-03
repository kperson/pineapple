# MCP Example - SimpleMathServer

A simple example demonstrating how to run an MCP server using the SimpleMathServer module with different transport adapters (HTTP via Hummingbird or Stdio).

## Quick Start

### Run HTTP Server

```bash
swift run MCPExample http
```

The server will start on `http://localhost:8080` with the math server available at `/math`.

### Run Stdio Mode (for Claude Desktop)

```bash
swift run MCPExample stdio
```

This mode is designed for integration with Claude Desktop or other MCP clients that use stdio transport.

## Features

The SimpleMathServer provides three MCP features:

### 1. Tool: `add_numbers`
Adds two numbers together.

**Example:**
```bash
curl -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "add_numbers",
      "arguments": {"a": 5, "b": 3}
    },
    "id": 1
  }'
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"sum\":8.0}"
      }
    ]
  }
}
```

### 2. Resource: `math://constants/pi`
Returns the value of π (pi).

**Example:**
```bash
curl -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "resources/read",
    "params": {
      "uri": "math://constants/pi"
    },
    "id": 2
  }'
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "contents": [
      {
        "uri": "math://constants/pi",
        "mimeType": "text/plain",
        "text": "3.14159"
      }
    ]
  }
}
```

### 3. Prompt: `explain_math`
Generates a prompt to request an explanation of a mathematical concept.

**Example:**
```bash
curl -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "prompts/get",
    "params": {
      "name": "explain_math",
      "arguments": {"concept": "derivatives"}
    },
    "id": 3
  }'
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "messages": [
      {
        "role": "user",
        "content": {
          "type": "text",
          "text": "Please explain the mathematical concept: derivatives"
        }
      }
    ]
  }
}
```

## Testing

A test script is provided in the repository root:

```bash
# Start the server in one terminal
swift run MCPExample http

# Run tests in another terminal
./test-math-server.sh
```

## Claude Desktop Integration

To integrate with Claude Desktop, add this to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "simple-math": {
      "command": "swift",
      "args": ["run", "--package-path", "/path/to/pineapple", "MCPExample", "stdio"]
    }
  }
}
```

Replace `/path/to/pineapple` with the actual path to this repository.

## Architecture

```
MCPExample (executable)
  ↓
SimpleMathServer (library)
  ↓
MCP Framework
  ↓
Transport Adapters:
  • MCPHummingbird (HTTP)
  • MCPStdio (stdio)
```

## Use Cases

This example serves multiple purposes:

1. **Learning**: Simple, easy-to-understand MCP server
2. **Testing**: Used by adapter tests to verify HTTP/stdio functionality
3. **Template**: Starting point for building your own MCP servers
4. **Debugging**: Quick way to test MCP clients and protocol compliance
