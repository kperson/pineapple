# LambdaApp

A fluent Swift framework for building type-safe AWS Lambda functions with multi-event-type support.

## Overview

LambdaApp provides a builder-pattern API for creating Lambda functions that handle multiple AWS event types in a single binary. It features:

- ✅ **Type-Safe Event Handling** - Strongly-typed handlers for all major AWS event sources
- ✅ **Multi-Event Support** - One Lambda binary handles SQS, SNS, S3, DynamoDB, API Gateway, and EventBridge
- ✅ **Swift Concurrency** - Full async/await support with structured concurrency
- ✅ **Custom Lambda Runtime** - No external dependencies on AWS Lambda Runtime API
- ✅ **Change Data Capture** - Type-safe DynamoDB Streams processing with CDC pattern
- ✅ **Comprehensive Logging** - Integrated swift-log with automatic request metadata

## Quick Start

### Single Handler (SQS Example)

```swift
import LambdaApp

let app = LambdaApp()
    .addSQS(key: "queue-processor") { context, event in
        for record in event.records {
            context.logger.info("Processing message: \(record.messageId)")
            // Your business logic here
        }
    }

// Single handler - key not required
app.run()
```

### Multi-Handler Lambda

```swift
import LambdaApp

let app = LambdaApp()
    .addSQS(key: "queue") { context, event in
        // Handle SQS messages
    }
    .addS3(key: "files") { context, event in
        // Handle S3 events
    }
    .addAPIGateway(key: "api") { context, request in
        // Handle HTTP requests
        return APIGatewayResponse(statusCode: .ok, body: "Hello!")
    }

// Route by environment variable
app.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
```

**Deployment:** Set `MY_HANDLER=queue` or `MY_HANDLER=files` or `MY_HANDLER=api` in Lambda environment.

## Supported Event Types

### SQS (Simple Queue Service)

Process messages from SQS queues:

```swift
.addSQS(key: "processor") { context, event in
    for record in event.records {
        context.logger.info("Message: \(record.body)")
        // Process message
    }
}
```

**Event Source:** SQS queue → Lambda trigger

### SNS (Simple Notification Service)

Process notifications from SNS topics:

```swift
.addSNS(key: "notifications") { context, event in
    for record in event.records {
        let subject = record.sns.subject ?? "No subject"
        let message = record.sns.message
        context.logger.info("Alert: \(subject)")
        // Process notification
    }
}
```

**Event Source:** SNS topic → Lambda subscription

### S3 (Simple Storage Service)

React to S3 bucket events:

```swift
.addS3(key: "file-processor") { context, event in
    for record in event.records {
        if record.isCreatedEvent {
            let key = record.s3.object.key
            context.logger.info("New file: \(key)")
            // Process uploaded file
        }
    }
}
```

**Event Source:** S3 bucket → Event notifications → Lambda

**Helper Properties:**
- `record.isCreatedEvent` - ObjectCreated:* events
- `record.isRemovedEvent` - ObjectRemoved:* events

### DynamoDB Streams

Process database change events:

#### Raw Events

```swift
.addDynamoDB(key: "stream") { context, event in
    for record in event.records {
        switch record.eventName {
        case .insert:
            context.logger.info("New item inserted")
        case .modify:
            context.logger.info("Item updated")
        case .remove:
            context.logger.info("Item deleted")
        }
    }
}
```

#### Type-Safe Change Data Capture

```swift
struct UserRecord: Codable {
    let userId: String
    let email: String
}

.addDynamoDBChangeCapture(key: "user-stream", type: UserRecord.self) { context, changes in
    for change in changes {
        switch change {
        case .create(let user):
            context.logger.info("New user: \(user.userId)")
            
        case .update(let new, let old):
            context.logger.info("Email changed: \(old.email) → \(new.email)")
            
        case .delete(let user):
            context.logger.info("User deleted: \(user.userId)")
        }
    }
}
```

**Event Source:** DynamoDB table with Streams enabled → Lambda trigger

