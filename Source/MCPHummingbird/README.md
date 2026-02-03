# MCPHummingbird

HTTP server adapter for [MCP](../MCP/README.md) using [Hummingbird](https://github.com/hummingbird-project/hummingbird), enabling local development and testing of MCP servers.

## Overview

MCPHummingbird provides a lightweight HTTP server for MCP development:

- **Local Development** - Test MCP servers without deploying to Lambda
- **HTTP Transport** - JSON-RPC over HTTP POST requests
- **Middleware Support** - Same middleware API as MCPLambda
- **CORS Support** - Automatic CORS headers for browser clients

## Quick Start

### Basic Server

```swift
import MCP
import MCPHummingbird
import Hummingbird

let server = Server()
    .addTool("add_numbers", inputType: AddInput.self, outputType: AddOutput.self) { request in
        return AddOutput(sum: request.input.a + request.input.b)
    }

let adapter = HummingbirdAdapter()
let app = adapter.createApp(
    server: server,
    configuration: .init(address: .hostname("0.0.0.0", port: 8080))
)

try await app.run()
```

### With Router

```swift
let fileServer = Server()
    .addTool("read_file", ...) { ... }

let dbServer = Server()
    .addTool("query", ...) { ... }

let router = HummingbirdRouter()
    .addServer(path: "/files", server: fileServer)
    .addServer(path: "/database", server: dbServer)

let adapter = HummingbirdAdapter()
let app = adapter.createApp(
    router: router,
    configuration: .init(address: .hostname("0.0.0.0", port: 8080))
)

try await app.run()
```

## Making Requests

Send JSON-RPC 2.0 requests via HTTP POST:

### Initialize

```bash
curl -X POST http://localhost:8080/files \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "initialize",
    "params": {},
    "id": 1
  }'
```

### List Tools

```bash
curl -X POST http://localhost:8080/files \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/list",
    "id": 2
  }'
```

### Call Tool

```bash
curl -X POST http://localhost:8080/files \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "read_file",
      "arguments": {"path": "/tmp/test.txt"}
    },
    "id": 3
  }'
```

### Read Resource

```bash
curl -X POST http://localhost:8080/files \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "resources/read",
    "params": {
      "uri": "file://config.json"
    },
    "id": 4
  }'
```

## Middleware

### Pre-Request Middleware

```swift
let loggingMiddleware = MiddlewareHelpers.from { (context: HummingbirdMCPContext, envelope: TransportEnvelope) in
    context.logger.info("MCP request: \(envelope.mcpRequest.method)")
    return .passthrough
}

let authMiddleware = MiddlewareHelpers.from { (context: HummingbirdMCPContext, envelope: TransportEnvelope) in
    guard let token = context.request.headers[.authorization] else {
        return .reject(MCPError(code: .invalidRequest, message: "Unauthorized"))
    }

    let userId = try await verifyToken(token)
    return .accept(metadata: ["userId": userId])
}

let adapter = HummingbirdAdapter()
    .usePreRequestMiddleware(loggingMiddleware)
    .usePreRequestMiddleware(authMiddleware)
```

### Post-Response Middleware

```swift
let timingMiddleware = PostResponseMiddlewareHelpers.from {
    (context: HummingbirdMCPContext, envelope: ResponseEnvelope<Response>) in

    var modified = envelope.response
    modified.headers[.init("X-Duration-Ms")!] = "\(Int(envelope.timing.duration * 1000))"
    return .accept(modified)
}

let adapter = HummingbirdAdapter()
    .usePostResponseMiddleware(timingMiddleware)
```

### Route-Specific Middleware

```swift
let router = HummingbirdRouter()
    .addServer(path: "/admin", server: adminServer) { route in
        route.usePreRequestMiddleware(adminAuthMiddleware)
    }
    .addServer(path: "/public", server: publicServer)  // No middleware
```

## HummingbirdMCPContext

Middleware has access to the Hummingbird request context:

```swift
struct HummingbirdMCPContext {
    let request: Hummingbird.Request      // HTTP request
    let context: BasicRequestContext       // Hummingbird context
    let logger: Logger                     // Logger instance
}
```

### Accessing in Middleware

```swift
let middleware = MiddlewareHelpers.from { (context: HummingbirdMCPContext, envelope: TransportEnvelope) in
    // Access HTTP headers
    let authHeader = context.request.headers[.authorization]
    let userAgent = context.request.headers[.userAgent]

    // Access request path
    let path = context.request.uri.path

    // Use logger
    context.logger.info("Processing request from \(userAgent ?? "unknown")")

    return .passthrough
}
```

## Simple Adapter

For quick setup without middleware:

```swift
import MCP
import MCPHummingbird

let server = Server()
    .addTool("hello", inputType: Empty.self) { _ in
        return .text("Hello, world!")
    }

let app = MCPHummingbirdSimpleAdapter.createApp(
    server: server,
    configuration: .init(address: .hostname("0.0.0.0", port: 8080))
)

try await app.run()
```

## CORS Support

The adapter automatically adds CORS headers:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

## Configuration

### Port and Host

```swift
let config = ApplicationConfiguration(
    address: .hostname("0.0.0.0", port: 8080)
)
```

### Unix Socket

```swift
let config = ApplicationConfiguration(
    address: .unixDomainSocket(path: "/tmp/mcp.sock")
)
```

## Testing

Use the adapter in integration tests:

```swift
import Testing
import MCPHummingbird
import HummingbirdTesting

@Test func toolExecution() async throws {
    let server = Server()
        .addTool("add", inputType: AddInput.self, outputType: AddOutput.self) { request in
            return AddOutput(sum: request.input.a + request.input.b)
        }

    let app = MCPHummingbirdSimpleAdapter.createApp(
        server: server,
        configuration: .init(address: .hostname("127.0.0.1", port: 0))
    )

    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/",
            method: .post,
            headers: [.contentType: "application/json"],
            body: ByteBuffer(string: """
                {
                    "jsonrpc": "2.0",
                    "method": "tools/call",
                    "params": {"name": "add", "arguments": {"a": 5, "b": 3}},
                    "id": 1
                }
                """)
        )

        #expect(response.status == .ok)
        // Verify response body contains sum: 8
    }
}
```

## Type Aliases

```swift
// Router configured for Hummingbird context
public typealias HummingbirdRouter = Router<HummingbirdMCPContext>
```

## Development Workflow

1. **Develop locally** with MCPHummingbird
2. **Test** using curl or HTTP client
3. **Deploy** to Lambda using MCPLambda (same server code)

```swift
// Same server works with both adapters
let server = Server()
    .addTool("my_tool", ...) { ... }

// Local development
#if DEBUG
let hbAdapter = HummingbirdAdapter()
let app = hbAdapter.createApp(server: server, configuration: ...)
try await app.run()
#else
// Production Lambda
let lambdaAdapter = LambdaAdapter()
let app = LambdaApp()
    .addMCP(key: "mcp", adapter: lambdaAdapter, server: server)
app.run(handlerKey: "mcp")
#endif
```

## Related Modules

- **[MCP](../MCP/README.md)** - Core MCP framework
- **[MCPLambda](../MCPLambda/README.md)** - Lambda adapter for production
- **MCPStdio** - Stdio adapter for Claude Desktop
