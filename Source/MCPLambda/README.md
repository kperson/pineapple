# MCPLambda

Bridges [MCP](../MCP/README.md) servers to AWS Lambda via API Gateway, enabling serverless deployment of MCP-compliant AI tool servers.

## Overview

MCPLambda connects MCP servers to AWS Lambda's execution environment:

- **API Gateway Integration** - Translates API Gateway requests/responses to MCP JSON-RPC
- **Middleware Support** - Authentication, logging, and request modification
- **Multi-Tenant Routing** - Path parameters for customer/tenant isolation
- **CORS Support** - Automatic CORS headers for browser clients

## Quick Start

### Simple Server (No Middleware)

```swift
import MCP
import MCPLambda
import LambdaApp

let server = Server()
    .addTool("read_file", inputType: FileInput.self, outputType: FileOutput.self) { request in
        let contents = try String(contentsOfFile: request.input.path)
        return FileOutput(contents: contents)
    }

let app = LambdaApp()
    .addMCP(key: "mcp", server: server)

app.run(handlerKey: "mcp")
```

### With Middleware

```swift
import MCP
import MCPLambda
import LambdaApp

// Authentication middleware
let authMiddleware = MiddlewareHelpers.from { (context: LambdaMCPContext, envelope: TransportEnvelope) in
    guard let token = context.apiGatewayRequest.headers["Authorization"] else {
        return .reject(MCPError(code: .invalidRequest, message: "Unauthorized"))
    }

    let userId = try await verifyToken(token)
    return .accept(metadata: ["userId": userId])
}

// Build adapter with middleware
let adapter = LambdaAdapter()
    .usePrequestMiddleware(authMiddleware)

let server = Server()
    .addTool("get_data", inputType: DataInput.self) { request in
        let userId = request.context.metadata["userId"] as? String
        // Load user-specific data
        return DataOutput(...)
    }

let app = LambdaApp()
    .addMCP(key: "mcp", adapter: adapter, server: server)

app.run(handlerKey: "mcp")
```

## Architecture

```
API Gateway → Lambda → LambdaAdapter → Middleware Chain → MCP Router → Server → Handler
                      ← CORS Headers ← JSON-RPC Response ←
```

The adapter:
1. Parses API Gateway request body as JSON-RPC 2.0 MCP request
2. Builds `TransportEnvelope` with route path and metadata
3. Executes middleware chain (auth, logging, etc.)
4. Routes to appropriate MCP server
5. Converts MCP response to API Gateway response with CORS headers

## Multi-Server Routing

Route requests to different servers based on URL path:

```swift
let fileServer = Server()
    .addTool("read_file", ...) { ... }
    .addTool("write_file", ...) { ... }

let dbServer = Server()
    .addTool("query", ...) { ... }
    .addTool("execute", ...) { ... }

let router = LambdaRouter()
    .addServer(path: "/{customerId}/files", server: fileServer)
    .addServer(path: "/{customerId}/database", server: dbServer)

let adapter = LambdaAdapter()
    .usePrequestMiddleware(authMiddleware)

let app = LambdaApp()
    .addMCP(key: "mcp", adapter: adapter, router: router)
```

### Path Parameter Access

Access URL path parameters in handlers:

```swift
// Router path: "/{customerId}/files"
// Request URL: "/acme-corp/files"

server.addTool("list_files", inputType: ListInput.self) { request in
    let customerId = request.pathParams?.string("customerId")  // "acme-corp"
    return listFilesForCustomer(customerId)
}
```

## LambdaMCPContext

Middleware and handlers have access to Lambda execution context:

```swift
struct LambdaMCPContext {
    let lambdaContext: LambdaContext      // Request ID, deadline, ARN, logger
    let apiGatewayRequest: APIGatewayRequest  // Headers, path, query params
}
```

### Accessing Context in Middleware

```swift
let middleware = MiddlewareHelpers.from { (context: LambdaMCPContext, envelope: TransportEnvelope) in
    // Lambda metadata
    let requestId = context.lambdaContext.requestId
    let timeRemaining = context.lambdaContext.deadline.timeIntervalSinceNow

    // API Gateway request
    let authHeader = context.apiGatewayRequest.headers["Authorization"]
    let userAgent = context.apiGatewayRequest.headers["User-Agent"]

    // Cognito identity (if using API Gateway authorizer)
    let userId = context.apiGatewayRequest.requestContext.authorizer?.claims?["sub"]

    return .accept(metadata: ["requestId": requestId])
}
```

## Middleware

### Pre-Request Middleware

Runs before MCP server processes requests:

