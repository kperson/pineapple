# MCP Implementation Plan

## Completed Features
- ✅ Swift 6 Concurrency Issues: Resolved JSONSchema Sendable conformance and macro-generated static properties
- ✅ Request Payload Structure Refactoring: Consolidated MCPServer handler parameters into single MCPHandlerRequest payload structure
- ✅ Context-Injected Logging Implementation: Added swift-log Logger integration with context-specific injection from stdio, Hummingbird, and Lambda environments
- ✅ Handler Signature Simplification: Updated all MCP handlers from `(MCPContext, T, PathParams?)` to `(MCPHandlerRequest<T>)` format
- ✅ Example File Migration: Updated MacroExample.swift to demonstrate new request structure and logger usage
- ✅ Test Suite: All tests passing with no warnings

## Current Implementation: Authorization Middleware

### Core Types
```swift
enum AuthorizationResult<Context> {
    case allowed(context: Context)
    case denied(reason: String)
}

// Use existing request type aliases with auth context
typealias MCPToolRequest<T> = MCPHandlerRequest<T, AuthContext>
typealias MCPResourceRequest<T> = MCPHandlerRequest<T, AuthContext>
typealias MCPPromptRequest<T> = MCPHandlerRequest<T, AuthContext>

protocol MCPAuthorizer {
    associatedtype AuthContext
    
    func authorizeTool<T>(_ request: MCPToolRequest<T>) async throws -> AuthorizationResult<AuthContext>
    func authorizeResource<T>(_ request: MCPResourceRequest<T>) async throws -> AuthorizationResult<AuthContext>
    func authorizePrompt<T>(_ request: MCPPromptRequest<T>) async throws -> AuthorizationResult<AuthContext>
}

struct NoOpAuthorizer: MCPAuthorizer {
    typealias AuthContext = Void
    // Always allows all requests
}
```

### Enhanced Request Context
```swift
struct MCPHandlerRequest<Input, AuthContext> {
    let context: MCPContext
    let input: Input
    let pathParams: PathParams?
    let logger: Logger
    let authContext: AuthContext // Strongly typed, no casting needed
}
```

### Generic MCPServer
```swift
class MCPServer<AuthContext> {
    private let authorizer: any MCPAuthorizer
    
    func withAuthorization<A: MCPAuthorizer>(_ authorizer: A) -> MCPServer<A.AuthContext>
}
```

### Request Processing Flow
1. Parse MCP request from JSON
2. **Run authorization** based on MCP method:
   - `tools/call` → `authorizeTool(MCPToolRequest<T>)`
   - `resources/read|list` → `authorizeResource(MCPResourceRequest<T>)`
   - `prompts/get|list` → `authorizePrompt(MCPPromptRequest<T>)`
3. **On authorization failure**: Return JSON-RPC error response immediately
4. **On authorization success**: Create `MCPHandlerRequest` with typed auth context
5. Execute handler with authorized context

### Usage Patterns
```swift
// Simple case - no auth needed
let server = MCPServer<Void>()

// With custom authorization
let server = MCPServer<UserContext>()
    .withAuthorization(MyAuthorizer())

// Handlers get strongly-typed auth context
.addTool("secure-tool", inputType: MyInput.self) { request in
    let userContext = request.authContext // No casting!
    // ... handler logic
}
```

## TODOs

### Phase 1: Authorization Foundation ✅ COMPLETED
- ✅ Implement `AuthorizationResult<Context>` enum
- ✅ Implement `MCPAuthorizer` protocol with separate methods for tools/resources/prompts
- ✅ Implement `NoOpAuthorizer` default implementation
- ✅ Update `MCPHandlerRequest` to include `AuthContext` generic parameter
- ✅ Update existing request type aliases to use auth context
- ✅ All tests passing with authorization foundation

### Phase 2: MCPServer Integration
- [ ] Make `MCPServer` generic over `AuthContext`
- [ ] Add `withAuthorization()` method to MCPServer
- [ ] Update request processing pipeline to run authorization after JSON parsing
- [ ] Implement authorization routing (tools/resources/prompts)
- [ ] Add JSON-RPC error responses for authorization failures

### Phase 3: Backward Compatibility
- [ ] Ensure existing handlers work without modification
- [ ] Update all example files to demonstrate authorization usage
- [ ] Add comprehensive authorization tests
- [ ] Update documentation with authorization examples

### Phase 4: Metrics Collection ✅ COMPLETED
- ✅ Implement `MCPMetricsCollector` protocol
- ✅ Implement `NoOpMetricsCollector` default implementation
- ✅ Add metrics collector to `MCPHandlerRequest`
- ✅ Add `withMetrics()` method to MCPServer
- ✅ Insert automatic metrics collection at all pipeline points
- ✅ Add comprehensive metrics tests
- ✅ Maintain backward compatibility with existing code

#### Automatic Metrics Implemented
- **Request Metrics**: `mcp.requests.total` counter, `mcp.request.duration` histogram
- **Error Metrics**: `mcp.errors.total` counter with error type and method tags
- **Handler Access**: Custom metrics available via `request.metrics` in all handlers

#### Usage Patterns Working
```swift
// Simple case - no metrics (uses NoOpMetricsCollector)
let server = MCPServer()

// With metrics
let server = MCPServer()
    .withMetrics(MyMetricsCollector())

// Handlers can access metrics for custom business metrics
.addTool("process", inputType: Input.self) { request in
    request.metrics.increment("files.processed", tags: ["type": "pdf"])
    // ... handler logic
}
```

## Design Principles
- **Progressive Complexity**: Start simple, add auth when needed
- **Type Safety**: No casting required, strongly-typed auth context
- **Backward Compatibility**: Existing code works unchanged
- **Implementer Choice**: Framework doesn't prescribe auth mechanisms
- **Zero Config**: Default to allowing all requests for simple use cases
