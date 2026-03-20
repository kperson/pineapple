## 🍍 Pineapple

A Swift framework for building AWS Lambda functions and MCP (Model Context Protocol) servers with type-safe event handling and fluent APIs.

## Features

- 🚀 **Multi-event Lambda Functions** - Handle SQS, SNS, S3, DynamoDB Streams, API Gateway, and EventBridge in one binary
- 🤖 **MCP Framework** - Build AI-powered tool servers with the [Model Context Protocol](https://spec.modelcontextprotocol.io/)
- 🔧 **Type-Safe Event Handlers** - Strongly-typed handlers with full Swift concurrency support
- 🧪 **Comprehensive Testing** - Unit tests and integration tests with distributed verification
- ⚡ **Efficient Docker Builds** - Two-stage builds with dependency caching

## Architecture

### System Overview

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  SystemTests    │────────▶│   AWS Services   │────────▶│  LambdaHandler  │
│  (Local)        │  Trigger│  (SQS/SNS/S3)    │  Invoke │  (Lambda)       │
└────────┬────────┘         └──────────────────┘         └────────┬────────┘
         │                                                          │
         │                  ┌──────────────────┐                  │
         └─────────────────▶│    DynamoDB      │◀─────────────────┘
           Verify via       │  Verification    │  Save via
           RemoteVerify     │     Table        │  RemoteVerify
                            └──────────────────┘
```

The system uses a **distributed verification pattern** where:
1. **LambdaHandler** (deployed to AWS Lambda) processes events and records verification data
2. **SystemTests** (runs locally) triggers events and verifies Lambda processed them correctly
3. **RemoteVerify** (shared library) coordinates between the two via DynamoDB

## Components

### LambdaApp Framework

A fluent interface for building Lambda functions with multiple event handlers:

```swift
let app = LambdaApp()
    .addSQS(key: "queue-processor") { context, event in
        // Handle SQS messages
        context.logger.info("Processing \(event.records.count) messages")
    }
    .addS3(key: "file-processor") { context, event in
        // Handle S3 events
        for record in event.records {
            context.logger.info("File: \(record.s3.object.key)")
        }
    }
    .addAPIGateway(key: "api") { context, request in
        // Handle HTTP requests
        return APIGatewayResponse(statusCode: .ok, body: "Hello!")
    }

// Run with handler key from environment
app.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
```

**Supported Event Types:**
- **SQS** - Queue messages
- **SNS** - Notification topics
- **S3** - Bucket events (create, delete)
- **DynamoDB Streams** - Database change events with type-safe CDC
- **API Gateway** - HTTP requests/responses (V1 and V2)
- **API Gateway WebSocket** - WebSocket lifecycle events ($connect/$disconnect/$default)
- **EventBridge** - Scheduled and custom events

📖 **[Full LambdaApp Documentation](Source/LambdaApp/README.md)**

### MCP Framework

Build [Model Context Protocol](https://spec.modelcontextprotocol.io/) servers that expose tools, resources, and prompts to AI agents:

```swift
import MCP
import MCPLambda
import LambdaApp

// Define typed input/output with automatic JSON Schema generation
@JSONSchema
struct AddInput: Codable {
    let a: Double
    let b: Double
}

@JSONSchema
struct AddOutput: Codable {
    let sum: Double
}

// Create MCP server with tools
let server = Server()
    .addTool(
        "add_numbers",
        description: "Add two numbers",
        inputType: AddInput.self,
        outputType: AddOutput.self
    ) { request in
        return AddOutput(sum: request.input.a + request.input.b)
    }
    .addResource(
        "config://settings",
        name: "settings",
        description: "Application settings",
        mimeType: "application/json"
    ) { request in
        return .init(name: "settings", data: .text("{\"theme\": \"dark\"}"))
    }

// Deploy to Lambda
let app = LambdaApp()
    .addMCP(key: "mcp", server: server)

app.run(handlerKey: "mcp")
```

**MCP Capabilities:**
- **Tools** - Execute functions with typed parameters
- **Resources** - Serve data via URI patterns
- **Prompts** - Generate conversation templates
- **Middleware** - Authentication, logging, request modification
- **Multi-tenant Routing** - Path parameters for customer isolation
- **OpenAI Integration** - Use MCP tools directly with OpenAI's function calling API

**Transport Adapters:**
- **[MCPLambda](Source/MCPLambda/README.md)** - AWS Lambda via API Gateway
- **[MCPHummingbird](Source/MCPHummingbird/README.md)** - HTTP server for local development
- **[MCPStdio](Source/MCPStdio/README.md)** - Standard I/O for Claude Desktop
- **[MCPWebSocket](Source/MCPWebSocket/README.md)** - iOS apps via WebSocket relay

**Direct API Integration (no transport needed):**
- **`openAIToolDefinitions()`** - Export tool schemas in OpenAI function calling format
- **`executeTool(name:argumentsJSON:)`** - Execute tools directly from OpenAI tool call responses

### HummingbirdLambda

Run standard [Hummingbird](https://hummingbird.codes) routing code on AWS Lambda:

```swift
import HummingbirdLambda
import LambdaApp

let router = Router(context: LambdaRequestContext.self)

router.get("users/:id") { req, ctx in
    let id = ctx.parameters.get("id") ?? "unknown"
    // Access Lambda context
    ctx.lambdaContext.logger.info("Fetching user \(id)")
    return "User: \(id)"
}

router.post("users") { req, ctx in
    // Parse body, create user...
    return Response(status: .created)
}

let app = LambdaApp()
    .addHummingbird(key: "api", router: router)

app.run(handlerKey: "api")
```

**Features:**
- Standard Hummingbird routing (`router.get()`, `router.post()`, etc.)
- Path parameters via `ctx.parameters`
- Lambda context access (request ID, deadline, logger)
- API Gateway request access (headers, query params, stage variables)

📖 **[Full HummingbirdLambda Documentation](Source/HummingbirdLambda/README.md)**

### WebSocket Relay (iOS MCP Proxy)

iOS apps can't run HTTP servers, so MCP clients can't call them directly. The WebSocket relay bridges this gap: the iOS app connects **outbound** to an AWS WebSocket endpoint, and MCP clients send HTTP requests to the relay, which forwards them to the iOS app and returns the response.

```
MCP Client (Claude)                              iOS App
     |                                              |
     | POST /mcp/{sessionId}                        | WSS outbound connect
     | Header: X-API-Key: <key>                     | Header: Authorization: Bearer <jwt>
     v                                              v
+----------------------------------------------------+
|               AWS API Gateway                      |
|  HTTP API                  WebSocket API           |
+------+-----------------------+---------------------+
       v                       v
  HTTP Lambda              WS Lambda
  (HTTPRelayHandler)       (WebSocketRelayHandler)
       |                       |
       +------- DynamoDB ------+
               (sessions + request/response)
```

**iOS app side** — connect to the relay and expose MCP tools:

```swift
import MCP
import MCPWebSocket

let server = Server()
    .addTool("get_location", description: "Device location",
             inputType: Empty.self) { _ in
        return .text("37.7749, -122.4194")
    }

let relayURL = URL(string: "wss://your-relay.execute-api.us-east-1.amazonaws.com/production")!
let adapter = WebSocketAdapter(server: server, url: relayURL)

let sessionId = UUID().uuidString  // Share with MCP client
try await adapter.run(sessionId: sessionId, token: jwtToken)
```

**Request flow:**
1. iOS app generates a `sessionId`, connects via WebSocket with JWT auth
2. iOS app shares `sessionId` with MCP client (e.g., displayed in UI)
3. MCP client POSTs JSON-RPC request to `/mcp/{sessionId}` with API key
4. HTTP Lambda forwards request to iOS app via WebSocket (API Gateway Management API)
5. iOS app processes request through its `MCPServer`, sends response back over WebSocket
6. HTTP Lambda polls DynamoDB for response, returns it to MCP client

**Security:** Two independent auth layers with pluggable implementations — `WebSocketAuthenticator` for iOS JWT validation, `HTTPClientAuthenticator` for MCP client API key validation.

**Connection management:** Auto-reconnect with exponential backoff (1s-30s), 5-minute ping keep-alive (under API Gateway's 10-min idle timeout).

The relay is three Swift packages:
- **[MCPWebSocketShared](Source/MCPWebSocketShared/README.md)** - Wire protocol types (no dependencies)
- **[MCPWebSocket](Source/MCPWebSocket/README.md)** - iOS client adapter
- **[MCPWebSocketRelay](Source/MCPWebSocketRelay/README.md)** - Lambda relay server (DynamoDB + API Gateway Management API)

Infrastructure is defined in `terraform-support/websocket-api-lambda/` with a complete deployment example in `Build/main.tf`.

📖 **[Full MCP Documentation](Source/MCP/README.md)**

### SystemTests & RemoteVerify

Integration testing system using DynamoDB for distributed verification:

**LambdaHandler** (deployed):
```swift
.addSQS(key: "test.sqs") { context, event in
    for record in event.records {
        let message = try DemoMessage(jsonStr: record.body)
        // Save verification that this message was processed
        try await remoteVerify.save(test: "sqs", value: message.message)
    }
}
```

**SystemTests** (local):
```swift
func testSQSIntegration() async throws {
    let result = try await verifier.checkWithValue(test: "sqs") { uniqueKey in
        // Send SQS message with unique key
        let message = DemoMessage(message: uniqueKey)
        try await sqs.sendMessage(messageBody: try message.jsonStr(), queueUrl: queueUrl)
        // Lambda processes and saves verification
        // RemoteVerify polls DynamoDB for matching key
    }
    XCTAssertTrue(result) // Verification found!
}
```

## Getting Started

### Prerequisites

- **Swift 6.1+** - [Download](https://swift.org/download/)
- **Docker** - For Lambda deployment builds
- **AWS Account** - For deployment and system tests
- **Terraform** - For infrastructure deployment (optional)

### Local Development

```bash
# Build locally
swift build

# Get the path to built executables
BIN_PATH=$(swift build --show-bin-path)
EXECUTABLE="$BIN_PATH/MCPExample"

# Run unit tests (no AWS required)
swift test --filter LambdaAppTests
swift test --filter MCPTests
```

### Building for Lambda

The project uses a two-stage Docker build for efficient compilation:

```bash
./docker-build.sh pineapple
```

**This creates:**
- `pineapple-cache` (5.83GB) - Build cache with compiled Swift dependencies
- `pineapple` (365MB) - Final Lambda runtime image
- `.lambda-build/` - Local build artifacts for testing

The cache stage speeds up subsequent builds by reusing compiled Swift packages (AWS Lambda Runtime, Soto SDK, NIO).

**Dockerfile stages:**
1. **Build stage** (`swift:6.1-amazonlinux2`) - Compiles code with static Swift stdlib
2. **Runtime stage** (`public.ecr.aws/lambda/provided:al2023`) - Creates minimal Lambda container

## Deployment

The `Build/` directory contains complete Terraform configuration for deploying all Lambda functions and required AWS resources.

```bash
cd Build

# Set your AWS profile (if not using default)
export AWS_PROFILE=your-profile

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# Get environment variables for SystemTests
terraform output -raw systemtest_env_vars
```

**Terraform uses standard AWS credential chain:**
- `AWS_PROFILE` environment variable
- `AWS_REGION` environment variable
- `~/.aws/credentials` and `~/.aws/config` files
- `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables

**Customize deployment (optional):**
```bash
# Use different region
terraform apply -var="aws_region=us-west-2"

# Use different test run key
terraform apply -var="test_run_key=my-test-run"

# Or create terraform.tfvars file (see Build/terraform.tfvars.example)
```

**What Terraform creates:**
- ECR repository for Docker image
- 8 Lambda functions (one per event type, plus WebSocket relay pair)
- Event sources (SQS queue, SNS topic, S3 bucket, DynamoDB table with streams)
- API Gateway (REST and HTTP API) for HTTP handlers
- WebSocket API Gateway for relay
- DynamoDB relay table (connection tracking with sessionId GSI)
- EventBridge schedule for cron handler
- DynamoDB verification table
- IAM roles and policies (including `execute-api:ManageConnections` for relay)

## Running Integration Tests

System tests verify that deployed Lambda functions correctly process AWS events. They require deployed infrastructure and AWS credentials.

### Step 1: Deploy Infrastructure

```bash
cd Build
terraform apply
```

### Step 2: Set Environment Variables

**Option A - Use helper script (easiest):**
```bash
# From project root
source <(cd Build && ./setup-systemtest-env.sh)
```

**Option B - Get from Terraform output:**
```bash
cd Build
terraform output -raw systemtest_env_vars
# Copy and paste the export commands
```

**Note:** AWS credentials are automatically inherited from your environment (`AWS_PROFILE`, `~/.aws/credentials`, etc.)

### Step 3: Run System Tests

```bash
# Run all system tests
swift test --filter SystemTests

# Run specific test
swift test --filter SystemTests.LambdaHandlerTests/testSQSIntegration
```

**Test Flow:**
1. Test generates unique UUID
2. Test triggers AWS service (sends SQS message, uploads S3 file, etc.)
3. AWS service invokes Lambda function
4. Lambda processes event and saves verification to DynamoDB
5. Test polls DynamoDB for verification (30 second timeout)
6. Test passes if matching verification found

**Common Issues:**

- **Tests skip**: Missing environment variables. Check all required vars are set.
- **Tests timeout**: Lambda not deployed or handler key mismatch. Check CloudWatch logs.
- **Permission errors**: Lambda IAM role needs permissions for DynamoDB, SQS, etc.

### Debugging System Tests

```bash
# View Lambda logs
aws logs tail /aws/lambda/pineapple-sqs --follow --profile your-profile

# Check DynamoDB verification table
aws dynamodb scan --table-name $VERIFY_TABLE --profile your-profile

# Manually trigger SQS Lambda
aws sqs send-message \
  --queue-url $TEST_SQS_QUEUE_URL \
  --message-body '{"message":"manual-test"}' \
  --profile your-profile
```

## Project Structure

```
pineapple/
├── Source/
│   ├── LambdaApp/              # Lambda framework
│   │   ├── LambdaApp.swift     # Main fluent API
│   │   ├── LambdaRuntime.swift # Custom Lambda runtime
│   │   ├── APIGatewayRouter.swift # Sub-path routing
│   │   └── ...
│   ├── MCP/                    # Model Context Protocol framework
│   │   ├── Server.swift        # MCP server builder
│   │   ├── Router.swift        # Path-based routing
│   │   └── ...
│   ├── MCPLambda/              # MCP → Lambda adapter
│   ├── MCPHummingbird/         # MCP → HTTP adapter
│   ├── MCPStdio/               # MCP → Stdio adapter
│   ├── MCPWebSocket/           # MCP → iOS WebSocket relay adapter
│   ├── MCPWebSocketShared/     # Relay wire protocol types
│   ├── MCPWebSocketRelay/      # Lambda relay server
│   ├── HummingbirdLambda/      # Hummingbird → Lambda adapter
│   ├── JSONSchemaDSL/          # JSON Schema generation
│   ├── JSONValueCoding/        # JSON value encoding/decoding
│   ├── LambdaHandler/          # Deployable Lambda executable
│   ├── MCPExample/             # Example MCP server
│   └── SystemTestsCommon/      # Shared test utilities
├── Tests/
│   ├── LambdaAppTests/         # LambdaApp unit tests
│   ├── MCPTests/               # MCP framework tests
│   ├── MCPLambdaTests/         # Lambda adapter tests
│   ├── MCPHummingbirdTests/    # HTTP adapter tests
│   ├── MCPStdioTests/          # Stdio adapter tests
│   ├── MCPWebSocketTests/      # WebSocket adapter tests
│   ├── MCPWebSocketRelayTests/ # Relay handler tests
│   ├── HummingbirdLambdaTests/ # Hummingbird Lambda adapter tests
│   └── SystemTests/            # Integration tests (requires AWS)
├── Build/                      # Terraform configuration
├── Dockerfile                  # Multi-stage Lambda build
├── docker-build.sh             # Build script
└── Package.swift               # Swift package definition
```

## Testing

### Test Suites

**Unit Tests** (fast, no AWS required):
- `LambdaAppTests` - LambdaApp framework
- `MCPTests` - MCP protocol and server
- `MCPLambdaTests` - Lambda adapter
- `MCPHummingbirdTests` - HTTP adapter
- `MCPStdioTests` - Stdio adapter
- `MCPWebSocketTests` - WebSocket adapter (mock WebSocket)
- `MCPWebSocketRelayTests` - Relay handlers (mock DynamoDB + auth)
- `HummingbirdLambdaTests` - Hummingbird Lambda adapter
- `JSONValueCodingTests` - JSON encoding/decoding

**Integration Tests** (requires AWS):
- `SystemTests` - End-to-end Lambda verification (SQS, SNS, S3, DynamoDB, API Gateway)
- `WebSocketRelayTests` - End-to-end relay round-trip (WebSocket + HTTP + DynamoDB)

### Running Tests

```bash
# All unit tests (no AWS required)
swift test

# LambdaApp tests only
swift test --filter LambdaAppTests

# MCP tests only
swift test --filter MCPTests

# WebSocket relay unit tests
swift test --filter MCPWebSocketTests
swift test --filter MCPWebSocketRelayTests

# Integration tests (requires AWS + env vars)
swift test --filter SystemTests
swift test --filter WebSocketRelayTests

# Specific test
swift test --filter "LambdaAppTests.EventProcessingTests/sqsEventProcessing"
```

### Test Results

```
667 tests in 62 suites passed

Breakdown:
- LambdaApp Tests: ~45 tests
- MCP Tests: ~450 tests
- Adapter Tests: ~90 tests (Lambda, Hummingbird, Stdio)
- WebSocket Tests: ~18 tests (adapter + relay handlers)
- System Tests: ~14 tests (requires AWS)
```

## Environment Variables Reference

### Lambda Runtime
- `_HANDLER` - Handler key for routing (e.g., "test.sqs", "test.http", "test.ws-relay")
- `LOG_LEVEL` - Logging level (trace, debug, info, warning, error)

### Lambda Runtime (WebSocket Relay)
- `RELAY_TABLE_NAME` - DynamoDB relay table name
- `WS_MANAGEMENT_ENDPOINT` - API Gateway WebSocket management URL (for PostToConnection)

### System Tests
- `AWS_PROFILE` - AWS credentials profile
- `TEST_RUN_KEY` - Unique test run identifier (must match Lambda)
- `VERIFY_TABLE` - DynamoDB verification table name
- `TEST_SQS_QUEUE_URL` - SQS queue URL
- `TEST_SNS_TOPIC_ARN` - SNS topic ARN
- `TEST_S3_BUCKET` - S3 bucket name
- `TEST_TABLE` - DynamoDB table with streams
- `TEST_API_ENDPOINT` - API Gateway endpoint URL
- `TEST_API_V2_ENDPOINT` - API Gateway V2 (HTTP API) endpoint URL

### WebSocket Relay E2E Tests
- `TEST_WS_RELAY_ENDPOINT` - WebSocket relay endpoint (wss://...)
- `TEST_HTTP_RELAY_ENDPOINT` - HTTP relay endpoint for MCP client requests

## Contributing

We use Swift Testing framework for tests. When adding tests:

1. Use `@Suite` and `@Test` attributes
2. Use `#expect()` for assertions
3. Use `Issue.record()` for test failures
4. Follow existing patterns in `Tests/LambdaAppTests/`

Example:
```swift
@Suite("My Feature Tests")
struct MyFeatureTests {
    @Test("Feature does something")
    func featureBehavior() {
        let result = doSomething()
        #expect(result == expected)
    }
}
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Resources

- [Swift on AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)
- [Model Context Protocol](https://spec.modelcontextprotocol.io/)
- [Swift Testing](https://github.com/apple/swift-testing)
- [Soto AWS SDK](https://github.com/soto-project/soto)
