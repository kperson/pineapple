# MCP

A Swift framework for building [Model Context Protocol](https://spec.modelcontextprotocol.io/) servers that expose tools, resources, and prompts to AI agents.

## Overview

MCP provides a fluent interface for building MCP-compliant servers with:

- **Tools** - Execute functions with typed input/output schemas
- **Resources** - Serve data via URI pattern matching
- **Prompts** - Define conversation templates for AI agents
- **Middleware** - Add authentication, logging, and other cross-cutting concerns
- **Routing** - Route requests to different servers by path pattern

## Quick Start

### Basic Server with Tools

```swift
import MCP

// Define typed input/output
@JSONSchema
struct AddInput: Codable {
    let a: Double
    let b: Double
}

@JSONSchema
struct AddOutput: Codable {
    let sum: Double
}

// Create server with typed tool
let server = Server()
    .addTool(
        "add_numbers",
        description: "Add two numbers together",
        inputType: AddInput.self,
        outputType: AddOutput.self
    ) { request in
        return AddOutput(sum: request.input.a + request.input.b)
    }
```

### Server with Resources

```swift
let server = Server()
    .addResource(
        "file://{path}",
        name: "files",
        description: "Read files by path",
        mimeType: "text/plain"
    ) { request in
        let path = request.resourceParams.string("path") ?? ""
        let contents = try String(contentsOfFile: path)
        return .init(name: path, data: .text(contents))
    }
```

### Server with Prompts

```swift
let server = Server()
    .addPrompt(
        "code_review",
        description: "Generate a code review prompt",
        arguments: [
            PromptArgument(name: "code", description: "Code to review", required: true),
            PromptArgument(name: "language", description: "Programming language")
        ]
    ) { request in
        let code = try request.argumentOrThrow("code")
        let language = request.arguments.string("language") ?? "unknown"

        return PromptHandlerResponse(messages: [
            PromptMessage(role: .system, content: .text("You are a code reviewer.")),
            PromptMessage(role: .user, content: .text("Review this \(language) code:\n\(code)"))
        ])
    }
```

## Tools

Tools are executable functions that AI agents can invoke. Define them with typed inputs and outputs for automatic JSON Schema generation.

### Typed Input/Output (Recommended)

```swift
@JSONSchema
struct FileInput: Codable {
    let path: String
    let encoding: String?
}

@JSONSchema
struct FileOutput: Codable {
    let contents: String
    let size: Int
}

server.addTool(
    "read_file",
    description: "Read a file from disk",
    inputType: FileInput.self,
    outputType: FileOutput.self
) { request in
    let contents = try String(contentsOfFile: request.input.path)
    return FileOutput(contents: contents, size: contents.count)
}
```

### Rich Content Response

Return images, audio, or formatted text:

```swift
server.addTool(
    "generate_chart",
    description: "Generate a chart image",
    inputType: ChartInput.self
) { request in
    let imageData = generateChart(request.input.data)
    return .image(data: imageData, mimeType: "image/png")
}
```

### Accessing Path Parameters

When using routers, access URL path parameters in handlers:

```swift
// Router path: "/customers/{customerId}/tools"
server.addTool("get_data", inputType: DataInput.self) { request in
    let customerId = request.pathParams?.string("customerId") ?? "unknown"
    // Load customer-specific data
    return DataOutput(...)
}
```

## Resources

Resources serve data via URI pattern matching. Use them to expose files, database records, or API data.

### Static Resources

```swift
server.addResource(
    "config://settings",
    name: "settings",
    description: "Application settings",
    mimeType: "application/json"
) { request in
    return .init(name: "settings", data: .text("{\"theme\": \"dark\"}"))
}
```

### Dynamic Resources with URI Parameters

```swift
server.addResource(
    "db://{database}/tables/{table}",
    name: "database_tables",
    description: "Read database table data",
    mimeType: "application/json"
) { request in
    let database = request.resourceParams.string("database") ?? ""
    let table = request.resourceParams.string("table") ?? ""

    let data = try queryTable(database: database, table: table)
    return .init(name: "\(database).\(table)", data: .text(data))
}
```

### Binary Resources

```swift
server.addResource(
    "image://{id}",
    name: "images",
    description: "Image files",
    mimeType: "image/png"
) { request in
    let id = request.resourceParams.string("id") ?? ""
    let imageData = try loadImage(id: id)
    return .init(name: id, data: .blob(imageData))
}
```

## Prompts

Prompts define conversation templates that AI agents can use to generate structured interactions.

```swift
server.addPrompt(
    "summarize",
    description: "Generate a summarization prompt",
    arguments: [
        PromptArgument(name: "text", description: "Text to summarize", required: true),
        PromptArgument(name: "style", description: "Summary style (brief, detailed)")
    ]
) { request in
    let text = try request.argumentOrThrow("text")
    let style = request.arguments.string("style") ?? "brief"

    return PromptHandlerResponse(messages: [
        PromptMessage(
            role: .user,
            content: .text("Summarize this text in a \(style) style:\n\n\(text)")
        )
    ])
}
```

## Routing

Use `Router` to route requests to different servers based on URL path patterns.

### Basic Routing

```swift
let fileServer = Server()
    .addTool("read_file", ...) { ... }

let dbServer = Server()
    .addTool("query", ...) { ... }

let router = Router<MyContext>()
    .addServer(path: "/files", server: fileServer)
    .addServer(path: "/database", server: dbServer)
```

### Path Parameters

Extract parameters from URL paths for multi-tenant applications:

```swift
let router = Router<MyContext>()
    .addServer(path: "/{customerId}/files", server: fileServer)
    .addServer(path: "/{customerId}/db", server: dbServer)

// In handlers:
// request.pathParams?.string("customerId") returns the customer ID
```

### Route-Specific Middleware

Add middleware that only runs for specific routes:

```swift
router.addServer(path: "/admin/{tenant}", server: adminServer) { route in
    route.usePreRequestMiddleware(authMiddleware)
    route.usePreRequestMiddleware(adminCheckMiddleware)
}
```

### Route Matching Order

Routes match in **registration order** (first match wins). Register specific routes before wildcards:

```swift
// Good: Specific before wildcard
router.addServer(path: "/users/admin", server: adminServer)  // Matches first
router.addServer(path: "/users/{id}", server: userServer)    // Matches other /users/*

// Bad: Wildcard catches everything
router.addServer(path: "/users/{id}", server: userServer)    // Matches ALL /users/*
router.addServer(path: "/users/admin", server: adminServer)  // Never reached!
```

## Middleware

Middleware intercepts requests before they reach handlers, enabling authentication, logging, and request modification.

### Pre-Request Middleware

Runs before the MCP server processes requests:

```swift
let authMiddleware = MiddlewareHelpers.from { (context: MyContext, envelope: TransportEnvelope) in
    guard let token = extractToken(context) else {
        return .reject(MCPError(code: .invalidRequest, message: "Unauthorized"))
    }

    let userId = try await verifyToken(token)
    return .accept(metadata: ["userId": userId])
}

// Add to adapter or route
adapter.usePreRequestMiddleware(authMiddleware)
```

### Post-Response Middleware

Runs after the response is generated but before it's sent:

```swift
let loggingMiddleware = PostResponseMiddlewareHelpers.from { context, envelope, response, timing in
    print("Request took \(timing.duration)s")
    return .passthrough
}

adapter.usePostResponseMiddleware(loggingMiddleware)
```

### Middleware Response Types

- **`.accept(metadata:)`** - Continue with optional metadata added to context
- **`.passthrough`** - Continue without modification
- **`.reject(error:)`** - Stop processing and return error to client

## JSON Schema Generation

Use the `@JSONSchema` macro to automatically generate JSON Schema from Swift types:

```swift
@JSONSchema
struct UserInput: Codable {
    let name: String
    let age: Int
    let email: String?  // Optional fields are nullable in schema
}

// Generates:
// {
//   "type": "object",
//   "properties": {
//     "name": {"type": "string"},
//     "age": {"type": "integer"},
//     "email": {"anyOf": [{"type": "string"}, {"type": "null"}]}
//   },
//   "required": ["name", "age"]
// }
```

For manual schema definition, use `JSONSchema`:

```swift
let schema = JSONSchema.object(
    properties: [
        "name": .string(),
        "count": .integer(),
        "tags": .array(of: .string())
    ],
    required: ["name", "count"]
)
```

## OpenAI Integration

MCP tools can be used directly with OpenAI's function calling API without a transport adapter. The `Server` class provides two methods that bridge MCP tool definitions to OpenAI's format.

### Getting Tool Definitions

Use `openAIToolDefinitions()` to get all registered tools in OpenAI's expected format:

```swift
let server = Server()
    .addTool("get_weather", description: "Get current weather",
             inputType: WeatherInput.self, outputType: WeatherOutput.self) { request in
        let weather = try await fetchWeather(city: request.input.city)
        return WeatherOutput(temperature: weather.temp, condition: weather.condition)
    }

// Build OpenAI API request
var requestBody: [String: Any] = [
    "model": "gpt-4o",
    "messages": messages
]
requestBody["tools"] = server.openAIToolDefinitions()

// Returns:
// [
//   {
//     "type": "function",
//     "function": {
//       "name": "get_weather",
//       "description": "Get current weather",
//       "parameters": {
//         "type": "object",
//         "properties": { "city": { "type": "string" } },
//         "required": ["city"]
//       },
//       "strict": true
//     }
//   }
// ]
```

### Executing Tool Calls

When OpenAI returns a `tool_calls` response, use `executeTool(name:argumentsJSON:)` to dispatch it:

```swift
// OpenAI response contains:
// tool_calls: [{ "name": "get_weather", "arguments": "{\"city\": \"London\"}" }]

for toolCall in toolCalls {
    let result = try await server.executeTool(
        name: toolCall.name,
        argumentsJSON: toolCall.arguments
    )
    // result: "{\"temperature\":15,\"condition\":\"cloudy\"}"

    // Send result back to OpenAI as a tool response message
    messages.append(["role": "tool", "tool_call_id": toolCall.id, "content": result])
}
```

### Complete OpenAI Chat Loop

```swift
import MCP

@JSONSchema
struct CityInput: Codable {
    let city: String
}

@JSONSchema
struct WeatherOutput: Codable {
    let temperature: Double
    let condition: String
}

// Define tools once using MCP Server
let server = Server()
    .addTool("get_weather", description: "Get weather for a city",
             inputType: CityInput.self, outputType: WeatherOutput.self) { request in
        return WeatherOutput(temperature: 22.0, condition: "sunny")
    }

// Use server.openAIToolDefinitions() in your API request body
// Use server.executeTool(name:argumentsJSON:) when OpenAI returns tool_calls
// No hardcoded schemas, no manual argument deserialization
```

This approach gives you:
- **Single source of truth** — tool schemas are generated from Swift types via `@JSONSchema`
- **Generic execution** — no `if/else` chains per tool type
- **Type safety** — input deserialization is handled by `Codable` conformance
- **Reusability** — the same `Server` can serve MCP clients (via transport adapters) and OpenAI simultaneously

## Transport Adapters

MCP servers need a transport adapter to communicate with MCP clients:

| Adapter | Use Case | Module |
|---------|----------|--------|
| [MCPLambda](../MCPLambda/README.md) | AWS Lambda via API Gateway | `MCPLambda` |
| [MCPHummingbird](../MCPHummingbird/README.md) | HTTP server for local dev | `MCPHummingbird` |
| [MCPStdio](../MCPStdio/README.md) | Claude Desktop, CLI tools | `MCPStdio` |

### Lambda Deployment

```swift
import MCP
import MCPLambda
import LambdaApp

let server = Server()
    .addTool("my_tool", ...) { ... }

let app = LambdaApp()
    .addMCP(key: "mcp", server: server)

app.run(handlerKey: "mcp")
```

### HTTP Server (Development)

```swift
import MCP
import MCPHummingbird
import Hummingbird

let server = Server()
    .addTool("my_tool", ...) { ... }

let adapter = HummingbirdAdapter()
let app = adapter.createApp(server: server, configuration: .init(address: .hostname("0.0.0.0", port: 8080)))

try await app.run()
```

### Stdio (Claude Desktop)

```swift
import MCP
import MCPStdio

let server = Server()
    .addTool("my_tool", ...) { ... }

let adapter = StdioAdapter(server: server)
try await adapter.run()
```

## Error Handling

MCP uses JSON-RPC 2.0 error codes:

```swift
// In a tool handler
throw MCPError(code: .invalidParams, message: "Missing required field: path")

// Common error codes:
// .parseError (-32700) - Invalid JSON
// .invalidRequest (-32600) - Invalid JSON-RPC request
// .methodNotFound (-32601) - Method not found
// .invalidParams (-32602) - Invalid parameters
// .internalError (-32603) - Internal server error
```

## Testing

```swift
import Testing
@testable import MCP

@Test func toolExecution() async throws {
    let server = Server()
        .addTool("add", inputType: AddInput.self, outputType: AddOutput.self) { request in
            return AddOutput(sum: request.input.a + request.input.b)
        }

    // Create test request
    let request = Request(
        jsonrpc: "2.0",
        id: .int(1),
        method: "tools/call",
        params: ["name": "add", "arguments": ["a": 5, "b": 3]]
    )

    let envelope = TransportEnvelope(mcpRequest: request, routePath: "/")
    let response = try await server.handleRequest(envelope, pathParams: nil, logger: Logger(label: "test"))

    // Verify response
    // ...
}
```

## Architecture

```
  ┌─────────────────┐     ┌─────────────────────┐
  │   OpenAI API    │     │   Transport Layer   │
  │  (Direct Call)  │     │  (Lambda/HTTP/Stdio)│
  └────────┬────────┘     └──────────┬──────────┘
           │                         │
           │  openAIToolDefinitions()│
           │  executeTool()          │  handleRequest()
           │                         │
           └────────────┬────────────┘
                        │
             ┌──────────▼──────────┐
             │     MCP Server      │
             │  (Tool Registry)    │
             └──────────┬──────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
 ┌──────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
 │    Tools    │ │  Resources  │ │   Prompts   │
 └─────────────┘ └─────────────┘ └─────────────┘
```

## Dependencies

- **JSONValueCoding** - JSON value encoding/decoding
- **swift-log** - Structured logging

## Related Modules

- **[MCPLambda](../MCPLambda/README.md)** - AWS Lambda adapter
- **[MCPHummingbird](../MCPHummingbird/README.md)** - Hummingbird HTTP adapter
- **[MCPStdio](../MCPStdio/README.md)** - Standard I/O adapter for CLI tools
- **JSONSchemaDSL** - JSON Schema generation

## Resources

- [Model Context Protocol Specification](https://spec.modelcontextprotocol.io/)
- [MCP GitHub Repository](https://github.com/modelcontextprotocol)
