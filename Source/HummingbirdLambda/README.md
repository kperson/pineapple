# HummingbirdLambda

Bridges [Hummingbird](https://hummingbird.codes) routers to AWS Lambda via API Gateway, enabling standard Hummingbird routing code to run serverlessly.

## Overview

HummingbirdLambda connects Hummingbird's powerful routing system to AWS Lambda:

- **Standard Hummingbird Routing** - Use familiar `router.get()`, `router.post()`, etc.
- **Path Parameters** - Extract parameters via `ctx.parameters.get("id")`
- **Lambda Context Access** - Access request ID, deadline, function ARN, and logger
- **API Gateway Integration** - Full access to original API Gateway request

## Quick Start

### Basic Usage

```swift
import HummingbirdLambda
import LambdaApp

let router = Router(context: LambdaRequestContext.self)

router.get("hello") { _, _ in
    "Hello, World!"
}

router.get("users/:id") { req, ctx in
    let id = ctx.parameters.get("id") ?? "unknown"
    return "User: \(id)"
}

router.post("users") { req, ctx in
    // Parse request body, create user...
    return Response(status: .created)
}

let app = LambdaApp()
    .addHummingbird(key: "api", router: router)

app.run(handlerKey: "api")
```

### Fluent Builder Pattern

```swift
import HummingbirdLambda
import LambdaApp

let hbApp = HummingbirdLambda.App { router in
    router.get("hello") { _, _ in "Hello!" }

    router.get("users/:id") { req, ctx in
        let id = ctx.parameters.get("id") ?? "unknown"
        return "User: \(id)"
    }

    router.post("users") { req, ctx in
        Response(status: .created)
    }
}

let app = LambdaApp()
    .addHummingbird(key: "api", hbApp: hbApp)

app.run(handlerKey: "api")
```

## Architecture

```
API Gateway → Lambda → HummingbirdLambdaAdapter → Hummingbird Router → Handler
                            ↓                           ↓
                      APIGatewayRequest → Request     Response → APIGatewayResponse
```

The adapter:
1. Converts `APIGatewayRequest` to Hummingbird `Request`
2. Creates `LambdaRequestContext` with Lambda context and original request
3. Routes through standard Hummingbird router
4. Converts Hummingbird `Response` to `APIGatewayResponse`

## LambdaRequestContext

Route handlers receive `LambdaRequestContext` which provides access to:

```swift
public struct LambdaRequestContext: RequestContext {
    // Standard Hummingbird context
    var coreContext: CoreRequestContextStorage

    // Lambda execution context
    let lambdaContext: LambdaContext        // Request ID, deadline, ARN, logger

    // Original API Gateway request
    let apiGatewayRequest: APIGatewayRequest // Headers, path, query params, stage vars
}
```

### Accessing Lambda Context

```swift
router.get("info") { req, ctx in
    // Lambda execution context
    let requestId = ctx.lambdaContext.requestId
    let timeRemaining = ctx.lambdaContext.deadline.timeIntervalSinceNow
    let functionArn = ctx.lambdaContext.invokedFunctionArn

    // Logging with request metadata
    ctx.lambdaContext.logger.info("Processing request \(requestId)")

    return "Request ID: \(requestId)"
}
```

### Accessing API Gateway Request

```swift
router.get("headers") { req, ctx in
    // HTTP headers
    let authHeader = ctx.apiGatewayRequest.headers["Authorization"]
    let userAgent = ctx.apiGatewayRequest.headers["User-Agent"]

    // Query parameters
    let page = ctx.apiGatewayRequest.queryStringParameters["page"]

    // Stage variables
    let env = ctx.apiGatewayRequest.stageVariables?["environment"]

    // Cognito identity (if using API Gateway authorizer)
    let userId = ctx.apiGatewayRequest.requestContext.authorizer?.claims?["sub"]

    return "Auth: \(authHeader ?? "none")"
}
```

### Path Parameters

```swift
router.get("users/:userId/posts/:postId") { req, ctx in
    let userId = ctx.parameters.get("userId") ?? "unknown"
    let postId = ctx.parameters.get("postId") ?? "unknown"

    return "User \(userId), Post \(postId)"
}
```

## Multi-Handler Lambda

Combine Hummingbird with other event handlers:

```swift
let hbApp = HummingbirdLambda.App { router in
    router.get("users/:id") { req, ctx in ... }
    router.post("users") { req, ctx in ... }
}

let app = LambdaApp()
    .addSQS(key: "queue") { ctx, event in
        // Handle SQS messages
    }
    .addHummingbird(key: "api", hbApp: hbApp)
    .addS3(key: "files") { ctx, event in
        // Handle S3 events
    }

// Set MY_HANDLER environment variable to: "queue", "api", or "files"
app.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
```

## APIGatewayRouter Integration

Mount Hummingbird alongside other handlers using `APIGatewayRouter`:

```swift
let hbRouter = Router(context: LambdaRequestContext.self)
hbRouter.get("users/:id") { req, ctx in
    return "User: \(ctx.parameters.get("id") ?? "?")"
}

let apiRouter = APIGatewayRouter()
    .mount("/health") { ctx, req, path in
        APIGatewayResponse(statusCode: .ok, body: "OK")
    }
    .mountHummingbird("/api", router: hbRouter)

let app = LambdaApp()
    .addAPIGateway(key: "http", router: apiRouter)
```

### Path Rewriting

When mounted at a prefix, the prefix is stripped before Hummingbird routing:

```
Mount: "/api"
Request: "/api/users/123"
Hummingbird sees: "/users/123"
```

## Response Types

Hummingbird supports various response types:

```swift
// String response
router.get("text") { _, _ in
    "Plain text"
}

// JSON response
router.get("json") { _, _ in
    let data = try! JSONEncoder().encode(["key": "value"])
    return Response(
        status: .ok,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(data: data))
    )
}

// Status-only response
router.delete("item/:id") { _, _ in
    Response(status: .noContent)
}

// Custom headers
router.get("custom") { _, _ in
    var headers = HTTPFields()
    headers[.contentType] = "text/plain"
    headers[HTTPField.Name("X-Custom-Header")!] = "value"

    return Response(
        status: .ok,
        headers: headers,
        body: .init(byteBuffer: ByteBuffer(string: "Hello"))
    )
}
```

## Request Body Handling

```swift
router.post("echo") { req, ctx in
    // Collect request body
    let buffer = try await req.body.collect(upTo: ctx.maxUploadSize)
    let bodyString = String(buffer: buffer)

    return "Received: \(bodyString)"
}

// JSON decoding
router.post("users") { req, ctx in
    struct CreateUser: Codable {
        let name: String
        let email: String
    }

    let user = try await req.decode(as: CreateUser.self, context: ctx)
    // Create user...

    return Response(status: .created)
}
```

## Response Encoding

All response bodies are automatically base64-encoded for reliable transmission through API Gateway. This handles both text and binary content correctly:

```swift
router.get("image") { _, _ in
    let imageData = loadImage()

    var headers = HTTPFields()
    headers[.contentType] = "image/png"

    return Response(
        status: .ok,
        headers: headers,
        body: .init(byteBuffer: ByteBuffer(data: imageData))
    )
}
```

## Deployment

### Lambda Configuration

```bash
# Environment variables
MY_HANDLER=api          # Handler key for LambdaApp routing
LOG_LEVEL=info          # Logging level

# Memory: 256-512MB recommended
# Timeout: 30 seconds default
```

### API Gateway Configuration

- **Method:** ANY (or specific methods)
- **Integration:** Lambda Proxy
- **Payload Format:** Version 1.0 (REST API)

### Terraform Example

```hcl
resource "aws_lambda_function" "api" {
  function_name = "hummingbird-api"
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:latest"

  environment {
    variables = {
      MY_HANDLER = "api"
      LOG_LEVEL  = "info"
    }
  }

  memory_size = 512
  timeout     = 30
}

resource "aws_apigatewayv2_api" "api" {
  name          = "hummingbird-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.api.invoke_arn
  payload_format_version = "1.0"
}
```

## Related Modules

- **[LambdaApp](../LambdaApp/README.md)** - Lambda framework
- **[MCPLambda](../MCPLambda/README.md)** - MCP to Lambda adapter
- **[MCPHummingbird](../MCPHummingbird/README.md)** - MCP to Hummingbird adapter
