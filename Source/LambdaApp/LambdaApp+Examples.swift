// This file contains documentation examples for LambdaApp
// It is not compiled into the library but serves as a reference

#if false

import Foundation
import LambdaApp
import Logging

// MARK: - Basic Examples

/// Example 1: Single SQS Handler
///
/// The simplest Lambda function - processes SQS messages
func example1_SingleSQSHandler() {
    let app = LambdaApp()
        .addSQS(key: "queue-processor") { context, event in
            for record in event.records {
                context.logger.info("Processing message: \(record.messageId)")
                // Your business logic here
            }
        }
    
    // Single handler - no key needed
    app.run()
}

/// Example 2: Multi-Handler Lambda
///
/// One binary handles multiple event types, routed by handler key
func example2_MultiHandlerLambda() {
    let app = LambdaApp()
        // SQS queue processor
        .addSQS(key: "queue") { context, event in
            context.logger.info("Processing \(event.records.count) SQS messages")
        }
        
        // S3 event processor
        .addS3(key: "files") { context, event in
            for record in event.records where record.isCreatedEvent {
                context.logger.info("New file: \(record.s3.object.key)")
            }
        }
        
        // API Gateway endpoint
        .addAPIGateway(key: "api") { context, request in
            return APIGatewayResponse(
                statusCode: .ok,
                body: "{\"message\": \"Hello from Lambda!\"}"
            )
        }
    
    // Handler key from environment variable
    app.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
}

// MARK: - DynamoDB Stream Examples

/// Example 3: DynamoDB Raw Events
///
/// Process raw DynamoDB Stream records
func example3_DynamoDBRawEvents() {
    let app = LambdaApp()
        .addDynamoDB(key: "stream") { context, event in
            for record in event.records {
                context.logger.info("Event: \(record.eventName)")
                
                switch record.eventName {
                case .insert:
                    context.logger.info("New item inserted")
                    // Access record.change.newImage
                    
                case .modify:
                    context.logger.info("Item modified")
                    // Access record.change.newImage and record.change.oldImage
                    
                case .remove:
                    context.logger.info("Item removed")
                    // Access record.change.oldImage
                }
            }
        }
    
    app.run()
}

/// Example 4: Type-Safe DynamoDB CDC
///
/// Use Change Data Capture for type-safe DynamoDB processing
func example4_DynamoDBCDC() {
    // Define your DynamoDB record type
    struct UserRecord: Codable {
        let userId: String
        let email: String
        let name: String
    }
    
    let app = LambdaApp()
        .addDynamoDBChangeCapture(key: "user-stream", type: UserRecord.self) { context, changes in
            for change in changes {
                switch change {
                case .create(let user):
                    context.logger.info("New user: \(user.userId)")
                    // Send welcome email, etc.
                    
                case .update(let newUser, let oldUser):
                    if newUser.email != oldUser.email {
                        context.logger.info("Email changed: \(oldUser.email) → \(newUser.email)")
                        // Send verification email
                    }
                    
                case .delete(let user):
                    context.logger.info("User deleted: \(user.userId)")
                    // Clean up related resources
                }
            }
        }
    
    app.run()
}

// MARK: - S3 Event Examples

/// Example 5: S3 File Processing
///
/// Process files uploaded to S3 bucket
func example5_S3FileProcessing() {
    let app = LambdaApp()
        .addS3(key: "uploads") { context, event in
            for record in event.records {
                let bucket = record.s3.bucket.name
                let key = record.s3.object.key
                
                if record.isCreatedEvent {
                    context.logger.info("Processing new file: s3://\(bucket)/\(key)")
                    // Download and process file
                    
                } else if record.isRemovedEvent {
                    context.logger.info("File deleted: s3://\(bucket)/\(key)")
                    // Clean up references
                }
            }
        }
    
    app.run()
}

// MARK: - API Gateway Examples

