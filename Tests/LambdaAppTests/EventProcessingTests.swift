import Testing
import Foundation
import Logging
@testable import LambdaApp

/// Mock runtime for testing event handling without actual AWS Lambda runtime
final class MockRuntime: Runtime, @unchecked Sendable {
    var eventHandler: RuntimeEventHandler?
    var startCalled = false
    var stopCalled = false
    
    private let queue = DispatchQueue(label: "com.test.mockruntime")
    private var _responses: [String: Data] = [:]
    private var _invocationErrors: [String: LambdaError] = [:]
    private var _initializationError: LambdaError?
    
    var responses: [String: Data] {
        queue.sync { _responses }
    }
    
    var invocationErrors: [String: LambdaError] {
        queue.sync { _invocationErrors }
    }
    
    var initializationError: LambdaError? {
        queue.sync { _initializationError }
    }
    
    func start() {
        startCalled = true
    }
    
    func stop() {
        stopCalled = true
    }
    
    func sendResponse(requestId: String, data: Data) {
        queue.sync {
            _responses[requestId] = data
        }
    }
    
    func sendInitializationError(error: LambdaError) {
        queue.sync {
            _initializationError = error
        }
    }
    
    func sendInvocationError(requestId: String, error: LambdaError) {
        queue.sync {
            _invocationErrors[requestId] = error
        }
    }
    
    func simulateEvent(requestId: String, payload: LambdaPayload) {
        let event = LambdaEvent(requestId: requestId, payload: payload, runTime: self)
        eventHandler?.handleEvent(event)
    }
}

@Suite("Event Processing Tests")
struct EventProcessingTests {
    
    @Test("SQS events are processed correctly")
    func sqsEventProcessing() async throws {
        let app = LambdaApp()
        let mockRuntime = MockRuntime()
        
        var receivedEvent: SQSEvent?
        
        app.addSQS(key: "sqs-test") { context, event in
            receivedEvent = event
        }
        
        mockRuntime.eventHandler = app
        
        // Create a valid SQS event from JSON
        let sqsJSON = """
        {
            "Records": [
                {
                    "messageId": "msg-123",
                    "receiptHandle": "receipt-456",
                    "body": "test message",
                    "md5OfBody": "md5-hash",
                    "attributes": {},
                    "messageAttributes": {},
                    "eventSourceARN": "arn:aws:sqs:us-east-1:123456789:test-queue",
                    "eventSource": "aws:sqs",
                    "awsRegion": "us-east-1"
                }
            ]
        }
        """
        
        let eventData = sqsJSON.data(using: .utf8)!
        let payload = LambdaPayload(
            body: eventData,
            headers: [
                "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test",
                "lambda-runtime-deadline-ms": "1609459200000"
            ]
        )
        
        // Simulate event delivery
        mockRuntime.simulateEvent(requestId: "req-123", payload: payload)
        
        // Wait for async handler to complete
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(receivedEvent != nil)
        #expect(receivedEvent?.records.count == 1)
        #expect(receivedEvent?.records.first?.messageId == "msg-123")
        #expect(mockRuntime.responses["req-123"] != nil)
    }
    
    @Test("Invalid JSON is handled with error")
    func eventProcessingWithInvalidJSON() async throws {
        let app = LambdaApp()
        let mockRuntime = MockRuntime()
        
        app.addSQS(key: "sqs-test") { context, event in
            Issue.record("Handler should not be called with invalid JSON")
        }
        
        mockRuntime.eventHandler = app
        
        let payload = LambdaPayload(
            body: "invalid json".data(using: .utf8)!,
            headers: [
                "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test",
                "lambda-runtime-deadline-ms": "1609459200000"
            ]
        )
        
        mockRuntime.simulateEvent(requestId: "req-error", payload: payload)
        
        // Give async task time to complete
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should have sent an invocation error
        #expect(mockRuntime.invocationErrors["req-error"] != nil)
    }
    
