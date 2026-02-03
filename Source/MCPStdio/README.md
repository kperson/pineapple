# MCPStdio

Standard I/O adapter for [MCP](../MCP/README.md), enabling integration with Claude Desktop, IDE extensions, and command-line MCP clients.

## Overview

MCPStdio communicates via stdin/stdout using JSON-RPC 2.0, the standard transport for MCP clients:

- **Claude Desktop Integration** - Run as an MCP server in Claude Desktop
- **IDE Extensions** - Integrate with VS Code, JetBrains, and other editors
- **CLI Tools** - Build command-line MCP clients and servers
- **Middleware Support** - Environment validation, logging, and request modification

## Quick Start

### Basic Server

```swift
import MCP
import MCPStdio

let server = Server()
    .addTool("read_file", inputType: FileInput.self, outputType: FileOutput.self) { request in
        let contents = try String(contentsOfFile: request.input.path)
        return FileOutput(contents: contents)
    }

let adapter = StdioAdapter(server: server)
try await adapter.run()
```

### With Router

```swift
let fileServer = Server()
    .addTool("read_file", ...) { ... }

let dbServer = Server()
    .addTool("query", ...) { ... }

let router = StdioRouter()
    .addServer(path: "/files/{userId}", server: fileServer)
    .addServer(path: "/db/{tenant}", server: dbServer)

let adapter = StdioAdapter(router: router)

// Use MCP_PATH environment variable or explicit path
try await adapter.run(mcpPath: "/files/user-123")
```

## Claude Desktop Integration

Configure in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "/path/to/MCPExample",
      "args": ["stdio"],
      "env": {
        "MCP_PATH": "/files/default",
        "API_KEY": "your-api-key"
      }
    }
  }
}
```

### Using Swift Package

```json
{
  "mcpServers": {
    "my-server": {
      "command": "swift",
      "args": ["run", "--package-path", "/path/to/your/package", "YourExecutable", "stdio"]
    }
  }
}
```

## Path Resolution

The route path is determined by (in priority order):

1. `mcpPath` parameter passed to `run()`
2. `MCP_PATH` environment variable
3. Root path `/` (default)

```swift
// Explicit path
try await adapter.run(mcpPath: "/files/user-123")

// From environment
// export MCP_PATH="/db/tenant-456"
try await adapter.run()

// Default to "/"
try await adapter.run()
```

## Middleware

### Pre-Request Middleware

Validate environment and modify requests:

```swift
let envMiddleware = MiddlewareHelpers.from { (context: StdioMCPContext, envelope: TransportEnvelope) in
    // Validate required environment variables
    guard let apiKey = context.environment["API_KEY"] else {
        return .reject(MCPError(code: .invalidRequest, message: "Missing API_KEY"))
    }

    // Add to metadata for handlers
    return .accept(metadata: ["apiKey": apiKey])
}

let loggingMiddleware = MiddlewareHelpers.from { (context: StdioMCPContext, envelope: TransportEnvelope) in
    // Log to stderr (stdout is reserved for MCP responses)
    fputs("[\(context.processId)] \(envelope.mcpRequest.method)\n", stderr)
    return .passthrough
}

let adapter = StdioAdapter(server: server)
    .usePreRequestMiddleware(envMiddleware)
    .usePreRequestMiddleware(loggingMiddleware)
```

### Post-Response Middleware

Log timing and modify responses:

```swift
let timingMiddleware = PostResponseMiddlewareHelpers.from {
    (context: StdioMCPContext, envelope: ResponseEnvelope<TransportResponse>) in

    fputs("Request completed in \(envelope.timing.duration)s\n", stderr)
    return .passthrough
}

let adapter = StdioAdapter(server: server)
    .usePostResponseMiddleware(timingMiddleware)
```

### Route-Specific Middleware

```swift
let router = StdioRouter()
    .addServer(path: "/admin", server: adminServer) { route in
        route.usePreRequestMiddleware(adminValidationMiddleware)
    }
    .addServer(path: "/public", server: publicServer)
```

## StdioMCPContext

Middleware has access to process context:

```swift
struct StdioMCPContext {
    let environment: [String: String]  // Process environment variables
    let processId: Int                   // Current process ID
    let routePath: String                // Resolved MCP route path
}
```

### Accessing in Middleware

```swift
let middleware = MiddlewareHelpers.from { (context: StdioMCPContext, envelope: TransportEnvelope) in
    // Access environment
    let home = context.environment["HOME"]
    let apiKey = context.environment["API_KEY"]

    // Access process info
    let pid = context.processId

    // Access route
    let path = context.routePath

    return .passthrough
}
```

## Simple Adapter

For quick setup without middleware:

```swift
import MCP
import MCPStdio

let server = Server()
    .addTool("hello", inputType: Empty.self) { _ in
        return .text("Hello, world!")
    }

let adapter = MCPStdioSimpleAdapter(server: server)
try await adapter.run()
```

## Protocol Details

### Request Format

Each line from stdin is a JSON-RPC 2.0 request:

```json
{"jsonrpc":"2.0","method":"tools/call","params":{"name":"read_file","arguments":{"path":"/tmp/test.txt"}},"id":1}
```

### Response Format

Responses are written to stdout as single-line JSON:

```json
{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"file contents"}]}}
```

### Error Handling

Parse errors and exceptions become JSON-RPC errors:

```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"Invalid file path"}}
```

## Logging

Use stderr for logging (stdout is reserved for MCP responses):

```swift
// In middleware or handlers
fputs("Debug message\n", stderr)

// Or use swift-log with stderr handler
var logger = Logger(label: "my-server")
// Configure to write to stderr
```

## Testing

The adapter supports dependency injection for testing:

```swift
import Testing
@testable import MCPStdio

@Test func toolExecution() async throws {
    // Create mock I/O
    let input = MockInputReader(lines: [
        #"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"add","arguments":{"a":5,"b":3}},"id":1}"#
    ])
    let output = MockOutputWriter()

    let server = Server()
        .addTool("add", inputType: AddInput.self, outputType: AddOutput.self) { request in
            return AddOutput(sum: request.input.a + request.input.b)
        }

    let router = StdioRouter().addServer(server: server)
    let adapter = StdioAdapter(
        router: router,
        inputReader: input,
        outputWriter: output
    )

    try await adapter.run()

    // Verify output
    let response = output.lines.first
    #expect(response?.contains("\"sum\":8") == true)
}
```

## Building an Executable

Create a main.swift that handles stdio mode:

```swift
import Foundation
import MCP
import MCPStdio

@main
struct MyMCPServer {
    static func main() async throws {
        let server = Server()
            .addTool("my_tool", ...) { ... }

        if CommandLine.arguments.contains("stdio") {
            // Run in stdio mode for Claude Desktop
            let adapter = StdioAdapter(server: server)
            try await adapter.run()
        } else {
            print("Usage: MyMCPServer stdio")
        }
    }
}
```

## Type Aliases

```swift
// Router configured for stdio context
public typealias StdioRouter = Router<StdioMCPContext>
```

## Related Modules

- **[MCP](../MCP/README.md)** - Core MCP framework
- **[MCPLambda](../MCPLambda/README.md)** - Lambda adapter for serverless
- **[MCPHummingbird](../MCPHummingbird/README.md)** - HTTP adapter for local development
