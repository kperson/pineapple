import XCTest
import Logging
@testable import LambdaApp

final class HandlerExecutionTests: XCTestCase {
    
    func testHandlerClosureCapture() {
        var capturedValue = ""
        let app = LambdaApp()
        
        app.addSQS(key: "test") { _, _ in
            capturedValue = "SQS executed"
        }
        
        // Verify handler was stored
        XCTAssertNotNil(app.handler(for: "test"))
        guard case .sqs(_) = app.handler(for: "test")! else {
            XCTFail("Expected SQS handler")
            return
        }
        
        // The closure should be captured in the handler
        XCTAssertEqual(capturedValue, "") // Not executed yet
    }
    
    func testMultipleHandlerStorage() {
        let app = LambdaApp()
        
        app.addSQS(key: "sqs-test") { _, _ in }
        app.addSNS(key: "sns-test") { _, _ in }
        app.addS3(key: "s3-test") { _, _ in }
        app.addDynamoDB(key: "dynamo-test") { _, _ in }
        app.addEventBridge(key: "event-test") { _, _ in }
        
        // All handlers should be stored with correct types
        guard case .sqs(_) = app.handler(for: "sqs-test")! else {
            XCTFail("Expected SQS handler")
            return
        }
        guard case .sns(_) = app.handler(for: "sns-test")! else {
            XCTFail("Expected SNS handler")
            return
        }
        guard case .s3(_) = app.handler(for: "s3-test")! else {
            XCTFail("Expected S3 handler")
            return
        }
        guard case .dynamodb(_) = app.handler(for: "dynamo-test")! else {
            XCTFail("Expected DynamoDB handler")
            return
        }
        guard case .basicVoid(_) = app.handler(for: "event-test")! else {
            XCTFail("Expected BasicVoid handler")
            return
        }
    }
    
    func testHandlerTypeEnumeration() {
        let app = LambdaApp()
        
        app.addSQS(key: "test") { _, _ in }
        
        guard let handler = app.handler(for: "test") else {
            XCTFail("Handler not found")
            return
        }
        
        // Test pattern matching on handler types
        switch handler {
        case .sqs(_):
            // Expected case
            break
        case .sns(_), .s3(_), .dynamodb(_), .apiGateway(_), .basic(_), .basicVoid(_):
            XCTFail("Unexpected handler type")
        }
    }
    
    func testHandlerReplacement() {
        let app = LambdaApp()
        
        // Add initial handler
        app.addSQS(key: "test") { _, _ in }
        guard case .sqs(_) = app.handler(for: "test")! else {
            XCTFail("Expected SQS handler")
            return
        }
        
        // Replace with different type
        app.addSNS(key: "test") { _, _ in }
        guard case .sns(_) = app.handler(for: "test")! else {
            XCTFail("Expected SNS handler after replacement")
            return
        }
    }
    
    func testContextParameterPassing() {
        let app = LambdaApp()
        var receivedContext: LambdaContext?
        
        app.addEventBridge(key: "test") { context, _ in
            receivedContext = context
        }
        
        // Verify the closure signature accepts LambdaContext
        XCTAssertNotNil(app.handler(for: "test"))
        
        // The closure should be ready to receive context when executed
        // (We can't easily test execution without full AWS Lambda runtime setup)
    }
}
