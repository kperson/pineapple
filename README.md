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
- **API Gateway** - HTTP requests/responses (V1)
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

**Transport Adapters:**
- **[MCPLambda](Source/MCPLambda/README.md)** - AWS Lambda via API Gateway
- **[MCPHummingbird](Source/MCPHummingbird/README.md)** - HTTP server for local development
- **[MCPStdio](Source/MCPStdio/README.md)** - Standard I/O for Claude Desktop

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
- 6 Lambda functions (one per event type)
- Event sources (SQS queue, SNS topic, S3 bucket, DynamoDB table with streams)
- API Gateway for HTTP handler
- EventBridge schedule for cron handler
- DynamoDB verification table
- IAM roles and policies

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
- `JSONValueCodingTests` - JSON encoding/decoding

**Integration Tests** (slow, requires AWS):
- `SystemTests` - End-to-end Lambda verification

### Running Tests

```bash
# All tests (unit + integration)
swift test

# LambdaApp tests only
swift test --filter LambdaAppTests

# MCP tests only
swift test --filter MCPTests

# Integration tests (requires AWS)
swift test --filter SystemTests

# Specific test
swift test --filter "LambdaAppTests.EventProcessingTests/sqsEventProcessing"
```

### Test Results

```
✔ Test run with 579 tests passed

Breakdown:
- LambdaApp Tests: ~45 tests
- MCP Tests: ~450 tests
- Adapter Tests: ~75 tests
- System Tests: 10 tests (requires AWS)
```

## Environment Variables Reference

### Lambda Runtime
- `_HANDLER` - Handler key for routing (e.g., "test.sqs", "test.http")
- `LOG_LEVEL` - Logging level (trace, debug, info, warning, error)

### System Tests
- `AWS_PROFILE` - AWS credentials profile
- `TEST_RUN_KEY` - Unique test run identifier (must match Lambda)
- `VERIFY_TABLE` - DynamoDB verification table name
- `TEST_SQS_QUEUE_URL` - SQS queue URL
- `TEST_SNS_TOPIC_ARN` - SNS topic ARN
- `TEST_S3_BUCKET` - S3 bucket name
- `TEST_TABLE` - DynamoDB table with streams
- `TEST_API_ENDPOINT` - API Gateway endpoint URL

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
