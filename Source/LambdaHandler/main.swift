import Foundation
import SotoDynamoDB
import SystemTestsCommon
import LambdaApp
import Logging

 
guard let verifyTable = ProcessInfo.processInfo.environment["VERIFY_TABLE"] else {
    fatalError("VERIFY_TABLE environment variable required")
}

guard let testRunKey = ProcessInfo.processInfo.environment["TEST_RUN_KEY"] else {
    fatalError("TEST_RUN_KEY environment variable required")
}

let client = AWSClient()
let dynamoDB = DynamoDB(client: client)
let remoteVerify = RemoteVerify(dynamoDB: dynamoDB, namespace: testRunKey, tableName: verifyTable)

// Define a simple test item structure for DynamoDB
struct TestItem: Codable {
    let id: String
    let data: String
}

let app = LambdaApp()
.addSQS(key: "test.sqs") { context, event in
    context.logger.info("Processing SQS event with \(event.records.count) records")
    
    for record in event.records {
        context.logger.info("SQS Record: \(record)")
        
        // Parse the DemoMessage from the SQS record body and save verification
        do {
            let demoMessage = try DemoMessage(jsonStr: record.body)
            try await remoteVerify.save(test: "sqs", value: demoMessage.message)
            context.logger.info("Saved SQS verification with message: \(demoMessage.message)")
        } catch {
            context.logger.error("Failed to parse DemoMessage: \(error)")
            try await remoteVerify.save(test: "sqs")
        }
    }
}
// NOTE: Single S3 handler for both create and delete events
// AWS S3 bucket notifications require a single notification configuration per bucket.
// Multiple separate notification resources conflict, so we handle both event types here.
.addS3(key: "test.s3-events") { context, event in
    context.logger.info("Processing S3 event with \(event.records.count) records")
    
    for record in event.records {
        if record.isCreatedEvent {
            context.logger.info("S3 Create Record: bucket=\(record.s3.bucket.name), key=\(record.s3.object.key), event=\(record.eventName)")
            try await remoteVerify.save(test: "s3-create", value: record.s3.object.key)
        } else if record.isRemovedEvent {
            context.logger.info("S3 Removed Record: bucket=\(record.s3.bucket.name), key=\(record.s3.object.key), event=\(record.eventName)")
            try await remoteVerify.save(test: "s3-delete", value: record.s3.object.key)
        }
    }
}
.addEventBridge(key: "test.cron") { context, event in
    context.logger.info("Processing EventBridge event: \(event)")
    
    try await remoteVerify.save(test: "eventbridge")
}
.addAPIGateway(key: "test.http") { context, request in
    context.logger.info("Processing API Gateway request: \(request.httpMethod) \(request.path)")
    
    // Remove leading "/" from API Gateway path (e.g., "/bob" becomes "bob")
    try await remoteVerify.save(test: "http", value: String(request.path.dropFirst()))
    
    return APIGatewayResponse(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: "{\"message\": \"Hello from Pineapple Lambda!\"}"
    )
}
.addAPIGatewayV2(key: "test.httpv2") { context, request in
    context.logger.info("Processing API Gateway V2 request: \(request.context.http.method) \(request.rawPath)")

    // Remove leading "/" from V2 rawPath (e.g., "/bob" becomes "bob")
    try await remoteVerify.save(test: "httpv2", value: String(request.rawPath.dropFirst()))

    return APIGatewayV2Response(
        statusCode: 200,
        headers: ["Content-Type": "application/json"],
        body: "{\"message\": \"Hello from Pineapple Lambda V2!\"}"
    )
}
.addSNS(key: "test.sns") { context, event in
    context.logger.info("Processing SNS event with \(event.records.count) records")
    
    for record in event.records {
        context.logger.info("SNS message: \(record.sns.message)")
        try await remoteVerify.save(test: "sns", value: record.sns.message)
    }
}
.addDynamoDBChangeCapture(key: "test.dynamo", type: TestItem.self) { context, changes in
    context.logger.info("Processing \(changes.count) DynamoDB change events")
    for change in changes {
        switch change {
        case .create(let item):
            context.logger.info("DynamoDB CREATE: \(item.id)")
            try await remoteVerify.save(test: "dynamo-create", value: item.id)
        case .update(let new, let old):
            context.logger.info("DynamoDB UPDATE: \(new.id): \(old.data) -> \(new.data)")
            try await remoteVerify.save(test: "dynamo-update", value: new.id)
        case .delete(let item):
            context.logger.info("DynamoDB DELETE: \(item.id)")
            try await remoteVerify.save(test: "dynamo-delete", value: item.id)
        }
    }
}


let logLevel = ProcessInfo.processInfo.environment["LOG_LEVEL"]
    .flatMap { Logger.Level(rawValue: $0.lowercased()) }
let handler = ProcessInfo.processInfo.environment["_HANDLER"]

app.run(handlerKey: handler, logLevel: logLevel)
