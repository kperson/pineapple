import Testing
@testable import LambdaApp

@Suite("LambdaApp Tests")
struct LambdaAppTests {
    
    @Test("LambdaApp can be created")
    func creation() {
        let app = LambdaApp()
        #expect(app.handlerCount == 0)
    }
    
    @Test("Handlers can be registered and retrieved")
    func handlerRegistrationAndRetrieval() {
        let app = LambdaApp()
        
        // Register handlers
        app.addSQS(key: "sqs-handler") { _, _ in }
        app.addSNS(key: "sns-handler") { _, _ in }
        app.addS3(key: "s3-handler") { _, _ in }
        app.addDynamoDB(key: "dynamo-handler") { _, _ in }
        app.addEventBridge(key: "event-handler") { _, _ in }
        
        // Verify handlers are stored
        #expect(app.handler(for: "sqs-handler") != nil)
        #expect(app.handler(for: "sns-handler") != nil)
        #expect(app.handler(for: "s3-handler") != nil)
        #expect(app.handler(for: "dynamo-handler") != nil)
        #expect(app.handler(for: "event-handler") != nil)
        
        // Verify correct handler types
        guard case .sqs(_) = app.handler(for: "sqs-handler")! else {
            Issue.record("Expected SQS handler")
            return
        }
        guard case .sns(_) = app.handler(for: "sns-handler")! else {
            Issue.record("Expected SNS handler")
            return
        }
        guard case .s3(_) = app.handler(for: "s3-handler")! else {
            Issue.record("Expected S3 handler")
            return
        }
        guard case .dynamodb(_) = app.handler(for: "dynamo-handler")! else {
            Issue.record("Expected DynamoDB handler")
            return
        }
        guard case .basicVoid(_) = app.handler(for: "event-handler")! else {
            Issue.record("Expected BasicVoid handler")
            return
        }
    }
    
    @Test("Handlers can be overwritten")
    func handlerOverwriting() {
        let app = LambdaApp()
        
        // Register initial handler
        app.addSQS(key: "test-key") { _, _ in }
        #expect(app.handler(for: "test-key") != nil)
        
        // Overwrite with different handler type
        app.addSNS(key: "test-key") { _, _ in }
        
        // Should have SNS handler now
        guard case .sns(_) = app.handler(for: "test-key")! else {
            Issue.record("Expected SNS handler after overwrite")
            return
        }
    }
    
    @Test("Non-existent handler returns nil")
    func nonExistentHandler() {
        let app = LambdaApp()
        #expect(app.handler(for: "non-existent") == nil)
    }
    
    @Test("Method chaining works")
    func methodChaining() {
        let app = LambdaApp()
        let result = app
            .addSQS(key: "sqs") { _, _ in }
            .addSNS(key: "sns") { _, _ in }
            .addS3(key: "s3") { _, _ in }
        
        #expect(result === app)
        #expect(app.handler(for: "sqs") != nil)
        #expect(app.handler(for: "sns") != nil)
        #expect(app.handler(for: "s3") != nil)
    }
}
