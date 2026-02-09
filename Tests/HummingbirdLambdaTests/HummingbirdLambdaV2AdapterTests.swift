import Testing
import Foundation
import Logging
import HTTPTypes
import Hummingbird
import NIOCore
@testable import HummingbirdLambda
@testable import LambdaApp
@testable import AWSLambdaEvents

/// Tests for HummingbirdLambda V2 adapter
///
/// These tests verify that the adapter correctly translates between
/// API Gateway V2 requests/responses and Hummingbird requests/responses.
@Suite("Hummingbird Lambda V2 Adapter Tests")
struct HummingbirdLambdaV2AdapterTests {

    // MARK: - Test Setup

    /// Creates a test APIGatewayV2Request
    func createAPIGatewayV2Request(
        path: String,
        method: String = "GET",
        headers: [String: String] = [:],
        queryParams: [String: String]? = nil,
        body: String? = nil,
        isBase64Encoded: Bool = false
    ) throws -> AWSLambdaEvents.APIGatewayV2Request {
        var allHeaders = headers
        if allHeaders["Content-Type"] == nil && body != nil {
            allHeaders["Content-Type"] = "application/json"
        }

        var json: [String: Any] = [
            "version": "2.0",
            "routeKey": "$default",
            "rawPath": path,
            "rawQueryString": "",
            "headers": allHeaders.isEmpty ? [:] as [String: String] : allHeaders,
            "requestContext": [
                "accountId": "123456789012",
                "apiId": "test-api",
                "domainName": "test.execute-api.us-east-1.amazonaws.com",
                "domainPrefix": "test",
                "stage": "$default",
                "requestId": UUID().uuidString,
                "http": [
                    "method": method,
                    "path": path,
                    "protocol": "HTTP/1.1",
                    "sourceIp": "127.0.0.1",
                    "userAgent": "test-agent"
                ],
                "time": "12/Mar/2020:19:03:58 +0000",
                "timeEpoch": 1583348638390
            ],
            "isBase64Encoded": isBase64Encoded
        ]

        if let queryParams = queryParams, !queryParams.isEmpty {
            json["queryStringParameters"] = queryParams
        }

        if let body = body {
            json["body"] = body
        }

        let jsonData = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AWSLambdaEvents.APIGatewayV2Request.self, from: jsonData)
    }

    /// Creates a mock LambdaContext for testing
    func createMockContext() -> MockLambdaContext {
        MockLambdaContext(
            requestID: UUID().uuidString,
            traceID: "test-trace",
            invokedFunctionARN: "arn:aws:lambda:us-east-1:123456789012:function:test"
        )
    }

    /// Decode base64 response body to string
    func decodeResponseBody(_ response: APIGatewayV2Response) -> String? {
        guard let body = response.body else { return nil }
        if response.isBase64Encoded == true {
            guard let data = Data(base64Encoded: body) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        return body
    }

    // MARK: - Basic Routing Tests

    @Test("Simple GET route returns correct response")
    func testSimpleGetRoute() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("hello") { _, _ in
            "Hello, World!"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(path: "/hello")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response) == "Hello, World!")
    }

    @Test("Path parameters are extracted correctly")
    func testPathParameters() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("users/:id") { _, ctx in
            let id = ctx.parameters.get("id") ?? "unknown"
            return "User: \(id)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(path: "/users/123")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response) == "User: 123")
    }

    @Test("Query parameters are passed through")
    func testQueryParameters() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("search") { req, _ in
            return "Path: \(req.uri.path)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(
            path: "/search",
            queryParams: ["q": "test", "page": "1"]
        )
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response)?.contains("/search") == true)
    }

    @Test("POST with body works correctly")
    func testPostWithBody() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.post("echo") { req, _ in
            var bodyData = Data()
            for try await buffer in req.body {
                bodyData.append(contentsOf: buffer.readableBytesView)
            }
            let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
            return "Received: \(bodyString)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(
            path: "/echo",
            method: "POST",
            body: "Hello from client"
        )
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response) == "Received: Hello from client")
    }

    @Test("Base64 encoded request body is decoded")
    func testBase64EncodedRequest() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.post("data") { req, _ in
            var bodyData = Data()
            for try await buffer in req.body {
                bodyData.append(contentsOf: buffer.readableBytesView)
            }
            let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
            return "Got: \(bodyString)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let originalBody = "Secret message"
        let base64Body = Data(originalBody.utf8).base64EncodedString()

        let request = try createAPIGatewayV2Request(
            path: "/data",
            method: "POST",
            body: base64Body,
            isBase64Encoded: true
        )
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response) == "Got: Secret message")
    }

    // MARK: - Lambda Context Access Tests

    @Test("Lambda context is accessible in handlers")
    func testLambdaContextAccess() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("context") { _, ctx in
            let requestId = ctx.lambdaContext.requestId
            return "Request ID: \(requestId)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(path: "/context")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response)?.hasPrefix("Request ID:") == true)
    }

    @Test("API Gateway V2 request is accessible in handlers")
    func testAPIGatewayV2RequestAccess() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("headers") { _, ctx in
            let customHeader = ctx.apiGatewayV2Request.headers["X-Custom-Header"] ?? "not found"
            return "Header: \(customHeader)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(
            path: "/headers",
            headers: ["X-Custom-Header": "test-value"]
        )
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response) == "Header: test-value")
    }

    // MARK: - Response Conversion Tests

    @Test("Custom status code is preserved")
    func testCustomStatusCode() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("not-found") { _, _ in
            Response(status: .notFound)
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(path: "/not-found")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .notFound)
    }

    @Test("Response headers are passed through")
    func testResponseHeaders() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("custom-headers") { _, _ in
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            if let customField = HTTPField.Name("X-Custom-Response") {
                headers[customField] = "custom-value"
            }
            return Response(
                status: .ok,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(string: "{}"))
            )
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(path: "/custom-headers")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(response.headers?["Content-Type"] == "application/json")
        #expect(response.headers?["X-Custom-Response"] == "custom-value")
    }

    @Test("Empty response body is handled")
    func testEmptyResponseBody() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.delete("item/:id") { _, _ in
            Response(status: .noContent)
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(path: "/item/123", method: "DELETE")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .noContent)
        #expect(response.body == nil || response.body?.isEmpty == true)
    }

    @Test("Response body is base64 encoded")
    func testResponseIsBase64Encoded() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("test") { _, _ in "Hello" }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(path: "/test")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(response.isBase64Encoded == true)
        #expect(response.body == "SGVsbG8=") // "Hello" in base64
    }

    // MARK: - LambdaApp Integration Tests

    @Test("addHummingbirdV2 integrates with LambdaApp")
    func testLambdaAppIntegration() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("test") { _, _ in "OK" }

        let app = LambdaApp()
            .addHummingbirdV2(key: "api", router: router)

        #expect(app.handlers.count == 1)
        #expect(app.handlers["api"] != nil)
    }

    @Test("HummingbirdLambda.V2App fluent builder works")
    func testFluentBuilder() async throws {
        let hbApp = HummingbirdLambda.V2App { router in
            router.get("hello") { _, _ in "Hello!" }
            router.post("create") { _, _ in Response(status: .created) }
        }

        let app = LambdaApp()
            .addHummingbirdV2(key: "api", hbApp: hbApp)

        #expect(app.handlers.count == 1)
        #expect(app.handlers["api"] != nil)
    }

    // MARK: - Path Override Tests

    @Test("Path override works for mounting under prefix")
    func testPathOverride() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("users/:id") { _, ctx in
            let id = ctx.parameters.get("id") ?? "unknown"
            return "User: \(id)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router, pathOverride: "/users/123")

        let request = try createAPIGatewayV2Request(path: "/api/users/123")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response) == "User: 123")
    }

    // MARK: - Multiple HTTP Methods Tests

    @Test("Different HTTP methods are routed correctly")
    func testMultipleMethods() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("resource") { _, _ in "GET" }
        router.post("resource") { _, _ in "POST" }
        router.put("resource") { _, _ in "PUT" }
        router.delete("resource") { _, _ in "DELETE" }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)
        let context = createMockContext()

        let getRequest = try createAPIGatewayV2Request(path: "/resource", method: "GET")
        let getResponse = try await handler(context, getRequest)
        #expect(decodeResponseBody(getResponse) == "GET")

        let postRequest = try createAPIGatewayV2Request(path: "/resource", method: "POST")
        let postResponse = try await handler(context, postRequest)
        #expect(decodeResponseBody(postResponse) == "POST")

        let putRequest = try createAPIGatewayV2Request(path: "/resource", method: "PUT")
        let putResponse = try await handler(context, putRequest)
        #expect(decodeResponseBody(putResponse) == "PUT")

        let deleteRequest = try createAPIGatewayV2Request(path: "/resource", method: "DELETE")
        let deleteResponse = try await handler(context, deleteRequest)
        #expect(decodeResponseBody(deleteResponse) == "DELETE")
    }

    @Test("Route not found returns 404")
    func testRouteNotFound() async throws {
        let router = Router(context: LambdaV2RequestContext.self)
        router.get("existing") { _, _ in "OK" }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridgeV2(router)

        let request = try createAPIGatewayV2Request(path: "/nonexistent")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .notFound)
    }
}

// MockLambdaContext is defined in HummingbirdLambdaAdapterTests.swift
