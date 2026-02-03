import Testing
import Foundation
import Logging
@testable import MCP

@Suite("Router Tests")
struct RouterTests {
    
    struct TestContext {}
    
    class MockServer: Server {
        let identifier: String
        var callCount = 0
        var lastPathParams: Params?
        
        init(identifier: String) {
            self.identifier = identifier
        }
        
        override func handleRequest(
            _ envelope: TransportEnvelope,
            pathParams: Params?,
            logger: Logger
        ) async throws -> JSONValue {
            callCount += 1
            lastPathParams = pathParams
            return .object(["server": .string(identifier), "called": .bool(true)])
        }
    }
    
    // MARK: - Basic Routing
    
    @Test("Routes to correct server by path")
    func testRoutesToCorrectServerByPath() async throws {
        let router = Router<TestContext>()
        let server1 = MockServer(identifier: "users")
        let server2 = MockServer(identifier: "posts")
        
        router.addServer(path: "/users", server: server1)
        router.addServer(path: "/posts", server: server2)
        
        let context = TestContext()
        
        // Route to server1
        let envelope1 = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/users"
        )
        let response1 = try await router.route(envelope1, context: context)
        
        #expect(server1.callCount == 1)
        #expect(server2.callCount == 0)
        
        // Route to server2
        let envelope2 = TransportEnvelope(
            mcpRequest: Request(id: .string("2"), method: "tools/list"),
            routePath: "/posts"
        )
        let response2 = try await router.route(envelope2, context: context)
        
