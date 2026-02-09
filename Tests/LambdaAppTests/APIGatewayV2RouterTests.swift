import Testing
import Foundation
import Logging
import HTTPTypes
@testable import LambdaApp
@testable import AWSLambdaEvents

@Suite("APIGatewayV2Router Tests")
struct APIGatewayV2RouterTests {

    // MARK: - Path Stripping Tests

    @Test("Prefix match strips prefix and keeps leading slash")
    func testPrefixMatchStripsCorrectly() {
        let router = APIGatewayV2Router()
            .mount("/users", handler: { _, _, path in
                APIGatewayV2Response(statusCode: .ok, body: path)
            })

        let result = router.matchAndStrip("/users/123")
        #expect(result?.prefix == "/users")
        #expect(result?.strippedPath == "/123")
    }

    @Test("Exact prefix match returns root path")
    func testExactPrefixMatchReturnsRoot() {
        let router = APIGatewayV2Router()
            .mount("/users", handler: { _, _, path in
                APIGatewayV2Response(statusCode: .ok, body: path)
            })

        let result = router.matchAndStrip("/users")
        #expect(result?.prefix == "/users")
        #expect(result?.strippedPath == "/")
    }

    @Test("Root mount returns path unchanged")
    func testRootMountReturnsPathUnchanged() {
        let router = APIGatewayV2Router()
            .mount("/", handler: { _, _, path in
                APIGatewayV2Response(statusCode: .ok, body: path)
            })

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
        let router = APIGatewayV2Router()
            .mount("/api/v1", handler: { _, _, path in
                APIGatewayV2Response(statusCode: .ok, body: path)
            })

        let result = router.matchAndStrip("/api/v1/users/123")
        #expect(result?.prefix == "/api/v1")
        #expect(result?.strippedPath == "/users/123")
    }

    @Test("No match returns nil")
    func testNoMatchReturnsNil() {
        let router = APIGatewayV2Router()
            .mount("/users", handler: { _, _, path in
                APIGatewayV2Response(statusCode: .ok, body: path)
            })

        let result = router.matchAndStrip("/products/123")
        #expect(result == nil)
    }

    @Test("Partial prefix does not match")
    func testPartialPrefixDoesNotMatch() {
        let router = APIGatewayV2Router()
            .mount("/users", handler: { _, _, path in
                APIGatewayV2Response(statusCode: .ok, body: path)
            })

        let result = router.matchAndStrip("/usersabc")
        #expect(result == nil)
    }

    // MARK: - Route Priority Tests

    @Test("First matching route wins")
    func testFirstMatchingRouteWins() {
        let router = APIGatewayV2Router()
            .mount("/users/admin", handler: { _, _, _ in
                APIGatewayV2Response(statusCode: .ok)
            })
            .mount("/users", handler: { _, _, _ in
                APIGatewayV2Response(statusCode: .ok)
            })

        let result1 = router.matchAndStrip("/users/admin")
        #expect(result1?.prefix == "/users/admin")

        let result2 = router.matchAndStrip("/users/123")
        #expect(result2?.prefix == "/users")
    }

    @Test("Root as catch-all when registered last")
    func testRootAsCatchAll() {
        let router = APIGatewayV2Router()
            .mount("/users", handler: { _, _, _ in APIGatewayV2Response(statusCode: .ok) })
            .mount("/products", handler: { _, _, _ in APIGatewayV2Response(statusCode: .ok) })
            .mount("/", handler: { _, _, _ in APIGatewayV2Response(statusCode: .ok) })

        let result1 = router.matchAndStrip("/users/123")
        #expect(result1?.prefix == "/users")

        let result2 = router.matchAndStrip("/products/abc")
        #expect(result2?.prefix == "/products")

        let result3 = router.matchAndStrip("/unknown/path")
        #expect(result3?.prefix == "/")
    }

    // MARK: - Prefix Normalization Tests