    @Test("Invalid headers are handled with error")
    func eventProcessingWithInvalidHeaders() async throws {
        let app = LambdaApp()
        let mockRuntime = MockRuntime()
        
        app.addSQS(key: "sqs-test") { context, event in
            Issue.record("Handler should not be called with invalid headers")
        }
        
        mockRuntime.eventHandler = app
        
        let sqsJSON = """
        {
            "Records": []
        }
        """
        let eventData = sqsJSON.data(using: .utf8)!
        
        // Missing required headers
        let payload = LambdaPayload(body: eventData, headers: [:])
        
        mockRuntime.simulateEvent(requestId: "req-bad-headers", payload: payload)
        
        // Give async task time to complete
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Should have sent an invocation error due to context creation failure
        #expect(mockRuntime.invocationErrors["req-bad-headers"] != nil, "Expected invocation error for missing headers")
        
        // Verify no successful response was sent
        #expect(mockRuntime.responses["req-bad-headers"] == nil, "Should not have a successful response")
    }
    
    @Test("Multiple handlers without key generates error")
    func multipleHandlerWithoutKey() async throws {
        let app = LambdaApp()
        let mockRuntime = MockRuntime()
        
        app.addSQS(key: "sqs-handler") { context, event in
            Issue.record("SQS handler should not be called")
        }
        
        app.addS3(key: "s3-handler") { context, event in
            Issue.record("S3 handler should not be called")
        }
        
        mockRuntime.eventHandler = app
        
        let sqsJSON = """
        {
            "Records": []
        }
        """
        let eventData = sqsJSON.data(using: .utf8)!
        let payload = LambdaPayload(
            body: eventData,
            headers: [
                "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test",
                "lambda-runtime-deadline-ms": "1609459200000"
            ]
        )
        
        mockRuntime.simulateEvent(requestId: "req-multi", payload: payload)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Should have error because no handler key was specified with multiple handlers
        #expect(mockRuntime.invocationErrors["req-multi"] != nil, "Expected invocation error for multiple handlers without key")
        
        // Verify no successful response was sent
        #expect(mockRuntime.responses["req-multi"] == nil, "Should not have a successful response")
    }
    
    @Test("Handler errors are propagated")
    func handlerThrowsError() async throws {
        let app = LambdaApp()
        let mockRuntime = MockRuntime()
        
        struct TestError: Error {}
        
        app.addSQS(key: "sqs-test") { context, event in
            throw TestError()
        }
        
        mockRuntime.eventHandler = app
        
        let sqsJSON = """
        {
            "Records": []
        }
        """
        let eventData = sqsJSON.data(using: .utf8)!
        let payload = LambdaPayload(
            body: eventData,
            headers: [
                "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test",
                "lambda-runtime-deadline-ms": "1609459200000"
            ]
        )
        
        mockRuntime.simulateEvent(requestId: "req-throws", payload: payload)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should have sent an invocation error
        #expect(mockRuntime.invocationErrors["req-throws"] != nil)
    }
    
    @Test("Single handler is auto-resolved")
    func singleHandlerAutoResolution() async throws {
        let app = LambdaApp()
        let mockRuntime = MockRuntime()
        
        var handlerWasCalled = false
        
        app.addSQS(key: "only-handler") { context, event in
            handlerWasCalled = true
        }
        
        mockRuntime.eventHandler = app
        
        let sqsJSON = """
        {
            "Records": []
        }
        """
        let eventData = sqsJSON.data(using: .utf8)!
        let payload = LambdaPayload(
            body: eventData,
            headers: [
                "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test",
                "lambda-runtime-deadline-ms": "1609459200000"
            ]
        )
        
        // No handler key specified, but should work because there's only one handler
        mockRuntime.simulateEvent(requestId: "req-single", payload: payload)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should succeed without error
        #expect(handlerWasCalled == true)
        #expect(mockRuntime.invocationErrors["req-single"] == nil)
        #expect(mockRuntime.responses["req-single"] != nil)
    }
}
