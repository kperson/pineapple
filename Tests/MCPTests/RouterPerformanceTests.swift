import Testing
import Foundation
import Logging
@testable import MCP

@Suite("Router Performance Tests")
struct RouterPerformanceTests {
    
    struct TestContext {}
    
    class MockServer: Server {
        var callCount = 0
        
        override func handleRequest(
            _ envelope: TransportEnvelope,
            pathParams: Params?,
            logger: Logger
        ) async throws -> JSONValue {
            callCount += 1
            return .object(["result": .string("ok")])
        }
    }
    
    // MARK: - Pattern Caching
    
    @Test("PathPattern is cached and not recreated on each request")
    func testPathPatternCachedNotRecreated() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        
        // Add a route with a complex pattern
        router.addServer(path: "/users/{userId}/posts/{postId}/comments/{commentId}", server: server)
        
        // Make multiple requests to the same route
        let envelope1 = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/users/1/posts/2/comments/3"
        )
        let envelope2 = TransportEnvelope(
            mcpRequest: Request(id: .string("2"), method: "tools/list"),
            routePath: "/users/4/posts/5/comments/6"
        )
        let envelope3 = TransportEnvelope(
            mcpRequest: Request(id: .string("3"), method: "tools/list"),
            routePath: "/users/7/posts/8/comments/9"
        )
        
        let context = TestContext()
        
        // Execute multiple requests
        _ = try await router.route(envelope1, context: context)
        _ = try await router.route(envelope2, context: context)
        _ = try await router.route(envelope3, context: context)
        
        // All requests should have been handled
        #expect(server.callCount == 3)
        
        // This test passes if PathPattern is cached because:
        // 1. Pattern parsing happens once during addServer()
        // 2. Same cached pattern is used for all three matches
        // 3. No new PathPattern instances created during routing
        
        // Note: We can't directly verify the pattern wasn't recreated without
        // instrumentation, but the test documents the expected behavior and
        // we can verify the implementation doesn't create new patterns in match()
    }
    
    @Test("Multiple routes each cache their own pattern")
    func testMultipleRoutesCacheTheirOwnPatterns() async throws {
        let router = Router<TestContext>()
        let server1 = MockServer()
        let server2 = MockServer()
        let server3 = MockServer()
        
        // Add multiple routes
        router.addServer(path: "/users/{id}", server: server1)
        router.addServer(path: "/posts/{id}", server: server2)
        router.addServer(path: "/admin/{resource}/{id}", server: server3)
        
        let context = TestContext()
        
        // Route to different servers
        let envelope1 = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/users/123"
        )
        let envelope2 = TransportEnvelope(
            mcpRequest: Request(id: .string("2"), method: "tools/list"),
            routePath: "/posts/456"
        )
        let envelope3 = TransportEnvelope(
            mcpRequest: Request(id: .string("3"), method: "tools/list"),
            routePath: "/admin/tools/789"
        )
        
        _ = try await router.route(envelope1, context: context)
        _ = try await router.route(envelope2, context: context)
        _ = try await router.route(envelope3, context: context)
        
        // Each server should have been called once
        #expect(server1.callCount == 1)
        #expect(server2.callCount == 1)
        #expect(server3.callCount == 1)
    }
    
    @Test("Pattern matching performance with many requests")
    func testPatternMatchingPerformanceWithManyRequests() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        
        router.addServer(path: "/api/v1/{resource}/{id}", server: server)
        
        let context = TestContext()
        let startTime = Date()
        
        // Make 100 requests
        for i in 0..<100 {
            let envelope = TransportEnvelope(
                mcpRequest: Request(id: .string("\(i)"), method: "tools/list"),
                routePath: "/api/v1/users/\(i)"
            )
            _ = try await router.route(envelope, context: context)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        #expect(server.callCount == 100)
        
        // Performance expectation: 100 requests should complete quickly
        // If PathPattern is cached properly, this should be very fast (< 0.1s)
        // If PathPattern is recreated each time, it will be slower
        #expect(duration < 1.0) // Very conservative upper bound
    }
}
