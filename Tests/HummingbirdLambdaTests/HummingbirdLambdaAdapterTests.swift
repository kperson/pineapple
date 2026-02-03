import Testing
import Foundation
import Logging
import HTTPTypes
import Hummingbird
import NIOCore
@testable import HummingbirdLambda
@testable import LambdaApp
@testable import AWSLambdaEvents

/// Tests for HummingbirdLambda adapter
///
/// These tests verify that the adapter correctly translates between
/// API Gateway requests/responses and Hummingbird requests/responses.
@Suite("Hummingbird Lambda Adapter Tests")
struct HummingbirdLambdaAdapterTests {

    // MARK: - Test Setup

    /// Creates a test APIGatewayRequest
    func createAPIGatewayRequest(
        path: String,
        method: String = "GET",
        headers: [String: String] = [:],
        queryParams: [String: String]? = nil,
        body: String? = nil,
        isBase64Encoded: Bool = false
    ) throws -> AWSLambdaEvents.APIGatewayRequest {
        var allHeaders = headers
        if allHeaders["Content-Type"] == nil && body != nil {
            allHeaders["Content-Type"] = "application/json"
        }

        let json: [String: Any] = [
            "httpMethod": method,
            "resource": path,
            "path": path,
            "requestContext": [
                "resourceId": "test-resource",
                "apiId": "test-api",
                "domainName": "test.execute-api.us-east-1.amazonaws.com",
                "resourcePath": path,
                "httpMethod": method,
                "requestId": UUID().uuidString,
                "accountId": "123456789012",
                "stage": "test",
                "identity": [
                    "apiKey": NSNull(),
                    "userArn": NSNull(),
                    "cognitoAuthenticationType": NSNull(),
                    "caller": NSNull(),
                    "userAgent": "test-agent",
                    "user": NSNull(),
                    "cognitoIdentityPoolId": NSNull(),
                    "cognitoAuthenticationProvider": NSNull(),
                    "sourceIp": "127.0.0.1",
                    "accountId": NSNull()
                ],
                "extendedRequestId": NSNull(),
                "path": path
            ],
            "queryStringParameters": queryParams as Any? ?? NSNull(),
            "multiValueQueryStringParameters": NSNull(),
            "headers": allHeaders.isEmpty ? NSNull() : allHeaders,
            "multiValueHeaders": NSNull(),
            "pathParameters": NSNull(),
            "stageVariables": NSNull(),
            "body": body as Any? ?? NSNull(),
            "isBase64Encoded": isBase64Encoded
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AWSLambdaEvents.APIGatewayRequest.self, from: jsonData)
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
    func decodeResponseBody(_ response: APIGatewayResponse) -> String? {
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
        let router = Router(context: LambdaRequestContext.self)
        router.get("hello") { _, _ in
            "Hello, World!"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(path: "/hello")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response) == "Hello, World!")
    }

    @Test("Path parameters are extracted correctly")
    func testPathParameters() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.get("users/:id") { _, ctx in
            let id = ctx.parameters.get("id") ?? "unknown"
            return "User: \(id)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(path: "/users/123")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response) == "User: 123")
    }