**Stream View Requirements:**
- INSERT: Requires `NEW_IMAGE` or `NEW_AND_OLD_IMAGES`
- MODIFY: Requires `NEW_AND_OLD_IMAGES`
- REMOVE: Requires `OLD_IMAGE` or `NEW_AND_OLD_IMAGES`

**Automatic Filtering:** Records that fail to decode to your type are automatically filtered out.

### API Gateway (HTTP)

Handle HTTP requests and return responses:

```swift
.addAPIGateway(key: "api") { context, request in
    context.logger.info("Path: \(request.path)")
    context.logger.info("Method: \(request.httpMethod)")
    
    return APIGatewayResponse(
        statusCode: .ok,
        headers: ["Content-Type": "application/json"],
        body: "{\"message\": \"Success\"}"
    )
}
```

**Event Source:** API Gateway (REST API or HTTP API with v1 payload format) → Lambda integration

### EventBridge / CloudWatch Events

Process scheduled or custom events:

```swift
.addEventBridge(key: "daily-job") { context, eventJSON in
    context.logger.info("Running scheduled task")
    // Perform work
}
```

**Event Source:** EventBridge rule or CloudWatch Events rule → Lambda target

**Use Cases:**
- Scheduled tasks (cron jobs)
- Custom application events
- AWS service state changes

## Lambda Context

Every handler receives a `LambdaContext` with execution metadata:

```swift
.addSQS(key: "processor") { context, event in
    // Request metadata
    context.logger.info("Request ID: \(context.requestId)")
    context.logger.info("Function ARN: \(context.invokedFunctionArn)")
    
    // Timeout management
    let timeRemaining = context.deadline.timeIntervalSinceNow
    if timeRemaining < 10.0 {
        context.logger.warning("Less than 10 seconds remaining!")
    }
    
    // AWS X-Ray tracing
    if let traceId = context.traceId {
        context.logger.info("Trace ID: \(traceId)")
    }
}
```

**Available Properties:**
- `requestId: String` - Unique invocation identifier
- `traceId: String?` - AWS X-Ray trace ID (if enabled)
- `invokedFunctionArn: String` - Lambda function ARN
- `deadline: Date` - Invocation timeout deadline
- `logger: Logger` - Pre-configured logger with request metadata
- `cognitoIdentity: String?` - Cognito identity (if applicable)
- `clientContext: String?` - Client context (if applicable)

## Logging