        #expect(server1.callCount == 1)
        #expect(server2.callCount == 1)
    }
    
    @Test("Routes with path parameters")
    func testRoutesWithPathParameters() async throws {
        let router = Router<TestContext>()
        let server = MockServer(identifier: "user-server")
        
        router.addServer(path: "/users/{userId}", server: server)
        
        let context = TestContext()
        let envelope = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/users/123"
        )
        
        _ = try await router.route(envelope, context: context)
        
        #expect(server.callCount == 1)
        #expect(server.lastPathParams?.string("userId") == "123")
    }
    
    @Test("Root path server matches only root")
    func testRootPathServerMatchesOnlyRoot() async throws {
        let router = Router<TestContext>()
        let server = MockServer(identifier: "root")
        
        router.addServer(server: server)  // Root path "/"
        
        let context = TestContext()
        
        // Should match root path
        let envelope1 = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/"
        )
        _ = try await router.route(envelope1, context: context)
        #expect(server.callCount == 1)
        
        // Should match empty path (normalized to root)
        let envelope2 = TransportEnvelope(
            mcpRequest: Request(id: .string("2"), method: "tools/list"),
            routePath: ""
        )
        _ = try await router.route(envelope2, context: context)
        #expect(server.callCount == 2)
        
        // Should NOT match other paths
        let envelope3 = TransportEnvelope(
            mcpRequest: Request(id: .string("3"), method: "tools/list"),
            routePath: "/users"
        )
        let response3 = try await router.route(envelope3, context: context)
        
        // Should get error, not route to root server
        if case .object(let obj) = response3.data,
           case .object = obj["error"] {
            // Expected - root doesn't match /users
        } else {
            #expect(Bool(false), "Expected error for non-root path")
        }
        
        #expect(server.callCount == 2) // Still 2 (only root paths)
    }
    
    // MARK: - Route Priority (First Match Wins)
    
    @Test("First matching route wins")
    func testFirstMatchingRouteWins() async throws {
        let router = Router<TestContext>()
        let server1 = MockServer(identifier: "first")
        let server2 = MockServer(identifier: "second")
        
        // Add routes in order
        router.addServer(path: "/users/{id}", server: server1)
        router.addServer(path: "/users/{userId}", server: server2)  // Same pattern, different param name
        
        let context = TestContext()
        let envelope = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/users/123"
        )
        
        _ = try await router.route(envelope, context: context)
        
        // First server should handle it
        #expect(server1.callCount == 1)
        #expect(server2.callCount == 0)
    }
    
    @Test("Specific routes before wildcard routes")
    func testSpecificRoutesBeforeWildcard() async throws {
        let router = Router<TestContext>()
        let specificServer = MockServer(identifier: "specific")
        let wildcardServer = MockServer(identifier: "wildcard")
        
        // Add specific route first, then wildcard
        router.addServer(path: "/users/admin", server: specificServer)
        router.addServer(path: "/users/{id}", server: wildcardServer)
        
        let context = TestContext()
        
        // Specific path should match specific server
        let envelope1 = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/users/admin"
        )
        _ = try await router.route(envelope1, context: context)
        
        #expect(specificServer.callCount == 1)
        #expect(wildcardServer.callCount == 0)
        
        // Other paths should match wildcard
        let envelope2 = TransportEnvelope(
            mcpRequest: Request(id: .string("2"), method: "tools/list"),
            routePath: "/users/123"
        )
        _ = try await router.route(envelope2, context: context)
        
        #expect(specificServer.callCount == 1)
        #expect(wildcardServer.callCount == 1)
    }
    
    @Test("Wildcard before specific routes takes precedence")
    func testWildcardBeforeSpecificTakesPrecedence() async throws {
        let router = Router<TestContext>()
        let wildcardServer = MockServer(identifier: "wildcard")
        let specificServer = MockServer(identifier: "specific")
        
        // Add wildcard BEFORE specific (order matters!)
        router.addServer(path: "/users/{id}", server: wildcardServer)
        router.addServer(path: "/users/admin", server: specificServer)
        
        let context = TestContext()
        let envelope = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/users/admin"
        )
        
        _ = try await router.route(envelope, context: context)
        
        // Wildcard wins because it was registered first
        #expect(wildcardServer.callCount == 1)
        #expect(specificServer.callCount == 0)
    }
    
    // MARK: - Multiple Parameters
    
    @Test("Routes with multiple path parameters")
    func testRoutesWithMultipleParameters() async throws {
        let router = Router<TestContext>()
        let server = MockServer(identifier: "posts")
        
        router.addServer(path: "/users/{userId}/posts/{postId}", server: server)
        
        let context = TestContext()
        let envelope = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/users/alice/posts/42"
        )
        
        _ = try await router.route(envelope, context: context)
        
        #expect(server.callCount == 1)
        #expect(server.lastPathParams?.string("userId") == "alice")
        #expect(server.lastPathParams?.string("postId") == "42")
    }
    
    @Test("Deep nesting with parameters")
    func testDeepNestingWithParameters() async throws {
        let router = Router<TestContext>()
        let server = MockServer(identifier: "deep")
        
        router.addServer(path: "/{tenant}/api/{version}/{resource}/{id}", server: server)
        
        let context = TestContext()
        let envelope = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/acme-corp/api/v2/users/123"
        )
        
        _ = try await router.route(envelope, context: context)
        
        #expect(server.callCount == 1)
        #expect(server.lastPathParams?.string("tenant") == "acme-corp")
        #expect(server.lastPathParams?.string("version") == "v2")
        #expect(server.lastPathParams?.string("resource") == "users")
        #expect(server.lastPathParams?.string("id") == "123")
    }
    
    // MARK: - Error Handling
    
    @Test("Returns error for unmatched path")
    func testReturnsErrorForUnmatchedPath() async throws {
        let router = Router<TestContext>()
        let server = MockServer(identifier: "users")
        
        router.addServer(path: "/users", server: server)
        
        let context = TestContext()
        let envelope = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/posts"  // No matching route
        )
        
        let response = try await router.route(envelope, context: context)
        
        // Should return error response
        if case .object(let obj) = response.data,
           case .object(let error)? = obj["error"],
           case .string(let message)? = error["message"] {
            #expect(message.contains("No MCP server found"))
            #expect(message.contains("/posts"))
        } else {
            #expect(Bool(false), "Expected error response")
        }
        
        #expect(server.callCount == 0)
    }
    
    @Test("Returns error for partial path match")
    func testReturnsErrorForPartialPathMatch() async throws {
        let router = Router<TestContext>()
        let server = MockServer(identifier: "users")
        
        router.addServer(path: "/users/{id}", server: server)
        
        let context = TestContext()
        
        // Too few segments
        let envelope1 = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/users"
        )
        let response1 = try await router.route(envelope1, context: context)
        
        if case .object(let obj) = response1.data,
           case .object = obj["error"] {
            // Expected error
        } else {
            #expect(Bool(false), "Expected error for too few segments")
        }
        
        // Too many segments
        let envelope2 = TransportEnvelope(
            mcpRequest: Request(id: .string("2"), method: "tools/list"),
            routePath: "/users/123/extra"
        )
        let response2 = try await router.route(envelope2, context: context)
        
        if case .object(let obj) = response2.data,
           case .object = obj["error"] {
            // Expected error
        } else {
            #expect(Bool(false), "Expected error for too many segments")
        }
        
        #expect(server.callCount == 0)
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty router returns error")
    func testEmptyRouterReturnsError() async throws {
        let router = Router<TestContext>()
        let context = TestContext()
        
        let envelope = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/any/path"
        )
        
        let response = try await router.route(envelope, context: context)
        
        if case .object(let obj) = response.data,
           case .object = obj["error"] {
            // Expected error
        } else {
            #expect(Bool(false), "Expected error response")
        }
    }
    
    @Test("Multiple routes to different servers")
    func testMultipleRoutesToDifferentServers() async throws {
        let router = Router<TestContext>()
        let server1 = MockServer(identifier: "files")
        let server2 = MockServer(identifier: "db")
        let server3 = MockServer(identifier: "admin")
        
        router.addServer(path: "/files/{customerId}", server: server1)
        router.addServer(path: "/db/{tenant}/{table}", server: server2)
        router.addServer(path: "/admin/tools", server: server3)
        
        let context = TestContext()
        
        // Route to each server
        let envelope1 = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/files/acme-corp"
        )
        _ = try await router.route(envelope1, context: context)
        
        let envelope2 = TransportEnvelope(
            mcpRequest: Request(id: .string("2"), method: "tools/list"),
            routePath: "/db/tenant1/users"
        )
        _ = try await router.route(envelope2, context: context)
        
        let envelope3 = TransportEnvelope(
            mcpRequest: Request(id: .string("3"), method: "tools/list"),
            routePath: "/admin/tools"
        )
        _ = try await router.route(envelope3, context: context)
        
        #expect(server1.callCount == 1)
        #expect(server2.callCount == 1)
        #expect(server3.callCount == 1)
    }
    
    @Test("Case-sensitive path matching")
    func testCaseSensitivePathMatching() async throws {
        let router = Router<TestContext>()
        let server = MockServer(identifier: "users")
        
        router.addServer(path: "/Users", server: server)
        
        let context = TestContext()
        
        // Exact case should match
        let envelope1 = TransportEnvelope(
            mcpRequest: Request(id: .string("1"), method: "tools/list"),
            routePath: "/Users"
        )
        _ = try await router.route(envelope1, context: context)
        #expect(server.callCount == 1)
        
        // Different case should NOT match
        let envelope2 = TransportEnvelope(
            mcpRequest: Request(id: .string("2"), method: "tools/list"),
            routePath: "/users"
        )
        let response2 = try await router.route(envelope2, context: context)
        
        if case .object(let obj) = response2.data,
           case .object = obj["error"] {
            // Expected error - case mismatch
        } else {
            #expect(Bool(false), "Expected error for case mismatch")
        }
        
        #expect(server.callCount == 1) // Still only 1 call
    }
    
    // MARK: - Fluent Builder
    
    @Test("Fluent builder returns router")
    func testFluentBuilderReturnsRouter() {
        let router = Router<TestContext>()
        let server1 = MockServer(identifier: "s1")
        let server2 = MockServer(identifier: "s2")
        
        let result = router
            .addServer(path: "/path1", server: server1)
            .addServer(path: "/path2", server: server2)
        
        #expect(result === router)
    }
    
    @Test("Fluent builder with configure closure")
    func testFluentBuilderWithConfigureClosure() {
        let router = Router<TestContext>()
        let server = MockServer(identifier: "test")
        
        let result = router.addServer(path: "/test", server: server) { route in
            // Configure route (empty for this test)
        }
        
        #expect(result === router)
    }
}
