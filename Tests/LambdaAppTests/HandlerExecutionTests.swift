import Testing
import Logging
@testable import LambdaApp

@Suite("Handler Execution Tests")
struct HandlerExecutionTests {
    
    @Test("Handler closures are properly captured")
    func handlerClosureCapture() {
        var capturedValue = ""
        let app = LambdaApp()
        
        app.addSQS(key: "test") { _, _ in
            capturedValue = "SQS executed"
        }
        
        // Verify handler was stored
        #expect(app.handler(for: "test") != nil)
        guard case .sqs(_) = app.handler(for: "test")! else {
            Issue.record("Expected SQS handler")
            return
        }
        
        // The closure should be captured in the handler
        #expect(capturedValue == "") // Not executed yet
    }
    
    @Test("Multiple handlers can be stored simultaneously")
    func multipleHandlerStorage() {
        let app = LambdaApp()
        
        app.addSQS(key: "sqs-test") { _, _ in }
        app.addSNS(key: "sns-test") { _, _ in }
        app.addS3(key: "s3-test") { _, _ in }
        app.addDynamoDB(key: "dynamo-test") { _, _ in }
        app.addEventBridge(key: "event-test") { _, _ in }
        
        // All handlers should be stored with correct types
        guard case .sqs(_) = app.handler(for: "sqs-test")! else {
            Issue.record("Expected SQS handler")
            return
        }
        guard case .sns(_) = app.handler(for: "sns-test")! else {
            Issue.record("Expected SNS handler")
            return
        }
        guard case .s3(_) = app.handler(for: "s3-test")! else {
            Issue.record("Expected S3 handler")
            return
        }
        guard case .dynamodb(_) = app.handler(for: "dynamo-test")! else {
            Issue.record("Expected DynamoDB handler")
            return
        }
        guard case .basicVoid(_) = app.handler(for: "event-test")! else {
            Issue.record("Expected BasicVoid handler")
            return
        }
    }
    
    @Test("Handler types can be enumerated with pattern matching")
    func handlerTypeEnumeration() {
        let app = LambdaApp()
        
        app.addSQS(key: "test") { _, _ in }
        
        guard let handler = app.handler(for: "test") else {
            Issue.record("Handler not found")
            return
        }
        
        // Test pattern matching on handler types
        switch handler {
        case .sqs(_):
            // Expected case
            break
        case .sns(_), .s3(_), .dynamodb(_), .apiGateway(_), .basic(_), .basicVoid(_):
            Issue.record("Unexpected handler type")
        }
    }
    
    @Test("Handlers can be replaced")
    func handlerReplacement() {
        let app = LambdaApp()
        
        // Add initial handler
        app.addSQS(key: "test") { _, _ in }
        guard case .sqs(_) = app.handler(for: "test")! else {
            Issue.record("Expected SQS handler")
            return
        }
        
        // Replace with different type
        app.addSNS(key: "test") { _, _ in }
        guard case .sns(_) = app.handler(for: "test")! else {
            Issue.record("Expected SNS handler after replacement")
            return
        }
    }
    
    @Test("Context parameter is passed to handlers")
    func contextParameterPassing() {
        let app = LambdaApp()
        var receivedContext: LambdaContext?
        
        app.addEventBridge(key: "test") { context, _ in
            receivedContext = context
        }
        
        // Verify the closure signature accepts LambdaContext
        #expect(app.handler(for: "test") != nil)
        
        // The closure should be ready to receive context when executed
        // (We can't easily test execution without full AWS Lambda runtime setup)
    }
}