LambdaApp integrates with [swift-log](https://github.com/apple/swift-log) and automatically injects request metadata:

```swift
context.logger.info("Processing message")
// Output: 2024-01-31T12:00:00-0600 info processor : [requestId: abc-123] Processing message
```

### Custom Log Configuration

```swift
let logFactory: LambdaApp.LogFactory = { label in
    var logger = Logger(label: label)
    logger.logLevel = .debug
    return logger
}

app.run(
    handlerKey: "processor",
    logFactory: logFactory,
    logLevel: .debug
)
```

## Error Handling

Errors thrown from handlers are automatically caught and reported as Lambda invocation errors:

```swift
.addSQS(key: "processor") { context, event in
    for record in event.records {
        do {
            // Process message
            try processMessage(record.body)
            
        } catch {
            // Log error but continue processing other messages
            context.logger.error("Failed to process \(record.messageId): \(error)")
            // Don't re-throw unless you want to fail the entire invocation
        }
    }
}
```

**Behavior:**
- Thrown errors → Lambda invocation failure → Retry (if configured)
- Caught errors → Lambda invocation success → Continue processing

## Handler Registration

### Closure-Based (Recommended)

Most convenient for inline logic:

```swift
.addSQS(key: "processor") { context, event in
    // Handle event
}
```

### Protocol-Based

For complex handlers or code reuse:

```swift
struct MySQSHandler: SQSHandler {
    func handleEvent(context: LambdaContext, event: SQSEvent) async throws {
        // Handle event
    }
}

let app = LambdaApp()
    .add(key: "processor", handler: .sqs(MySQSHandler()))
```

## Multi-Handler Routing

When multiple handlers are registered, route by handler key:

### Environment Variable (Recommended)

```swift
app.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
```

**Lambda environment:** `MY_HANDLER=processor`

### Hardcoded

```swift
app.run(handlerKey: "processor")
```

### Auto-Resolved (Single Handler Only)

```swift
app.run()  // No key needed if only one handler registered
```

## Architecture

### Lambda Runtime API

LambdaApp includes a custom Lambda runtime that polls the Lambda Runtime API:

```
┌──────────────────────────────────────────────────────┐
│  Lambda Runtime API                                   │
│  - /runtime/invocation/next (poll for events)        │
│  - /runtime/invocation/{requestId}/response          │
│  - /runtime/invocation/{requestId}/error             │
└──────────────────────────────────────────────────────┘
                           ↑
                           │ HTTP
                           ↓
┌──────────────────────────────────────────────────────┐
│  LambdaRuntime (polls continuously)                   │
└──────────────────────────────────────────────────────┘
                           │
                           ↓
┌──────────────────────────────────────────────────────┐
│  LambdaApp (routes events to handlers)                │
│  - Resolves handler key                               │
│  - Creates LambdaContext                              │
│  - Decodes event JSON                                 │
│  - Invokes handler                                    │
│  - Encodes response                                   │
└──────────────────────────────────────────────────────┘
                           │
                           ↓
┌──────────────────────────────────────────────────────┐
│  Handler (your code)                                  │
│  - Receives typed event (SQSEvent, S3Event, etc.)    │
│  - Processes event                                    │
│  - Returns response (for API Gateway) or void        │
└──────────────────────────────────────────────────────┘
```

### Event Flow

1. **Poll**: Runtime calls `/runtime/invocation/next` (blocking)
2. **Receive**: Lambda returns event payload + headers
3. **Route**: LambdaApp resolves handler by key
4. **Decode**: Event JSON → Typed event (`SQSEvent`, `S3Event`, etc.)
5. **Context**: Create `LambdaContext` from headers
6. **Execute**: Call handler with context and event
7. **Respond**: 
   - Success → `/runtime/invocation/{requestId}/response`
   - Error → `/runtime/invocation/{requestId}/error`
8. **Repeat**: Loop back to step 1

### Thread Safety

LambdaApp uses a **two-phase lifecycle**:

1. **Setup Phase** (single-threaded):
   - Register handlers with `.addSQS()`, `.addS3()`, etc.
   - Configure logging, handler keys
   
2. **Runtime Phase** (concurrent):
   - Runtime polls for events
   - Events processed concurrently via async tasks
   - Handlers can be invoked in parallel (if Lambda concurrency > 1)

**Important:** All handler registration must complete before calling `.run()`. Do not add handlers after runtime starts.

## Dependencies

LambdaApp depends on:

- **[swift-aws-lambda-events](https://github.com/swift-server/swift-aws-lambda-events)** - AWS event type definitions (SQSEvent, S3Event, etc.)
- **[swift-log](https://github.com/apple/swift-log)** - Logging framework

All AWS event types are re-exported for convenience:

```swift
import LambdaApp
// You now have access to SQSEvent, S3Event, DynamoDBEvent, etc.
```

## Examples

See `LambdaApp+Examples.swift` for comprehensive examples covering:

1. Single SQS handler
2. Multi-handler Lambda
3. DynamoDB raw events
4. DynamoDB type-safe CDC
5. S3 file processing
6. REST API with JSON
7. Scheduled tasks (cron jobs)
8. Custom logging
9. Timeout management
10. Error handling
11. SNS event processing
12. Multi-step processing pipeline

## Best Practices

### 1. Use Type-Safe CDC for DynamoDB

Prefer `.addDynamoDBChangeCapture()` over `.addDynamoDB()` for cleaner code:

```swift
// ✅ Good: Type-safe
.addDynamoDBChangeCapture(key: "users", type: User.self) { context, changes in
    for change in changes {
        // Strongly typed User objects
    }
}

// ❌ Verbose: Manual decoding
.addDynamoDB(key: "users") { context, event in
    for record in event.records {
        // Manual AttributeValue decoding
    }
}
```

### 2. Check Deadlines for Long-Running Tasks

```swift
.addSQS(key: "processor") { context, event in
    for record in event.records {
        if context.deadline.timeIntervalSinceNow < 10.0 {
            context.logger.warning("Approaching timeout, stopping processing")
            break
        }
        // Process record
    }
}
```

### 3. Use Structured Logging

```swift
context.logger.info("Processing order", metadata: [
    "orderId": .string(order.id),
    "customerId": .string(order.customerId),
    "items": .stringConvertible(order.items.count)
])
```

### 4. Handle Partial Batch Failures (SQS)

```swift
.addSQS(key: "processor") { context, event in
    var failedMessageIds: [String] = []
    
    for record in event.records {
        do {
            try await processMessage(record)
        } catch {
            context.logger.error("Failed: \(record.messageId)")
            failedMessageIds.append(record.messageId)
        }
    }
    
    if !failedMessageIds.isEmpty {
        // Report partial failure (requires SQS batch failure reporting)
        throw PartialBatchFailure(failedMessageIds: failedMessageIds)
    }
}
```

### 5. Use Environment Variables for Configuration

```swift
.addS3(key: "processor") { context, event in
    let destinationBucket = ProcessInfo.processInfo.environment["DESTINATION_BUCKET"] ?? "default"
    // Process files
}
```

## Testing

LambdaApp is designed for testability:

```swift
import Testing
@testable import LambdaApp

@Test func testSQSHandler() async throws {
    var processed = false
    
    let app = LambdaApp()
        .addSQS(key: "test") { context, event in
            processed = true
        }
    
    // Verify handler registered
    #expect(app.handler(for: "test") != nil)
    
    // Note: Full integration testing requires AWS environment
    // See SystemTests for examples
}
```

## Deployment

### Docker Build

LambdaApp requires a custom Lambda runtime built with Docker:

```bash
# Two-stage build with dependency caching
./docker-build.sh pineapple

# Output:
# - pineapple-cache (5.83GB) - Build cache
# - pineapple (365MB) - Lambda runtime image
```

### Lambda Configuration

**Environment Variables:**
- `MY_HANDLER` - Handler key (e.g., "queue", "files", "api")
- `LOG_LEVEL` - Logging level (trace, debug, info, warning, error)

**Memory:** 512MB recommended (adjust based on workload)

**Timeout:** 30 seconds default (increase for long-running tasks)

**Concurrency:** Supports concurrent invocations

## Performance

### Cold Start

Swift Lambda cold starts are ~2-3 seconds with this runtime. Use provisioned concurrency for latency-sensitive APIs.

### Memory Usage

Base runtime: ~30-50MB  
Typical handler: 50-200MB  
Recommended: 512MB

### Throughput

Handles 1000s of events/second with proper concurrency settings.

## Troubleshooting

### "Multiple handlers registered but no handler key specified"

**Cause:** You have multiple handlers but didn't provide a handler key.

**Solution:** Set `MY_HANDLER` environment variable or pass `handlerKey` to `.run()`.

### "Missing required Lambda runtime header: lambda-runtime-invoked-function-arn"

**Cause:** Not running in Lambda environment or invalid runtime API.

**Solution:** Ensure Lambda container is properly configured. This error shouldn't occur in AWS Lambda.

### "Failed to decode event"

**Cause:** Event JSON doesn't match expected type.

**Solution:** Check CloudWatch logs for the actual JSON and verify your event source configuration.

## Contributing

See main project [CLAUDE.md](../../CLAUDE.md) for development guidelines.

## License

MIT License - see [LICENSE](../../LICENSE) for details.
