import Testing
@testable import LambdaApp

@Suite("Key Handling Tests")
struct KeyHandlingTests {
    
    @Test("Empty key can be used")
    func emptyKey() {
        let app = LambdaApp()
        app.addSQS(key: "") { _, _ in }
        #expect(app.handler(for: "") != nil)
    }
    
    @Test("Keys are case-sensitive")
    func caseSensitivity() {
        let app = LambdaApp()
        
        app.addSQS(key: "TestKey") { _, _ in }
        app.addSNS(key: "testkey") { _, _ in }
        
        // Should be different keys
        guard case .sqs(_) = app.handler(for: "TestKey")! else {
            Issue.record("Expected SQS handler for 'TestKey'")
            return
        }
        guard case .sns(_) = app.handler(for: "testkey")! else {
            Issue.record("Expected SNS handler for 'testkey'")
            return
        }
        
        #expect(app.handler(for: "TESTKEY") == nil)
    }
    
    @Test("Special characters in keys are supported")
    func specialCharacters() {
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
                    Issue.record("Failed to store/retrieve handler for key: \(key)")
                    return
                }
            } else {
                app.addSNS(key: key) { _, _ in }
                guard case .sns(_) = app.handler(for: key)! else {
                    Issue.record("Failed to store/retrieve handler for key: \(key)")
                    return
                }
            }
        }
    }
    
    @Test("Unicode keys are supported")
    func unicodeKeys() {
        let app = LambdaApp()
        
        let unicodeKeys = ["🚀", "测试", "café", "naïve"]
        
        for key in unicodeKeys {
            app.addS3(key: key) { _, _ in }
            guard case .s3(_) = app.handler(for: key)! else {
                Issue.record("Failed to handle unicode key: \(key)")
                return
            }
        }
    }
    
    @Test("Long keys (1000 characters) are supported")
    func longKeys() {
        let app = LambdaApp()
        
        let longKey = String(repeating: "a", count: 1000)
        app.addDynamoDB(key: longKey) { _, _ in }
        
        #expect(app.handler(for: longKey) != nil)
        guard case .dynamodb(_) = app.handler(for: longKey)! else {
            Issue.record("Expected DynamoDB handler for long key")
            return
        }
    }
}