    @Test("Prefix normalization adds leading slash")
    func testPrefixNormalizationAddsLeadingSlash() {
        let router = APIGatewayV2Router()
            .mount("users", handler: { _, _, _ in APIGatewayV2Response(statusCode: .ok) })

        let result = router.matchAndStrip("/users/123")
        #expect(result?.prefix == "/users")
        #expect(result?.strippedPath == "/123")
    }

    @Test("Prefix normalization removes trailing slash")
    func testPrefixNormalizationRemovesTrailingSlash() {
        let router = APIGatewayV2Router()
            .mount("/users/", handler: { _, _, _ in APIGatewayV2Response(statusCode: .ok) })

        let result = router.matchAndStrip("/users/123")
        #expect(result?.prefix == "/users")
        #expect(result?.strippedPath == "/123")
    }

    // MARK: - Fluent Builder Tests

    @Test("Fluent builder returns router")
    func testFluentBuilderReturnsRouter() {
        let router = APIGatewayV2Router()

        let result = router
            .mount("/a", handler: { _, _, _ in APIGatewayV2Response(statusCode: .ok) })
            .mount("/b", handler: { _, _, _ in APIGatewayV2Response(statusCode: .ok) })

        #expect(result === router)
    }

    // MARK: - Handler Execution Tests

    @Test("Handler receives correct stripped path")
    func testHandlerReceivesCorrectStrippedPath() async throws {
        var receivedPath: String?

        let router = APIGatewayV2Router()
            .mount("/api", handler: { _, _, path in
                receivedPath = path
                return APIGatewayV2Response(statusCode: .ok)
            })

        let handler = router.build()
        let context = MockLambdaContext()
        let request = createMockV2Request(path: "/api/users/123")

        _ = try await handler(context, request)

        #expect(receivedPath == "/users/123")
    }

    @Test("Handler receives original request unchanged")
    func testHandlerReceivesOriginalRequest() async throws {
        var receivedRequest: APIGatewayV2Request?

        let router = APIGatewayV2Router()
            .mount("/api", handler: { _, request, _ in
                receivedRequest = request
                return APIGatewayV2Response(statusCode: .ok)
            })

        let handler = router.build()
        let context = MockLambdaContext()
        let request = createMockV2Request(path: "/api/users/123")

        _ = try await handler(context, request)

        #expect(receivedRequest?.rawPath == "/api/users/123")
    }

    @Test("Unmatched route returns 404")
    func testUnmatchedRouteReturns404() async throws {
        let router = APIGatewayV2Router()
            .mount("/users", handler: { _, _, _ in APIGatewayV2Response(statusCode: .ok) })

        let handler = router.build()
        let context = MockLambdaContext()
        let request = createMockV2Request(path: "/unknown")

        let response = try await handler(context, request)

        #expect(response.statusCode == HTTPResponse.Status.notFound)
    }

    @Test("Empty router returns 404")
    func testEmptyRouterReturns404() async throws {
        let router = APIGatewayV2Router()

        let handler = router.build()
        let context = MockLambdaContext()
        let request = createMockV2Request(path: "/anything")

        let response = try await handler(context, request)

        #expect(response.statusCode == HTTPResponse.Status.notFound)
    }

    // MARK: - Helpers

    func createMockV2Request(path: String) -> APIGatewayV2Request {
        let json: [String: Any] = [
            "version": "2.0",
            "routeKey": "$default",
            "rawPath": path,
            "rawQueryString": "",
            "headers": [:],
            "requestContext": [
                "accountId": "123456789012",
                "apiId": "test-api",
                "domainName": "test.execute-api.us-east-1.amazonaws.com",
                "domainPrefix": "test",
                "stage": "$default",
                "requestId": UUID().uuidString,
                "http": [
                    "method": "GET",
                    "path": path,
                    "protocol": "HTTP/1.1",
                    "sourceIp": "127.0.0.1",
                    "userAgent": "test-agent"
                ],
                "time": "12/Mar/2020:19:03:58 +0000",
                "timeEpoch": 1583348638390
            ],
            "isBase64Encoded": false
        ]

        let jsonData = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(APIGatewayV2Request.self, from: jsonData)
    }
}

// MockLambdaContext is defined in APIGatewayRouterTests.swift
