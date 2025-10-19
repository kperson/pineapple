import XCTest
@testable import LambdaApp

final class LambdaAppTests: XCTestCase {
    
    func testLambdaAppCreation() {
        let app = LambdaApp()
        XCTAssertNotNil(app)
    }
    
    func testHandlerRegistrationAndRetrieval() {
        let app = LambdaApp()
        
        // Register handlers
        app.addSQS(key: "sqs-handler") { _, _ in }
        app.addSNS(key: "sns-handler") { _, _ in }
        app.addS3(key: "s3-handler") { _, _ in }
        app.addDynamoDB(key: "dynamo-handler") { _, _ in }
        app.addEventBridge(key: "event-handler") { _, _ in }
        
        // Verify handlers are stored
        XCTAssertNotNil(app.handler(for: "sqs-handler"))
        XCTAssertNotNil(app.handler(for: "sns-handler"))
        XCTAssertNotNil(app.handler(for: "s3-handler"))
        XCTAssertNotNil(app.handler(for: "dynamo-handler"))
        XCTAssertNotNil(app.handler(for: "event-handler"))
        
        // Verify correct handler types
        guard case .sqs(_) = app.handler(for: "sqs-handler")! else {
            XCTFail("Expected SQS handler")
            return
        }
        guard case .sns(_) = app.handler(for: "sns-handler")! else {
            XCTFail("Expected SNS handler")
            return
        }
        guard case .s3(_) = app.handler(for: "s3-handler")! else {
            XCTFail("Expected S3 handler")
            return
        }
        guard case .dynamodb(_) = app.handler(for: "dynamo-handler")! else {
            XCTFail("Expected DynamoDB handler")
            return
        }
        guard case .basicVoid(_) = app.handler(for: "event-handler")! else {
            XCTFail("Expected BasicVoid handler")
            return
        }
    }
    
    func testHandlerOverwriting() {
        let app = LambdaApp()
        
        // Register initial handler
        app.addSQS(key: "test-key") { _, _ in }
        XCTAssertNotNil(app.handler(for: "test-key"))
        
        // Overwrite with different handler type
        app.addSNS(key: "test-key") { _, _ in }
        
        // Should have SNS handler now
        guard case .sns(_) = app.handler(for: "test-key")! else {
            XCTFail("Expected SNS handler after overwrite")
            return
        }
    }
    
    func testNonExistentHandler() {
        let app = LambdaApp()
        XCTAssertNil(app.handler(for: "non-existent"))
    }
    
    func testMethodChaining() {
        let app = LambdaApp()
        let result = app
            .addSQS(key: "sqs") { _, _ in }
            .addSNS(key: "sns") { _, _ in }
            .addS3(key: "s3") { _, _ in }
        
        XCTAssertTrue(result === app)
        XCTAssertNotNil(app.handler(for: "sqs"))
        XCTAssertNotNil(app.handler(for: "sns"))
        XCTAssertNotNil(app.handler(for: "s3"))
    }
}
