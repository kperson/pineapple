import Testing
import Foundation
import Logging
import HTTPTypes
@testable import LambdaApp
@testable import AWSLambdaEvents

@Suite("APIGatewayRouter Tests")
struct APIGatewayRouterTests {

    // MARK: - Path Stripping Tests

    @Test("Prefix match strips prefix and keeps leading slash")
    func testPrefixMatchStripsCorrectly() {
        let router = APIGatewayRouter()
            .mount("/users", handler: { _, _, path in
                APIGatewayResponse(statusCode: .ok, body: path)
            })

        let result = router.matchAndStrip("/users/123")
        #expect(result?.prefix == "/users")
        #expect(result?.strippedPath == "/123")
    }

    @Test("Exact prefix match returns root path")
    func testExactPrefixMatchReturnsRoot() {
        let router = APIGatewayRouter()
            .mount("/users", handler: { _, _, path in
                APIGatewayResponse(statusCode: .ok, body: path)
            })

        let result = router.matchAndStrip("/users")
        #expect(result?.prefix == "/users")
        #expect(result?.strippedPath == "/")
    }

    @Test("Root mount returns path unchanged")
    func testRootMountReturnsPathUnchanged() {
        let router = APIGatewayRouter()
            .mount("/", handler: { _, _, path in
                APIGatewayResponse(statusCode: .ok, body: path)
            })

        // Test various paths
        let result1 = router.matchAndStrip("/foo")
        #expect(result1?.prefix == "/")
        #expect(result1?.strippedPath == "/foo")

        let result2 = router.matchAndStrip("/foo/bar/baz")
        #expect(result2?.prefix == "/")
        #expect(result2?.strippedPath == "/foo/bar/baz")

        let result3 = router.matchAndStrip("/")
        #expect(result3?.prefix == "/")
        #expect(result3?.strippedPath == "/")
    }

    @Test("Deep prefix strips correctly")
    func testDeepPrefixStripsCorrectly() {
        let router = APIGatewayRouter()
            .mount("/api/v1", handler: { _, _, path in
                APIGatewayResponse(statusCode: .ok, body: path)
            })

        let result = router.matchAndStrip("/api/v1/users/123")
        #expect(result?.prefix == "/api/v1")
        #expect(result?.strippedPath == "/users/123")
    }

    @Test("No match returns nil")
    func testNoMatchReturnsNil() {
        let router = APIGatewayRouter()
            .mount("/users", handler: { _, _, path in
                APIGatewayResponse(statusCode: .ok, body: path)
            })

        let result = router.matchAndStrip("/products/123")
        #expect(result == nil)
    }

    @Test("Partial prefix does not match")
    func testPartialPrefixDoesNotMatch() {
        let router = APIGatewayRouter()
            .mount("/users", handler: { _, _, path in
                APIGatewayResponse(statusCode: .ok, body: path)
            })

        // "/usersabc" should NOT match "/users"
        let result = router.matchAndStrip("/usersabc")
        #expect(result == nil)
    }

    // MARK: - Edge Cases from Discussion

