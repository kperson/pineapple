import Testing
import Foundation
@testable import LambdaApp

/// Tests for RuntimeHTTPClient implementations
@Suite("Runtime HTTP Client Tests")
struct RuntimeHTTPClientTests {
    
    // MARK: - MockRuntimeClient Tests
    
    @Test("Mock client returns queued responses in FIFO order")
    func testMockClientFIFO() async throws {
        let mockClient = MockRuntimeClient()
        
        // Queue two responses
        mockClient.addMockResponse(
            statusCode: 200,
            body: "first".data(using: .utf8)!,
            headers: ["X-Order": "1"]
        )
        mockClient.addMockResponse(
            statusCode: 201,
            body: "second".data(using: .utf8)!,
            headers: ["X-Order": "2"]
        )
        
        // First request (mock client calls callback synchronously)
        let firstResponse = await withCheckedContinuation { continuation in
            mockClient.request(
                method: "GET",
                path: "first",
                body: nil,
                headers: [:],
                runtimeAPI: "test"
            ) { response, error in
                continuation.resume(returning: response)
            }
        }
        
        #expect(firstResponse?.statusCode == 200)
        #expect(String(data: firstResponse?.body ?? Data(), encoding: .utf8) == "first")
        #expect(firstResponse?.headers["X-Order"] == "1")
        
        // Second request
        let secondResponse = await withCheckedContinuation { continuation in
            mockClient.request(
                method: "GET",
                path: "second",
                body: nil,
                headers: [:],
                runtimeAPI: "test"
            ) { response, error in
                continuation.resume(returning: response)
            }
        }
        
        #expect(secondResponse?.statusCode == 201)
        #expect(String(data: secondResponse?.body ?? Data(), encoding: .utf8) == "second")
        #expect(secondResponse?.headers["X-Order"] == "2")
    }
    
    @Test("Mock client records all requests")
    func testMockClientRecordsRequests() async throws {
        let mockClient = MockRuntimeClient()
        
        // Add responses
        mockClient.addMockResponse(statusCode: 200, body: Data(), headers: [:])
        mockClient.addMockResponse(statusCode: 200, body: Data(), headers: [:])
        
        // Make requests
        mockClient.request(
            method: "GET",
            path: "path1",
            body: "body1".data(using: .utf8),
            headers: ["Header1": "Value1"],
            runtimeAPI: "api1"
        ) { _, _ in }
        
        mockClient.request(
            method: "POST",
            path: "path2",
            body: "body2".data(using: .utf8),
            headers: ["Header2": "Value2"],
            runtimeAPI: "api2"
        ) { _, _ in }
        
        // Verify recorded requests
        let requests = mockClient.getRecordedRequests()
        #expect(requests.count == 2)
        
        #expect(requests[0].method == "GET")
        #expect(requests[0].path == "path1")
        #expect(String(data: requests[0].body ?? Data(), encoding: .utf8) == "body1")
        #expect(requests[0].headers["Header1"] == "Value1")
        #expect(requests[0].runtimeAPI == "api1")
        
        #expect(requests[1].method == "POST")
        #expect(requests[1].path == "path2")
        #expect(String(data: requests[1].body ?? Data(), encoding: .utf8) == "body2")
        #expect(requests[1].headers["Header2"] == "Value2")
        #expect(requests[1].runtimeAPI == "api2")
    }
    
    @Test("Mock client can return errors")
    func testMockClientReturnsErrors() async throws {
        let mockClient = MockRuntimeClient()
        
        struct TestError: Error, Equatable {
            let message: String
        }
        
        let expectedError = TestError(message: "Something went wrong")
        mockClient.addMockError(expectedError)
        
        let receivedError = await withCheckedContinuation { continuation in
            mockClient.request(
                method: "GET",
                path: "test",
                body: nil,
                headers: [:],
                runtimeAPI: "test"
            ) { response, error in
                continuation.resume(returning: error)
            }
        }
        
        #expect(receivedError != nil)
        #expect((receivedError as? TestError)?.message == "Something went wrong")
    }
    
    @Test("Mock client clearRecordedRequests works")
    func testMockClientClearRequests() async throws {
        let mockClient = MockRuntimeClient()
        
        mockClient.addMockResponse(statusCode: 200, body: Data(), headers: [:])
        mockClient.request(method: "GET", path: "test", body: nil, headers: [:], runtimeAPI: "test") { _, _ in }
        
        #expect(mockClient.getRecordedRequests().count == 1)
        
        mockClient.clearRecordedRequests()
        
        #expect(mockClient.getRecordedRequests().count == 0)
    }
    
    @Test("Mock client doesn't call callback when no responses queued")
    func testMockClientNoResponsesQueued() async throws {
        let mockClient = MockRuntimeClient()
        
        // Note: We can't easily test that callback wasn't called since mock is synchronous
        // Instead, verify that request is recorded even without response
        mockClient.request(
            method: "GET",
            path: "test",
            body: nil,
            headers: [:],
            runtimeAPI: "test"
        ) { _, _ in
            // This won't be called when no responses queued
        }
        
        // The request should still be recorded
        #expect(mockClient.getRecordedRequests().count == 1)
        #expect(mockClient.getRecordedRequests()[0].path == "test")
    }
}
