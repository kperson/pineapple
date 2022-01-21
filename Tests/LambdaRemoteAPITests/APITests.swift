import Foundation
import XCTest
import SotoDynamoDB
import Vapor
import LambdaRuntimeAPI
@testable import LambdaRemoteAPI
@testable import LambdaRemoteClient


class APITests: ProxyTestCase {

    let client = LambdaRemoteClient(baseURL: "http://localhost:8080")

    
    func testNilRequestId404() async throws {
        let requestId = UUID().uuidString
        let res = try await client.getEvent(requestId: requestId)
        XCTAssertNil(res)
    }
    
    func testSaveAndRetrieve() async throws {
        let requestId = UUID().uuidString
        let post = LambdaRemoteEventPost(
            namespaceKey: "my-key",
            request: .init(body: Data(), headers: ["hello": "world"]),
            requestId: requestId
        )
        let fetchedEvent = try await client.saveEvent(event: post)
        let res = try await client.getEvent(requestId: requestId)
        XCTAssertEqual(res?.requestId, requestId)
        XCTAssertEqual(fetchedEvent.requestId, requestId)
    }
    
    func testSaveAndRetrievePolling() {
        // NOTE: maybe there is a better way to test this using async, but I am new to this
        let exp = expectation(description: "testSaveAndRetrievePolling")
        let body = "my_response".data(using: .utf8)!
        let requestId = UUID().uuidString
        let post = LambdaRemoteEventPost(
            namespaceKey: "my-key",
            request: .init(body: Data(), headers: ["hello": "world"]),
            requestId: requestId
        )
        Task {
            let res = try await self.client.getEvent(requestId: requestId, shouldLongPoll: true)
            XCTAssertEqual(res?.requestId, requestId)
            XCTAssertNotNil(res?.response)
            exp.fulfill()
        }
        Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            _ = try await client.saveEvent(event: post)
            _ = try await client.sendInvocationResponse(
                namespaceKey: "my-key",
                requestId: requestId,
                response: body
            )
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testSaveAndDelete() async throws {
        let requestId = UUID().uuidString
        let post = LambdaRemoteEventPost(
            namespaceKey: "my-key",
            request: .init(body: Data(), headers: ["hello": "world"]),
            requestId: requestId
        )
        _ = try await client.saveEvent(event: post)
        _ = try await client.deleteEvent(requestId: requestId)
        let res = try await client.getEvent(requestId: requestId)
        XCTAssertNil(res)
    }
    
    func testSendingResponse() async throws {
        let body = "my_response".data(using: .utf8)!
        let requestId = UUID().uuidString
        let post = LambdaRemoteEventPost(
            namespaceKey: "my-key",
            request: .init(body: Data(), headers: ["hello": "world"]),
            requestId: requestId
        )
        _ = try await client.saveEvent(event: post)
        _ = try await client.sendInvocationResponse(namespaceKey: "my-key", requestId: requestId, response: body)
        let res = try await client.getEvent(requestId: requestId)!
        if case .response(payload: let p) = res.response! {
            XCTAssertEqual(p.body, body)
        }
        else {
            XCTFail("lambda event does not contain a response")
        }
    }
    
    func testSendingError() async throws {
        let error = LambdaError(errorMessage: "my error")
        let requestId = UUID().uuidString
        let post = LambdaRemoteEventPost(
            namespaceKey: "my-key",
            request: .init(body: Data(), headers: ["hello": "world"]),
            requestId: requestId
        )
        _ = try await client.saveEvent(event: post)
        _ = try await client.sendInvocationError(namespaceKey: "my-key", requestId: requestId, error: error)
        let res = try await client.getEvent(requestId: requestId)!
        if case .invocationError(error: let e) = res.response! {
            XCTAssertEqual(e, error)
        }
        else {
            XCTFail("lambda event does not contain an error")
        }
    }
    
    func testSendingInitError() async throws {
        let error = LambdaError(errorMessage: "my error")
        let requestId = UUID().uuidString
        let post = LambdaRemoteEventPost(
            namespaceKey: "my-key",
            request: .init(body: Data(), headers: ["hello": "world"]),
            requestId: requestId
        )
        _ = try await client.saveEvent(event: post)
        _ = try await client.sendInitError(namespaceKey: "my-key", error: error)
        let res = try await client.getEvent(requestId: requestId)!
        if case .initializationError(error: let e) = res.response! {
            XCTAssertEqual(e, error)
        }
        else {
            XCTFail("lambda event does not contain an initialization error")
        }
    }
    
    func testLongPollingNil() async throws {
        let res = try await client.getNextInvocation(namespaceKey: "my-key")
        XCTAssertNil(res)
    }
    
    func testLongPollingResponse() {
        // NOTE: maybe there is a better way to test this using async, but I am new to this
        let body = "hello_word".data(using: .utf8)!
        let exp = expectation(description: "testLongPollingResponse")
        Task {
            let res = try await client.getNextInvocation(namespaceKey: "my-key")
            XCTAssertEqual(res, body)
            exp.fulfill()
        }
        Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let requestId = UUID().uuidString
            let post = LambdaRemoteEventPost(
                namespaceKey: "my-key",
                request: .init(body: body, headers: ["hello": "world"]),
                requestId: requestId
            )
            _ = try await client.saveEvent(event: post)
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
}