    @Test("All edge cases from design discussion")
    func testAllEdgeCases() {
        let router = APIGatewayRouter()
            .mount("/users", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })
            .mount("/api/v1", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })
            .mount("/", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })

        // | Mount | Request | Stripped Path |
        // |-------|---------|---------------|
        // | /users | /users/123 | /123 |
        let case1 = router.matchAndStrip("/users/123")
        #expect(case1?.strippedPath == "/123")

        // | /users | /users | / |
        let case2 = router.matchAndStrip("/users")
        #expect(case2?.strippedPath == "/")

        // | /api/v1 | /api/v1/foo/bar | /foo/bar |
        let case3 = router.matchAndStrip("/api/v1/foo/bar")
        #expect(case3?.strippedPath == "/foo/bar")
    }

    @Test("Root mount edge cases")
    func testRootMountEdgeCases() {
        let router = APIGatewayRouter()
            .mount("/", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })

        // | / | /foo | /foo |
        let case1 = router.matchAndStrip("/foo")
        #expect(case1?.strippedPath == "/foo")

        // | / | / | / |
        let case2 = router.matchAndStrip("/")
        #expect(case2?.strippedPath == "/")
    }

    // MARK: - Route Priority Tests

    @Test("First matching route wins")
    func testFirstMatchingRouteWins() {
        var matchedRoute = ""

        let router = APIGatewayRouter()
            .mount("/users/admin", handler: { _, _, _ in
                matchedRoute = "admin"
                return APIGatewayResponse(statusCode: .ok)
            })
            .mount("/users", handler: { _, _, _ in
                matchedRoute = "users"
                return APIGatewayResponse(statusCode: .ok)
            })

        // /users/admin should match the more specific route first
        let result1 = router.matchAndStrip("/users/admin")
        #expect(result1?.prefix == "/users/admin")

        // /users/123 should match /users
        let result2 = router.matchAndStrip("/users/123")
        #expect(result2?.prefix == "/users")
    }

    @Test("Root as catch-all when registered last")
    func testRootAsCatchAll() {
        let router = APIGatewayRouter()
            .mount("/users", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })
            .mount("/products", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })
            .mount("/", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })

        // Specific routes match first
        let result1 = router.matchAndStrip("/users/123")
        #expect(result1?.prefix == "/users")

        let result2 = router.matchAndStrip("/products/abc")
        #expect(result2?.prefix == "/products")

        // Unknown paths fall through to root
        let result3 = router.matchAndStrip("/unknown/path")
        #expect(result3?.prefix == "/")
    }

    // MARK: - Prefix Normalization Tests

    @Test("Prefix normalization adds leading slash")
    func testPrefixNormalizationAddsLeadingSlash() {
        let router = APIGatewayRouter()
            .mount("users", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })

        let result = router.matchAndStrip("/users/123")
        #expect(result?.prefix == "/users")
        #expect(result?.strippedPath == "/123")
    }

    @Test("Prefix normalization removes trailing slash")
    func testPrefixNormalizationRemovesTrailingSlash() {
        let router = APIGatewayRouter()
            .mount("/users/", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })

        let result = router.matchAndStrip("/users/123")
        #expect(result?.prefix == "/users")
        #expect(result?.strippedPath == "/123")
    }

    // MARK: - Fluent Builder Tests

    @Test("Fluent builder returns router")
    func testFluentBuilderReturnsRouter() {
        let router = APIGatewayRouter()

        let result = router
            .mount("/a", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })
            .mount("/b", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })

        #expect(result === router)
    }

    // MARK: - Handler Execution Tests

    @Test("Handler receives correct stripped path")
    func testHandlerReceivesCorrectStrippedPath() async throws {
        var receivedPath: String?

        let router = APIGatewayRouter()
            .mount("/api", handler: { _, _, path in
                receivedPath = path
                return APIGatewayResponse(statusCode: .ok)
            })

        let handler = router.build()
        let context = MockLambdaContext()
        let request = createMockRequest(path: "/api/users/123")

        _ = try await handler(context, request)

        #expect(receivedPath == "/users/123")
    }

    @Test("Handler receives original request unchanged")
    func testHandlerReceivesOriginalRequest() async throws {
        var receivedRequest: APIGatewayRequest?

        let router = APIGatewayRouter()
            .mount("/api", handler: { _, request, _ in
                receivedRequest = request
                return APIGatewayResponse(statusCode: .ok)
            })

        let handler = router.build()
        let context = MockLambdaContext()
        let request = createMockRequest(path: "/api/users/123")

        _ = try await handler(context, request)

        // Original path should be preserved
        #expect(receivedRequest?.path == "/api/users/123")
    }

    @Test("Unmatched route returns 404")
    func testUnmatchedRouteReturns404() async throws {
        let router = APIGatewayRouter()
            .mount("/users", handler: { _, _, _ in APIGatewayResponse(statusCode: .ok) })

        let handler = router.build()
        let context = MockLambdaContext()
        let request = createMockRequest(path: "/unknown")

        let response = try await handler(context, request)

        #expect(response.statusCode == HTTPResponse.Status.notFound)
    }

    @Test("Empty router returns 404")
    func testEmptyRouterReturns404() async throws {
        let router = APIGatewayRouter()

        let handler = router.build()
        let context = MockLambdaContext()
        let request = createMockRequest(path: "/anything")

        let response = try await handler(context, request)

        #expect(response.statusCode == HTTPResponse.Status.notFound)
    }

    // MARK: - Helpers

    func createMockRequest(path: String) -> APIGatewayRequest {
        let json: [String: Any] = [
            "httpMethod": "GET",
            "resource": path,
            "path": path,
            "requestContext": [
                "resourceId": "test",
                "apiId": "test-api",
                "domainName": "test.example.com",
                "resourcePath": path,
                "httpMethod": "GET",
                "requestId": UUID().uuidString,
                "accountId": "123456789012",
                "stage": "test",
                "identity": [
                    "sourceIp": "127.0.0.1"
                ],
                "path": path
            ],
            "headers": [:],
            "multiValueHeaders": [:],
            "body": NSNull(),
            "isBase64Encoded": false
        ]

        let jsonData = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(APIGatewayRequest.self, from: jsonData)
    }
}

// MARK: - Mock Lambda Context

struct MockLambdaContext: LambdaContext {
    let requestId: String = UUID().uuidString
    let traceId: String? = "test-trace"
    let invokedFunctionArn: String = "arn:aws:lambda:us-east-1:123456789012:function:test"
    let deadline: Date = Date().addingTimeInterval(30)
    let cognitoIdentity: String? = nil
    let clientContext: String? = nil
    let logger: Logger = {
        var logger = Logger(label: "test")
        logger.logLevel = .trace
        return logger
    }()
}