    @Test("Query parameters are passed through")
    func testQueryParameters() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.get("search") { req, _ in
            // Query params should be accessible via request URI
            return "Path: \(req.uri.path)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(
            path: "/search",
            queryParams: ["q": "test", "page": "1"]
        )
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        // The URI should contain the path
        #expect(decodeResponseBody(response)?.contains("/search") == true)
    }

    @Test("Query parameters with special characters are URL encoded")
    func testQueryParametersURLEncoding() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.get("search") { req, _ in
            // Return the full URI string to verify encoding
            return "URI: \(req.uri.string)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(
            path: "/search",
            queryParams: ["q": "hello world", "filter": "a&b=c", "emoji": "🍍"]
        )
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        let body = decodeResponseBody(response) ?? ""
        // Spaces should be encoded as %20 or +
        #expect(body.contains("hello%20world") || body.contains("hello+world"))
        // & and = in values should be encoded
        #expect(body.contains("a%26b%3Dc") || body.contains("a%26b=c"))
    }

    @Test("POST with body works correctly")
    func testPostWithBody() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.post("echo") { req, _ in
            // Read request body
            var bodyData = Data()
            for try await buffer in req.body {
                bodyData.append(contentsOf: buffer.readableBytesView)
            }
            let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
            return "Received: \(bodyString)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(
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
        let router = Router(context: LambdaRequestContext.self)
        router.post("data") { req, _ in
            var bodyData = Data()
            for try await buffer in req.body {
                bodyData.append(contentsOf: buffer.readableBytesView)
            }
            let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
            return "Got: \(bodyString)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let originalBody = "Secret message"
        let base64Body = Data(originalBody.utf8).base64EncodedString()

        let request = try createAPIGatewayRequest(
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
        let router = Router(context: LambdaRequestContext.self)
        router.get("context") { _, ctx in
            let requestId = ctx.lambdaContext.requestId
            return "Request ID: \(requestId)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(path: "/context")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response)?.hasPrefix("Request ID:") == true)
    }

    @Test("API Gateway request is accessible in handlers")
    func testAPIGatewayRequestAccess() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.get("headers") { _, ctx in
            let customHeader = ctx.apiGatewayRequest.headers["X-Custom-Header"] ?? "not found"
            return "Header: \(customHeader)"
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(
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
        let router = Router(context: LambdaRequestContext.self)
        router.get("not-found") { _, _ in
            Response(status: .notFound)
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(path: "/not-found")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .notFound)
    }

    @Test("Response headers are passed through")
    func testResponseHeaders() async throws {
        let router = Router(context: LambdaRequestContext.self)
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
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(path: "/custom-headers")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(response.headers?["Content-Type"] == "application/json")
        #expect(response.headers?["X-Custom-Response"] == "custom-value")
    }

    @Test("Empty response body is handled")
    func testEmptyResponseBody() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.delete("item/:id") { _, _ in
            Response(status: .noContent)
        }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(path: "/item/123", method: "DELETE")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .noContent)
        #expect(response.body == nil || response.body?.isEmpty == true)
    }

    @Test("Response body is base64 encoded")
    func testResponseIsBase64Encoded() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.get("test") { _, _ in "Hello" }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(path: "/test")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(response.isBase64Encoded == true)
        #expect(response.body == "SGVsbG8=") // "Hello" in base64
    }

    // MARK: - LambdaApp Integration Tests

    @Test("addHummingbird integrates with LambdaApp")
    func testLambdaAppIntegration() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.get("test") { _, _ in "OK" }

        let app = LambdaApp()
            .addHummingbird(key: "api", router: router)

        // Verify handler was registered
        #expect(app.handlers.count == 1)
        #expect(app.handlers["api"] != nil)
    }

    @Test("HummingbirdLambda.App fluent builder works")
    func testFluentBuilder() async throws {
        let hbApp = HummingbirdLambda.App { router in
            router.get("hello") { _, _ in "Hello!" }
            router.post("create") { _, _ in Response(status: .created) }
        }

        let app = LambdaApp()
            .addHummingbird(key: "api", hbApp: hbApp)

        #expect(app.handlers.count == 1)
        #expect(app.handlers["api"] != nil)
    }

    // MARK: - Path Override Tests

    @Test("Path override works for mounting under prefix")
    func testPathOverride() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.get("users/:id") { _, ctx in
            let id = ctx.parameters.get("id") ?? "unknown"
            return "User: \(id)"
        }

        let adapter = HummingbirdLambdaAdapter()
        // Simulate mounting at /api - the stripped path would be /users/123
        let handler = adapter.bridge(router, pathOverride: "/users/123")

        // Original request path is /api/users/123 but we override to /users/123
        let request = try createAPIGatewayRequest(path: "/api/users/123")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .ok)
        #expect(decodeResponseBody(response) == "User: 123")
    }

    // MARK: - Multiple HTTP Methods Tests

    @Test("Different HTTP methods are routed correctly")
    func testMultipleMethods() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.get("resource") { _, _ in "GET" }
        router.post("resource") { _, _ in "POST" }
        router.put("resource") { _, _ in "PUT" }
        router.delete("resource") { _, _ in "DELETE" }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)
        let context = createMockContext()

        // Test GET
        let getRequest = try createAPIGatewayRequest(path: "/resource", method: "GET")
        let getResponse = try await handler(context, getRequest)
        #expect(decodeResponseBody(getResponse) == "GET")

        // Test POST
        let postRequest = try createAPIGatewayRequest(path: "/resource", method: "POST")
        let postResponse = try await handler(context, postRequest)
        #expect(decodeResponseBody(postResponse) == "POST")

        // Test PUT
        let putRequest = try createAPIGatewayRequest(path: "/resource", method: "PUT")
        let putResponse = try await handler(context, putRequest)
        #expect(decodeResponseBody(putResponse) == "PUT")

        // Test DELETE
        let deleteRequest = try createAPIGatewayRequest(path: "/resource", method: "DELETE")
        let deleteResponse = try await handler(context, deleteRequest)
        #expect(decodeResponseBody(deleteResponse) == "DELETE")
    }

    @Test("Route not found returns 404")
    func testRouteNotFound() async throws {
        let router = Router(context: LambdaRequestContext.self)
        router.get("existing") { _, _ in "OK" }

        let adapter = HummingbirdLambdaAdapter()
        let handler = adapter.bridge(router)

        let request = try createAPIGatewayRequest(path: "/nonexistent")
        let context = createMockContext()

        let response = try await handler(context, request)

        #expect(response.statusCode == .notFound)
    }
}

// MARK: - Mock Lambda Context

/// Mock LambdaContext for testing
struct MockLambdaContext: LambdaContext {
    let requestId: String
    let traceId: String?
    let invokedFunctionArn: String
    let deadline: Date
    let cognitoIdentity: String?
    let clientContext: String?
    let logger: Logger

    init(requestID: String, traceID: String?, invokedFunctionARN: String) {
        self.requestId = requestID
        self.traceId = traceID
        self.invokedFunctionArn = invokedFunctionARN
        self.deadline = Date().addingTimeInterval(30)
        self.cognitoIdentity = nil
        self.clientContext = nil

        var logger = Logger(label: "test")
        logger.logLevel = .trace
        self.logger = logger
    }
}
