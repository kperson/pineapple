import Testing
import Foundation
import Logging
@testable import LambdaApp

@Suite("LambdaContext Tests")
struct LambdaContextTests {
    
    @Test("Context creation with valid headers")
    func contextCreationWithValidHeaders() throws {
        let headers = [
            "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test",
            "lambda-runtime-deadline-ms": "1609459200000", // 2021-01-01 00:00:00 UTC
            "lambda-runtime-trace-id": "Root=1-5e5f3d2a-1234567890abcdef",
            "lambda-runtime-cognito-identity": "cognito-identity-id",
            "lambda-runtime-client-context": "client-context-data"
        ]
        
        let logger = Logger(label: "test")
        let context = try PineappleLambdaContext(
            requestId: "test-request-123",
            headers: headers,
            logger: logger
        )
        
        #expect(context.requestId == "test-request-123")
        #expect(context.invokedFunctionArn == "arn:aws:lambda:us-east-1:123456789:function:test")
        #expect(context.traceId == "Root=1-5e5f3d2a-1234567890abcdef")
        #expect(context.cognitoIdentity == "cognito-identity-id")
        #expect(context.clientContext == "client-context-data")
        
        // Verify deadline calculation
        let expectedDeadline = Date(timeIntervalSince1970: 1609459200.0)
        #expect(abs(context.deadline.timeIntervalSince1970 - expectedDeadline.timeIntervalSince1970) < 0.001)
    }
    
    @Test("Context creation with minimal headers")
    func contextCreationWithMinimalHeaders() throws {
        let headers = [
            "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test",
            "lambda-runtime-deadline-ms": "1609459200000"
        ]
        
        let logger = Logger(label: "test")
        let context = try PineappleLambdaContext(
            requestId: "test-request-123",
            headers: headers,
            logger: logger
        )
        
        #expect(context.requestId == "test-request-123")
        #expect(context.traceId == nil)
        #expect(context.cognitoIdentity == nil)
        #expect(context.clientContext == nil)
    }
    
    @Test("Context creation fails with missing function ARN")
    func contextCreationMissingFunctionArn() {
        let headers = [
            "lambda-runtime-deadline-ms": "1609459200000"
        ]
        
        let logger = Logger(label: "test")
        
        #expect(throws: LambdaContextError.self) {
            try PineappleLambdaContext(
                requestId: "test-request-123",
                headers: headers,
                logger: logger
            )
        }
        
        // Verify specific error case
        do {
            _ = try PineappleLambdaContext(
                requestId: "test-request-123",
                headers: headers,
                logger: logger
            )
            Issue.record("Expected LambdaContextError to be thrown")
        } catch let error as LambdaContextError {
            if case .missingRequiredHeader(let header) = error {
                #expect(header == "lambda-runtime-invoked-function-arn")
            } else {
                Issue.record("Expected missingRequiredHeader error")
            }
        } catch {
            Issue.record("Expected LambdaContextError, got \(type(of: error))")
        }
    }
    
    @Test("Context creation fails with missing deadline")
    func contextCreationMissingDeadline() {
        let headers = [
            "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test"
        ]
        
        let logger = Logger(label: "test")
        
        #expect(throws: LambdaContextError.self) {
            try PineappleLambdaContext(
                requestId: "test-request-123",
                headers: headers,
                logger: logger
            )
        }
        
        // Verify specific error case
        do {
            _ = try PineappleLambdaContext(
                requestId: "test-request-123",
                headers: headers,
                logger: logger
            )
            Issue.record("Expected LambdaContextError to be thrown")
        } catch let error as LambdaContextError {
            if case .missingRequiredHeader(let header) = error {
                #expect(header == "lambda-runtime-deadline-ms")
            } else {
                Issue.record("Expected missingRequiredHeader error")
            }
        } catch {
            Issue.record("Expected LambdaContextError, got \(type(of: error))")
        }
    }
    
    @Test("Context creation fails with invalid deadline value")
    func contextCreationInvalidDeadlineValue() {
        let headers = [
            "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test",
            "lambda-runtime-deadline-ms": "not-a-number"
        ]
        
        let logger = Logger(label: "test")
        
        #expect(throws: LambdaContextError.self) {
            try PineappleLambdaContext(
                requestId: "test-request-123",
                headers: headers,
                logger: logger
            )
        }
        
        // Verify specific error case
        do {
            _ = try PineappleLambdaContext(
                requestId: "test-request-123",
                headers: headers,
                logger: logger
            )
            Issue.record("Expected LambdaContextError to be thrown")
        } catch let error as LambdaContextError {
            if case .invalidHeaderValue(let header, let value, _) = error {
                #expect(header == "lambda-runtime-deadline-ms")
                #expect(value == "not-a-number")
            } else {
                Issue.record("Expected invalidHeaderValue error")
            }
        } catch {
            Issue.record("Expected LambdaContextError, got \(type(of: error))")
        }
    }
    
    @Test("Context error descriptions are informative")
    func contextErrorDescriptions() {
        let missingHeaderError = LambdaContextError.missingRequiredHeader("test-header")
        #expect(missingHeaderError.description.contains("test-header"))
        
        let invalidValueError = LambdaContextError.invalidHeaderValue(
            header: "test-header",
            value: "test-value",
            reason: "test reason"
        )
        #expect(invalidValueError.description.contains("test-header"))
        #expect(invalidValueError.description.contains("test-value"))
        #expect(invalidValueError.description.contains("test reason"))
    }
    
    @Test("Logger metadata is properly injected")
    func loggerMetadataInjection() throws {
        let headers = [
            "lambda-runtime-invoked-function-arn": "arn:aws:lambda:us-east-1:123456789:function:test",
            "lambda-runtime-deadline-ms": "1609459200000",
            "lambda-runtime-trace-id": "test-trace-id"
        ]
        
        var logger = Logger(label: "test")
        logger.logLevel = .trace
        
        let context = try PineappleLambdaContext(
            requestId: "test-request-123",
            headers: headers,
            logger: logger
        )
        
        // The context's logger should have metadata injected
        #expect(context.logger[metadataKey: "requestId"] != nil)
        #expect(context.logger[metadataKey: "traceId"] != nil)
    }
}