/// Example 6: REST API with JSON
///
/// Handle HTTP requests and return JSON responses
func example6_RESTAPI() {
    struct CreateUserRequest: Codable {
        let name: String
        let email: String
    }
    
    struct CreateUserResponse: Codable {
        let userId: String
        let message: String
    }
    
    let app = LambdaApp()
        .addAPIGateway(key: "api") { context, request in
            context.logger.info("Path: \(request.path)")
            context.logger.info("Method: \(request.httpMethod)")
            
            // Parse request body
            if let body = request.body,
               let data = body.data(using: .utf8),
               let userRequest = try? JSONDecoder().decode(CreateUserRequest.self, from: data) {
                
                // Process request
                let userId = UUID().uuidString
                let response = CreateUserResponse(
                    userId: userId,
                    message: "User \(userRequest.name) created"
                )
                
                // Return JSON response
                let responseData = try JSONEncoder().encode(response)
                let responseBody = String(data: responseData, encoding: .utf8) ?? ""
                
                return APIGatewayResponse(
                    statusCode: .ok,
                    headers: ["Content-Type": "application/json"],
                    body: responseBody
                )
            }
            
            // Invalid request
            return APIGatewayResponse(
                statusCode: .badRequest,
                body: "{\"error\": \"Invalid request\"}"
            )
        }
    
    app.run()
}

// MARK: - EventBridge Examples

/// Example 7: Scheduled Tasks (Cron Jobs)
///
/// Run code on a schedule using EventBridge
func example7_ScheduledTasks() {
    let app = LambdaApp()
        .addEventBridge(key: "daily-report") { context, eventJSON in
            context.logger.info("Running daily report")
            
            // Generate report
            // Send to S3 or email
            
            context.logger.info("Report complete")
        }
    
    app.run()
}

// MARK: - Advanced Examples

/// Example 8: Custom Logging
///
/// Configure custom logger factory
func example8_CustomLogging() {
    let app = LambdaApp()
        .addSQS(key: "processor") { context, event in
            context.logger.info("Processing messages")
        }
    
    // Custom logger factory
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
}

/// Example 9: Timeout Management
///
/// Use context.deadline to manage time-sensitive operations
func example9_TimeoutManagement() {
    let app = LambdaApp()
        .addSQS(key: "processor") { context, event in
            for record in event.records {
                // Check time remaining
                let timeRemaining = context.deadline.timeIntervalSinceNow
                
                if timeRemaining < 10.0 {
                    context.logger.warning("Less than 10 seconds remaining, skipping remaining messages")
                    break
                }
                
                // Process message
                context.logger.info("Processing \(record.messageId)")
            }
        }
    
    app.run()
}

/// Example 10: Error Handling
///
/// Handle errors gracefully with proper logging
func example10_ErrorHandling() {
    enum ProcessingError: Error {
        case invalidMessage
        case serviceUnavailable
    }
    
    let app = LambdaApp()
        .addSQS(key: "processor") { context, event in
            for record in event.records {
                do {
                    // Attempt to process
                    guard !record.body.isEmpty else {
                        throw ProcessingError.invalidMessage
                    }
                    
                    // Process message...
                    context.logger.info("Processed: \(record.messageId)")
                    
                } catch ProcessingError.invalidMessage {
                    context.logger.error("Invalid message: \(record.messageId)")
                    // Log to DLQ or metrics
                    
                } catch {
                    context.logger.error("Failed to process \(record.messageId): \(error)")
                    throw error  // Re-throw to fail Lambda invocation
                }
            }
        }
    
    app.run()
}

/// Example 11: SNS Event Processing
///
/// Process notifications from SNS topics
func example11_SNSProcessing() {
    let app = LambdaApp()
        .addSNS(key: "alerts") { context, event in
            for record in event.records {
                let subject = record.sns.subject ?? "No subject"
                let message = record.sns.message
                
                context.logger.info("Alert: \(subject)")
                context.logger.debug("Message: \(message)")
                
                // Forward to Slack, PagerDuty, etc.
            }
        }
    
    app.run()
}

/// Example 12: Multi-Step Processing Pipeline
///
/// Coordinate multiple AWS services
func example12_ProcessingPipeline() {
    struct OrderEvent: Codable {
        let orderId: String
        let customerId: String
        let items: [String]
    }
    
    let app = LambdaApp()
        .addSQS(key: "orders") { context, event in
            for record in event.records {
                guard let order = try? JSONDecoder().decode(
                    OrderEvent.self,
                    from: record.body.data(using: .utf8) ?? Data()
                ) else {
                    context.logger.error("Invalid order format")
                    continue
                }
                
                context.logger.info("Processing order: \(order.orderId)")
                
                // 1. Validate inventory
                // 2. Charge payment
                // 3. Update DynamoDB
                // 4. Send confirmation email
                // 5. Trigger fulfillment SNS notification
                
                context.logger.info("Order complete: \(order.orderId)")
            }
        }
    
    app.run()
}

#endif
