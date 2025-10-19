import XCTest
@testable import LambdaApp

final class KeyHandlingTests: XCTestCase {
    
    func testEmptyKey() {
        let app = LambdaApp()
        app.addSQS(key: "") { _, _ in }
        XCTAssertNotNil(app.handler(for: ""))
    }
    
    func testCaseSensitivity() {
        let app = LambdaApp()
        
        app.addSQS(key: "TestKey") { _, _ in }
        app.addSNS(key: "testkey") { _, _ in }
        
        // Should be different keys
        guard case .sqs(_) = app.handler(for: "TestKey")! else {
            XCTFail("Expected SQS handler for 'TestKey'")
            return
        }
        guard case .sns(_) = app.handler(for: "testkey")! else {
            XCTFail("Expected SNS handler for 'testkey'")
            return
        }
        
        XCTAssertNil(app.handler(for: "TESTKEY"))
    }
    
    func testSpecialCharacters() {
        let app = LambdaApp()
        
        let specialKeys = [
            "test.handler",
            "test-handler",
            "test_handler",
            "test handler",
            "test/handler",
            "test:handler",
            "test@handler",
            "test#handler"
        ]
        
        for (index, key) in specialKeys.enumerated() {
            if index % 2 == 0 {
                app.addSQS(key: key) { _, _ in }
                guard case .sqs(_) = app.handler(for: key)! else {
                    XCTFail("Failed to store/retrieve handler for key: \(key)")
                    return
                }
            } else {
                app.addSNS(key: key) { _, _ in }
                guard case .sns(_) = app.handler(for: key)! else {
                    XCTFail("Failed to store/retrieve handler for key: \(key)")
                    return
                }
            }
        }
    }
    
    func testUnicodeKeys() {
        let app = LambdaApp()
        
        let unicodeKeys = ["🚀", "测试", "café", "naïve"]
        
        for key in unicodeKeys {
            app.addS3(key: key) { _, _ in }
            guard case .s3(_) = app.handler(for: key)! else {
                XCTFail("Failed to handle unicode key: \(key)")
                return
            }
        }
    }
    
    func testLongKeys() {
        let app = LambdaApp()
        
        let longKey = String(repeating: "a", count: 1000)
        app.addDynamoDB(key: longKey) { _, _ in }
        
        XCTAssertNotNil(app.handler(for: longKey))
        guard case .dynamodb(_) = app.handler(for: longKey)! else {
            XCTFail("Expected DynamoDB handler for long key")
            return
        }
    }
}