```swift
// Logging middleware
let loggingMiddleware = MiddlewareHelpers.from { (context: LambdaMCPContext, envelope: TransportEnvelope) in
    context.lambdaContext.logger.info("MCP \(envelope.mcpRequest.method)")
    return .passthrough
}

// Rate limiting middleware
let rateLimitMiddleware = MiddlewareHelpers.from { (context: LambdaMCPContext, envelope: TransportEnvelope) in
    let clientIP = context.apiGatewayRequest.requestContext.identity?.sourceIp ?? "unknown"

    if isRateLimited(clientIP) {
        return .reject(MCPError(code: .invalidRequest, message: "Rate limit exceeded"))
    }

    return .passthrough
}

let adapter = LambdaAdapter()
    .usePrequestMiddleware(loggingMiddleware)
    .usePrequestMiddleware(rateLimitMiddleware)
```

### Post-Response Middleware

Runs after response is generated:

```swift
let timingMiddleware = PostResponseMiddlewareHelpers.from {
    (context: LambdaMCPContext, envelope: TransportEnvelope,
     response: APIGatewayResponse, timing: RequestTiming) in

    var modified = response
    modified.headers?["X-Request-ID"] = context.lambdaContext.requestId
    modified.headers?["X-Duration-Ms"] = "\(Int(timing.duration * 1000))"
    return .accept(modified)
}

let adapter = LambdaAdapter()
    .usePostResponseMiddleware(timingMiddleware)
```

### Route-Specific Middleware

Add middleware that only runs for specific routes:

```swift
let router = LambdaRouter()
    .addServer(path: "/admin/{tenant}", server: adminServer) { route in
        route.usePreRequestMiddleware(adminAuthMiddleware)
        route.usePreRequestMiddleware(auditLogMiddleware)
    }
    .addServer(path: "/public/tools", server: publicServer)  // No middleware
```

## APIGatewayRouter Integration

Mount MCP alongside regular HTTP handlers:

```swift
let mcpRouter = LambdaRouter()
    .addServer(path: "/{tenant}/files", server: fileServer)

let apiRouter = APIGatewayRouter()
    .mount("/health") { ctx, req, path in
        return APIGatewayResponse(statusCode: .ok, body: "OK")
    }
    .mount("/api/v1") { ctx, req, path in
        return handleRestAPI(ctx, req, path)
    }
    .mountMCP("/mcp", adapter: LambdaAdapter(), router: mcpRouter)

let app = LambdaApp()
    .addAPIGateway(key: "api", router: apiRouter)
```

### Path Rewriting

When mounted at a prefix, the prefix is stripped before MCP routing:

```
Mount: "/mcp"
Request: "/mcp/tenant/files"
MCP Router sees: "/tenant/files"
```

## CORS Support

The adapter automatically adds CORS headers to all responses:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

## Error Handling

Errors are converted to JSON-RPC error responses:

```swift
// Middleware rejection
return .reject(MCPError(code: .invalidRequest, message: "Unauthorized"))

// Tool handler error
throw MCPError(code: .invalidParams, message: "Invalid file path")

// Response:
// {
//   "jsonrpc": "2.0",
//   "id": 1,
//   "error": {
//     "code": -32602,
//     "message": "Invalid file path"
//   }
// }
```

## Deployment

### Lambda Configuration

```bash
# Environment variables
MY_HANDLER=mcp          # Handler key for LambdaApp routing
LOG_LEVEL=info          # Logging level

# Memory: 512MB recommended
# Timeout: 30 seconds default
```

### API Gateway Configuration

- **Method:** POST
- **Integration:** Lambda Proxy
- **Payload Format:** Version 1.0 (REST API)

### Terraform Example

```hcl
resource "aws_lambda_function" "mcp" {
  function_name = "mcp-server"
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.mcp.repository_url}:latest"

  environment {
    variables = {
      MY_HANDLER = "mcp"
      LOG_LEVEL  = "info"
    }
  }

  memory_size = 512
  timeout     = 30
}

resource "aws_apigatewayv2_api" "mcp" {
  name          = "mcp-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "mcp" {
  api_id             = aws_apigatewayv2_api.mcp.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.mcp.invoke_arn
  payload_format_version = "1.0"
}
```

## Type Aliases

```swift
// Router configured for Lambda context
public typealias LambdaRouter = Router<LambdaMCPContext>
```

## Related Modules

- **[MCP](../MCP/README.md)** - Core MCP framework
- **[LambdaApp](../LambdaApp/README.md)** - Lambda framework
- **[MCPHummingbird](../MCPHummingbird/README.md)** - HTTP adapter for local development
