# Testing Guide - SimpleMathServer Example

This guide shows how to manually test the SimpleMathServer running via MCPExample.

## Prerequisites

- Swift 6.0 or later
- `curl` for HTTP testing
- `jq` (optional, for pretty JSON formatting)

## Step 1: Build the Project

```bash
swift build
```

## Step 2: Start the HTTP Server

In one terminal, start the server:

```bash
swift run MCPExample http
```

You should see:
```
🧮 Simple Math MCP Server
📊 Mode: http

Features:
  • Tool: add_numbers - Adds two numbers together
  • Resource: math://constants/pi - Returns π
  • Prompt: explain_math - Explains math concepts

🌐 Starting HTTP server on http://localhost:8080

Test with curl:
  curl -X POST http://localhost:8080/math \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'
```

## Step 3: Test the Server

In another terminal, run these commands:

### Test 1: List Available Tools

```bash
curl -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'
```

**Expected Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "result": {
    "tools": [
      {
        "name": "add_numbers",
        "description": "Adds two numbers together and returns the sum",
        "inputSchema": {
          "type": "object",
          "properties": {
            "a": {"type": "number"},
            "b": {"type": "number"}
          },
          "required": ["a", "b"]
        }
      }
    ]
  }
}
```

### Test 2: Call the add_numbers Tool

```bash
curl -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "add_numbers",
      "arguments": {"a": 5.5, "b": 3.2}
    },
    "id": 2
  }'
```

**Expected Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "2",
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"sum\":8.7}"
      }
    ]
  }
}
```

### Test 3: List Available Resources

```bash
curl -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "resources/list", "id": 3}'
```

**Expected Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "3",
  "result": {
    "resources": [
      {
        "uri": "math://constants/pi",
        "name": "pi_constant",
        "description": "The mathematical constant pi (π) - the ratio of a circle's circumference to its diameter",
        "mimeType": "text/plain"
      }
    ]
  }
}
```

### Test 4: Read the Pi Resource

```bash
curl -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "resources/read",
    "params": {
      "uri": "math://constants/pi"
    },
    "id": 4
  }'
```

**Expected Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "4",
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

### Test 5: List Available Prompts

```bash
curl -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "prompts/list", "id": 5}'
```

**Expected Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "5",
  "result": {
    "prompts": [
      {
        "name": "explain_math",
        "description": "Generates a prompt to request an explanation of a mathematical concept",
        "arguments": [
          {
            "name": "concept",
            "description": "The mathematical concept to explain (e.g., 'derivatives', 'fibonacci sequence', 'pythagorean theorem')",
            "required": true
          }
        ]
      }
    ]
  }
}
```

### Test 6: Get the explain_math Prompt

```bash
curl -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "prompts/get",
    "params": {
      "name": "explain_math",
      "arguments": {"concept": "calculus"}
    },
    "id": 6
  }'
```

**Expected Response:**
```json
{
  "jsonrpc": "2.0",
  "id": "6",
  "result": {
    "messages": [
      {
        "role": "user",
        "content": {
          "type": "text",
          "text": "Please explain the mathematical concept: calculus"
        }
      }
    ]
  }
}
```

## Automated Test Script

Run all tests with the provided script:

```bash
./test-math-server.sh
```

This will execute all the above tests and show the results.

## Testing Stdio Mode

To test stdio mode (for Claude Desktop integration):

```bash
# This will run in stdio mode - type MCP JSON-RPC requests and see responses
swift run MCPExample stdio
```

Example session:
```
🧮 Simple Math MCP Server
📊 Mode: stdio

Features:
  • Tool: add_numbers - Adds two numbers together
  • Resource: math://constants/pi - Returns π
  • Prompt: explain_math - Explains math concepts

🔌 Running in stdio mode (for Claude Desktop integration)
💡 Add this to your Claude Desktop config:
...

# Type this and press Enter:
{"jsonrpc": "2.0", "method": "tools/list", "id": 1}

# You'll see the response immediately
```

## Verifying CORS Headers

The HTTP adapter automatically adds CORS headers. Verify with:

```bash
curl -i -X POST http://localhost:8080/math \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'
```

Look for these headers in the response:
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

## What's Next?

Now that you've verified SimpleMathServer works via HTTP:

1. **Write adapter tests** - Use SimpleMathServer in MCPHummingbird tests
2. **Test Lambda adapter** - Deploy SimpleMathServer to AWS Lambda
3. **Build your own server** - Use SimpleMathServer as a template

See `Source/SimpleMathServer/SimpleMathServer.swift` for the simple, well-documented implementation.
