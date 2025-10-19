## 🍍 Pineapple

Project Pineapple is a collection of tools to make running Lambda on Swift Simple.

## Components

### LambdaApp Framework
A fluent interface for building Lambda functions with multiple event handlers:

```swift
let app = LambdaApp()
    .addEventBridge { event in
        // Handle EventBridge/CloudWatch events
    }
    .addSQS { message in
        // Handle SQS messages
    }

Lambda.runApp(app: app, keyHandlerResolution: { 
    ProcessInfo.processInfo.environment["MY_HANDLER"] 
})
```

### SystemTestsApp
Integration testing application that processes SQS messages and stores verification data in DynamoDB. Uses environment variables for test isolation:
- `TEST_RUN_KEY` - Unique identifier for test runs
- `VERIFY_TABLE` - DynamoDB table for test verification
- `TEST_SQS_QUEUE_URL` - SQS queue for test messages

## Building

### Docker Build
The project uses a two-stage Docker build for efficient compilation:

```bash
./build.sh
```

This creates:
- `pineapple-cache` (5.83GB) - Build cache with compiled Swift dependencies
- `pineapple` (365MB) - Final Lambda runtime image

The cache image speeds up subsequent builds by avoiding recompilation of Swift packages like AWS Lambda Runtime, Soto SDK, and NIO.

### Local Development
```bash
swift build
swift test
```

## Deployment

The containerized Lambda can be deployed using the generated Docker image with Terraform configuration in the `Build/` directory.
