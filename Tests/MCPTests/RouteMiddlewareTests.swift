import Testing
@testable import MCP
import Logging

@Suite("Route Middleware Tests")
struct RouteMiddlewareTests {

    // MARK: - Test Fixtures

    struct TestContext {
        let requestId: String
        let metadata: [String: String]

        init(requestId: String = "test-request", metadata: [String: String] = [:]) {
            self.requestId = requestId
            self.metadata = metadata
        }
    }

    actor MiddlewareTracker {
        var executionCount = 0
        var executedMiddlewareNames: [String] = []
        var lastEnvelope: TransportEnvelope?
        var lastContext: TestContext?

        func record(name: String, envelope: TransportEnvelope, context: TestContext) {
            executionCount += 1
            executedMiddlewareNames.append(name)
            lastEnvelope = envelope
            lastContext = context
        }

        func reset() {
            executionCount = 0
            executedMiddlewareNames = []
            lastEnvelope = nil
            lastContext = nil
        }
    }

    // Helper to create tracking middleware
    func trackingMiddleware(
        name: String,
        tracker: MiddlewareTracker,
        response: PreRequestMiddlewareResponse<[String: Any]>
    ) -> AnyPreRequestMiddleware<TransportEnvelope, TestContext> {
        return PreRequestMiddlewareHelpers.from { (context: TestContext, envelope: TransportEnvelope) in
            await tracker.record(name: name, envelope: envelope, context: context)
            return response
        }.eraseToAnyPreRequestMiddleware()
    }

    // Helper to create accepting middleware
    func acceptingMiddleware(
        metadata: [String: Any]
    ) -> AnyPreRequestMiddleware<TransportEnvelope, TestContext> {
        return PreRequestMiddlewareHelpers.from { (_: TestContext, _: TransportEnvelope) in
            .accept(metadata: metadata)
        }.eraseToAnyPreRequestMiddleware()
    }

    // Helper to create rejecting middleware
    func rejectingMiddleware(
        error: MCPError
    ) -> AnyPreRequestMiddleware<TransportEnvelope, TestContext> {
        return PreRequestMiddlewareHelpers.from { (_: TestContext, _: TransportEnvelope) in
            .reject(error)
        }.eraseToAnyPreRequestMiddleware()
    }

    // Helper to create passthrough middleware
    func passthroughMiddleware() -> AnyPreRequestMiddleware<TransportEnvelope, TestContext> {
        return PreRequestMiddlewareHelpers.from { (_: TestContext, _: TransportEnvelope) in
            .passthrough
        }.eraseToAnyPreRequestMiddleware()
    }

    // Mock server that tracks if handler was called
    class MockServer: Server {
        var handlerCalled = false
        var receivedParams: Params?
        var receivedMetadata: [String: Any] = [:]

        init() {
            super.init(logger: Logger(label: "test"))
        }

        override func handleRequest(
            _ envelope: TransportEnvelope,
            pathParams: Params?,
            logger: Logger
        ) async throws -> JSONValue {
            handlerCalled = true
            receivedParams = pathParams
            receivedMetadata = envelope.metadata

            // Return a simple tools/list response
            return .object([
                "tools": .array([])
            ])
        }
    }

    // MARK: - 1. Router Generic Context Tests

    @Test("Router routes with test context")
    func routerWithTestContext() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        router.addServer(path: "/test", server: server)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
    }

    @Test("Router matches path patterns")
    func routerMatchesPathPattern() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        router.addServer(path: "/files/{userId}", server: server)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/files/user-123")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
        #expect(server.receivedParams?.string("userId") == "user-123")
    }

    @Test("Router returns error on no match")
    func routerNoMatchReturnsError() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        router.addServer(path: "/files/{userId}", server: server)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/admin/tools")
        let context = TestContext()

        let response = try await router.route(envelope, context: context)

        #expect(!server.handlerCalled)

        // Verify error response contains "No MCP server found"
        if case .object(let obj) = response.data,
           case .object(let error)? = obj["error"],
           case .string(let message)? = error["message"] {
            #expect(message.contains("No MCP server found"))
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Multiple routes match first")
    func multipleRoutesMatchFirst() async throws {
        let router = Router<TestContext>()
        let server1 = MockServer()
        let server2 = MockServer()

        router.addServer(path: "/files/{id}", server: server1)
        router.addServer(path: "/files/special", server: server2)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/files/special")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        // First route matches (pattern /files/{id} with id="special")
        #expect(server1.handlerCalled)
        #expect(!server2.handlerCalled)
        #expect(server1.receivedParams?.string("id") == "special")
    }

    @Test("Router works with no middleware")
    func routerWithNoMiddleware() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        router.addServer(path: "/test", server: server)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        let response = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
        // Verify response is successful (not an error)
        if case .object(let obj) = response.data {
            #expect(obj["error"] == nil)
        }
    }

    @Test("Router works with empty path")
    func routerWithEmptyPath() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        router.addServer(path: "/", server: server)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
    }

    @Test("Router extracts multiple parameters")
    func routerWithMultipleParameters() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        router.addServer(path: "/api/{version}/users/{userId}", server: server)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/api/v1/users/user-123")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
        #expect(server.receivedParams?.string("version") == "v1")
        #expect(server.receivedParams?.string("userId") == "user-123")
    }

    // MARK: - 2. Route Middleware Execution Tests

    @Test("Route middleware executes on match")
    func routeMiddlewareExecutesOnMatch() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        let tracker = MiddlewareTracker()

        router.addServer(path: "/files/{id}", server: server) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middleware1", tracker: tracker, response: .passthrough)
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/files/123")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        let count = await tracker.executionCount
        #expect(count == 1)
        #expect(server.handlerCalled)
    }

    @Test("Route middleware does not execute on no match")
    func routeMiddlewareDoesNotExecuteOnNoMatch() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        let tracker = MiddlewareTracker()

        router.addServer(path: "/files/{id}", server: server) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middleware1", tracker: tracker, response: .passthrough)
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/admin/tools")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        let count = await tracker.executionCount
        #expect(count == 0)
        #expect(!server.handlerCalled)
    }

    @Test("Multiple route middleware execute in chain")
    func multipleRouteMiddlewareChain() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        let tracker = MiddlewareTracker()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middleware1", tracker: tracker, response: .accept(metadata: ["key1": "value1"]))
            )
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middleware2", tracker: tracker, response: .accept(metadata: ["key2": "value2"]))
            )
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middleware3", tracker: tracker, response: .passthrough)
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        let count = await tracker.executionCount
        let names = await tracker.executedMiddlewareNames

        #expect(count == 3)
        #expect(names == ["middleware1", "middleware2", "middleware3"])
        #expect(server.handlerCalled)

        // Verify metadata accumulated
        #expect(server.receivedMetadata["key1"] as? String == "value1")
        #expect(server.receivedMetadata["key2"] as? String == "value2")
    }

    @Test("Route middleware accept enriches with metadata")
    func routeMiddlewareAcceptWithMetadata() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(
                self.acceptingMiddleware(metadata: ["userId": "user-123", "role": "admin"])
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
        #expect(server.receivedMetadata["userId"] as? String == "user-123")
        #expect(server.receivedMetadata["role"] as? String == "admin")
    }

    @Test("Route middleware passthrough leaves envelope unchanged")
    func routeMiddlewarePassthrough() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(self.passthroughMiddleware())
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
        #expect(server.receivedMetadata.isEmpty)
    }

    @Test("Route middleware reject prevents handler execution")
    func routeMiddlewareReject() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        let error = MCPError(code: .invalidRequest, message: "Access denied")

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(self.rejectingMiddleware(error: error))
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        let response = try await router.route(envelope, context: context)

        #expect(!server.handlerCalled)

        // Verify error response
        if case .object(let obj) = response.data,
           case .object(let errorObj)? = obj["error"],
           case .string(let message)? = errorObj["message"] {
            #expect(message == "Access denied")
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Route middleware reject stops chain execution")
    func routeMiddlewareRejectStopsChain() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        let tracker = MiddlewareTracker()
        let error = MCPError(code: .invalidRequest, message: "Rejected")

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middleware1", tracker: tracker, response: .passthrough)
            )
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middleware2", tracker: tracker, response: .reject(error))
            )
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middleware3", tracker: tracker, response: .passthrough)
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        let count = await tracker.executionCount
        let names = await tracker.executedMiddlewareNames

        // Only first two middleware should run
        #expect(count == 2)
        #expect(names == ["middleware1", "middleware2"])
        #expect(!server.handlerCalled)
    }

    @Test("Different routes have different middleware")
    func differentRoutesHaveDifferentMiddleware() async throws {
        let router = Router<TestContext>()
        let serverA = MockServer()
        let serverB = MockServer()
        let tracker = MiddlewareTracker()

        router.addServer(path: "/routeA", server: serverA) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middlewareA1", tracker: tracker, response: .passthrough)
            )
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middlewareA2", tracker: tracker, response: .passthrough)
            )
        }

        router.addServer(path: "/routeB", server: serverB) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "middlewareB", tracker: tracker, response: .passthrough)
            )
        }

        // Request to route A
        let requestA = Request(id: .string("1"), method: "tools/list")
        let envelopeA = TransportEnvelope(mcpRequest: requestA, routePath: "/routeA")
        let context = TestContext()

        _ = try await router.route(envelopeA, context: context)

        var names = await tracker.executedMiddlewareNames
        #expect(names == ["middlewareA1", "middlewareA2"])
        #expect(serverA.handlerCalled)

        // Reset tracker
        await tracker.reset()

        // Request to route B
        let requestB = Request(id: .string("2"), method: "tools/list")
        let envelopeB = TransportEnvelope(mcpRequest: requestB, routePath: "/routeB")

        _ = try await router.route(envelopeB, context: context)

        names = await tracker.executedMiddlewareNames
        #expect(names == ["middlewareB"])
        #expect(serverB.handlerCalled)
    }

    @Test("Route middleware handles async execution")
    func routeMiddlewareWithAsyncExecution() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        let asyncMiddleware = PreRequestMiddlewareHelpers.from { (_: TestContext, envelope: TransportEnvelope) in
            // Simulate async work
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return .accept(metadata: ["asyncKey": "asyncValue"])
        }.eraseToAnyPreRequestMiddleware()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(asyncMiddleware)
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
        #expect(server.receivedMetadata["asyncKey"] as? String == "asyncValue")
    }

    @Test("Route middleware metadata overwrite with last write wins")
    func routeMiddlewareMetadataOverwrite() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(
                self.acceptingMiddleware(metadata: ["key": "value1"])
            )
            route.usePreRequestMiddleware(
                self.acceptingMiddleware(metadata: ["key": "value2"])
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
        // Last write wins
        #expect(server.receivedMetadata["key"] as? String == "value2")
    }

    @Test("Empty route middleware chain works")
    func emptyRouteMiddlewareChain() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/test", server: server) { route in
            // Configure closure but add no middleware
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
    }

    // MARK: - 3. Params Availability Tests

    @Test("Params nil before routing")
    func paramsNilBeforeRouting() {
        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")

        #expect(envelope.pathParams == nil)
    }

    @Test("Params populated after route match")
    func paramsPopulatedAfterRouteMatch() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/customers/{customerId}/files", server: server)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/customers/cust-123/files")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
        #expect(server.receivedParams?.string("customerId") == "cust-123")
    }

    @Test("Params available in route middleware")
    func paramsAvailableInRouteMiddleware() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        var capturedUserId: String?
        var capturedFileId: String?

        let captureMiddleware = PreRequestMiddlewareHelpers.from { (_: TestContext, envelope: TransportEnvelope) in
            capturedUserId = envelope.pathParams?.string("userId")
            capturedFileId = envelope.pathParams?.string("fileId")
            return .passthrough
        }.eraseToAnyPreRequestMiddleware()

        router.addServer(path: "/users/{userId}/files/{fileId}", server: server) { route in
            route.usePreRequestMiddleware(captureMiddleware)
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/users/user-123/files/file-456")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(capturedUserId == "user-123")
        #expect(capturedFileId == "file-456")
    }

    @Test("Params preserved through middleware chain")
    func paramsPreservedThroughMiddlewareChain() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        var params1: Params?
        var params2: Params?
        var params3: Params?

        let captureMiddleware1 = PreRequestMiddlewareHelpers.from { (_: TestContext, envelope: TransportEnvelope) in
            params1 = envelope.pathParams
            return .passthrough
        }.eraseToAnyPreRequestMiddleware()

        let captureMiddleware2 = PreRequestMiddlewareHelpers.from { (_: TestContext, envelope: TransportEnvelope) in
            params2 = envelope.pathParams
            return .accept(metadata: ["key": "value"])
        }.eraseToAnyPreRequestMiddleware()

        let captureMiddleware3 = PreRequestMiddlewareHelpers.from { (_: TestContext, envelope: TransportEnvelope) in
            params3 = envelope.pathParams
            return .passthrough
        }.eraseToAnyPreRequestMiddleware()

        router.addServer(path: "/test/{id}", server: server) { route in
            route.usePreRequestMiddleware(captureMiddleware1)
            route.usePreRequestMiddleware(captureMiddleware2)
            route.usePreRequestMiddleware(captureMiddleware3)
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test/123")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        // All middleware should see the same Params
        #expect(params1?.string("id") == "123")
        #expect(params2?.string("id") == "123")
        #expect(params3?.string("id") == "123")
    }

    @Test("Params preserved in envelope combine")
    func paramsInEnvelopeCombine() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        var capturedParamsAfterCombine: Params?

        let middleware = PreRequestMiddlewareHelpers.from { (_: TestContext, envelope: TransportEnvelope) in
            // After accept, combine() is called which should preserve Params
            let result = PreRequestMiddlewareResponse<[String: Any]>.accept(metadata: ["key": "value"])
            return result
        }.eraseToAnyPreRequestMiddleware()

        let captureMiddleware = PreRequestMiddlewareHelpers.from { (_: TestContext, envelope: TransportEnvelope) in
            capturedParamsAfterCombine = envelope.pathParams
            return .passthrough
        }.eraseToAnyPreRequestMiddleware()

        router.addServer(path: "/test/{id}", server: server) { route in
            route.usePreRequestMiddleware(middleware)
            route.usePreRequestMiddleware(captureMiddleware)
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test/456")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(capturedParamsAfterCombine?.string("id") == "456")
    }

    @Test("Multiple params extracted correctly")
    func multipleParamsExtracted() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/api/{version}/users/{userId}/files/{fileId}", server: server)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(
            mcpRequest: request,
            routePath: "/api/v1/users/user-123/files/file-456"
        )
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
        #expect(server.receivedParams?.string("version") == "v1")
        #expect(server.receivedParams?.string("userId") == "user-123")
        #expect(server.receivedParams?.string("fileId") == "file-456")
    }

    // MARK: - 4. Route Builder Fluent API Tests

    @Test("Route builder supports chaining")
    func routeBuilderChaining() async throws {
        let router = Router<TestContext>()
        let server = MockServer()
        let tracker = MiddlewareTracker()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "m1", tracker: tracker, response: .passthrough)
            )
            .usePreRequestMiddleware(
                self.trackingMiddleware(name: "m2", tracker: tracker, response: .passthrough)
            )
            .usePreRequestMiddleware(
                self.trackingMiddleware(name: "m3", tracker: tracker, response: .passthrough)
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        let count = await tracker.executionCount
        let names = await tracker.executedMiddlewareNames

        #expect(count == 3)
        #expect(names == ["m1", "m2", "m3"])
    }

    @Test("Route builder works without closure")
    func routeBuilderWithoutClosure() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        // Add route without configure closure
        router.addServer(path: "/test", server: server)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
    }

    @Test("Route builder auto-registers route")
    func routeBuilderAutoRegistration() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        // Configure closure completes, route should auto-register
        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(self.passthroughMiddleware())
            // No explicit .register() call
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        _ = try await router.route(envelope, context: context)

        #expect(server.handlerCalled)
    }

    @Test("Multiple routes with builders work independently")
    func multipleRoutesWithBuilders() async throws {
        let router = Router<TestContext>()
        let server1 = MockServer()
        let server2 = MockServer()
        let server3 = MockServer()
        let tracker = MiddlewareTracker()

        router.addServer(path: "/route1", server: server1) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "r1m1", tracker: tracker, response: .passthrough)
            )
        }
        router.addServer(path: "/route2", server: server2) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "r2m1", tracker: tracker, response: .passthrough)
            )
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "r2m2", tracker: tracker, response: .passthrough)
            )
        }
        router.addServer(path: "/route3", server: server3) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "r3m1", tracker: tracker, response: .passthrough)
            )
        }

        let context = TestContext()

        // Test route 1
        let request1 = Request(id: .string("1"), method: "tools/list")
        let envelope1 = TransportEnvelope(mcpRequest: request1, routePath: "/route1")
        _ = try await router.route(envelope1, context: context)

        var names = await tracker.executedMiddlewareNames
        #expect(names == ["r1m1"])
        #expect(server1.handlerCalled)

        await tracker.reset()

        // Test route 2
        let request2 = Request(id: .string("2"), method: "tools/list")
        let envelope2 = TransportEnvelope(mcpRequest: request2, routePath: "/route2")
        _ = try await router.route(envelope2, context: context)

        names = await tracker.executedMiddlewareNames
        #expect(names == ["r2m1", "r2m2"])
        #expect(server2.handlerCalled)
    }

    @Test("Route builder returns router for chaining")
    func routeBuilderReturnsRouterForChaining() async throws {
        let router = Router<TestContext>()
        let server1 = MockServer()
        let server2 = MockServer()

        // Chain multiple addServer calls
        router
            .addServer(path: "/route1", server: server1) { route in
                route.usePreRequestMiddleware(self.passthroughMiddleware())
            }
            .addServer(path: "/route2", server: server2) { route in
                route.usePreRequestMiddleware(self.passthroughMiddleware())
            }

        let context = TestContext()

        // Both routes should be registered
        let request1 = Request(id: .string("1"), method: "tools/list")
        let envelope1 = TransportEnvelope(mcpRequest: request1, routePath: "/route1")
        _ = try await router.route(envelope1, context: context)
        #expect(server1.handlerCalled)

        let request2 = Request(id: .string("2"), method: "tools/list")
        let envelope2 = TransportEnvelope(mcpRequest: request2, routePath: "/route2")
        _ = try await router.route(envelope2, context: context)
        #expect(server2.handlerCalled)
    }

    // MARK: - 5. MiddlewareChain Execute Tests

    @Test("Execute returns accept with envelope")
    func executeReturnsAcceptWithEnvelope() async throws {
        let chain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        chain.use(self.acceptingMiddleware(metadata: ["key": "value"]))

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        let result = try await chain.execute(context: context, envelope: envelope)

        switch result {
        case .accept(let enrichedEnvelope):
            #expect(enrichedEnvelope.metadata["key"] as? String == "value")
        case .passthrough, .reject:
            Issue.record("Expected accept result")
        }
    }

    @Test("Execute returns passthrough with envelope")
    func executeReturnsPassthroughWithEnvelope() async throws {
        let chain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        chain.use(self.passthroughMiddleware())

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        let result = try await chain.execute(context: context, envelope: envelope)

        switch result {
        case .passthrough(let returnedEnvelope):
            #expect(returnedEnvelope.routePath == "/test")
        case .accept, .reject:
            Issue.record("Expected passthrough result")
        }
    }

    @Test("Execute returns reject")
    func executeReturnsReject() async throws {
        let chain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        let error = MCPError(code: .invalidRequest, message: "Test error")
        chain.use(self.rejectingMiddleware(error: error))

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        let result = try await chain.execute(context: context, envelope: envelope)

        switch result {
        case .reject(let receivedError):
            #expect(receivedError.message == "Test error")
        case .accept, .passthrough:
            Issue.record("Expected reject result")
        }
    }

    @Test("Execute with empty chain returns passthrough")
    func executeWithEmptyChain() async throws {
        let chain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        let result = try await chain.execute(context: context, envelope: envelope)

        switch result {
        case .passthrough(let returnedEnvelope):
            #expect(returnedEnvelope.routePath == "/test")
        case .accept, .reject:
            Issue.record("Expected passthrough for empty chain")
        }
    }

    @Test("Execute enriches envelope")
    func executeEnvelopeEnrichment() async throws {
        let chain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        chain.use(self.acceptingMiddleware(metadata: ["key1": "value1"]))
        chain.use(self.acceptingMiddleware(metadata: ["key2": "value2"]))
        chain.use(self.acceptingMiddleware(metadata: ["key3": "value3"]))

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        let result = try await chain.execute(context: context, envelope: envelope)

        switch result {
        case .accept(let enrichedEnvelope):
            #expect(enrichedEnvelope.metadata["key1"] as? String == "value1")
            #expect(enrichedEnvelope.metadata["key2"] as? String == "value2")
            #expect(enrichedEnvelope.metadata["key3"] as? String == "value3")
        case .passthrough, .reject:
            Issue.record("Expected accept result")
        }
    }

    @Test("Execute does not throw on reject")
    func executeDoesNotThrow() async throws {
        let chain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        let error = MCPError(code: .invalidRequest, message: "Test error")
        chain.use(self.rejectingMiddleware(error: error))

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        // execute() should not throw even when middleware rejects
        let result = try await chain.execute(context: context, envelope: envelope)

        switch result {
        case .reject:
            // Success - got reject without exception
            break
        case .accept, .passthrough:
            Issue.record("Expected reject result")
        }
    }

    @Test("Execute vs envelope comparison")
    func executeVsEnvelopeComparison() async throws {
        let chain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        chain.use(self.acceptingMiddleware(metadata: ["key": "value"]))

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        // Using envelope() method
        let envelopeResult = try await chain.envelope(envelope, context: context)

        // Using execute() method
        let executeResult = try await chain.execute(context: context, envelope: envelope)

        switch executeResult {
        case .accept(let enrichedEnvelope):
            #expect(enrichedEnvelope.metadata["key"] as? String == envelopeResult.metadata["key"] as? String)
        case .passthrough, .reject:
            Issue.record("Expected accept result")
        }
    }

    @Test("Execute catches MCPError and returns reject")
    func executeWithMCPErrorCatch() async throws {
        let chain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()

        // Middleware that throws MCPError
        let throwingMiddleware = PreRequestMiddlewareHelpers.from { (_: TestContext, _: TransportEnvelope) -> PreRequestMiddlewareResponse<[String: Any]> in
            throw MCPError(code: .internalError, message: "Thrown error")
        }.eraseToAnyPreRequestMiddleware()

        chain.use(throwingMiddleware)

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        // execute() should catch the MCPError and return .reject()
        let result = try await chain.execute(context: context, envelope: envelope)

        switch result {
        case .reject(let error):
            #expect(error.message == "Thrown error")
        case .accept, .passthrough:
            Issue.record("Expected reject result from thrown error")
        }
    }

    // MARK: - 6. Integration Tests

    @Test("Global and route middleware execute in correct order")
    func globalAndRouteMiddlewareOrder() async throws {
        // Simulate global middleware by running chain before router
        let globalChain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        globalChain.use(self.acceptingMiddleware(metadata: ["global": "globalValue"]))

        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(
                self.acceptingMiddleware(metadata: ["route": "routeValue"])
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        var envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        // Run global middleware first
        envelope = try await globalChain.envelope(envelope, context: context)

        // Then route (which runs route middleware)
        _ = try await router.route(envelope, context: context)

        // Verify both metadata present
        #expect(server.receivedMetadata["global"] as? String == "globalValue")
        #expect(server.receivedMetadata["route"] as? String == "routeValue")
    }

    @Test("Global middleware reject prevents route execution")
    func globalMiddlewareRejectBeforeRoute() async throws {
        let globalChain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        let error = MCPError(code: .invalidRequest, message: "Global reject")
        globalChain.use(self.rejectingMiddleware(error: error))

        let router = Router<TestContext>()
        let server = MockServer()
        let tracker = MiddlewareTracker()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(
                self.trackingMiddleware(name: "route", tracker: tracker, response: .passthrough)
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        let envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        // Global middleware rejects
        do {
            _ = try await globalChain.envelope(envelope, context: context)
            Issue.record("Should have thrown")
        } catch {
            // Expected
        }

        // Route middleware should not have run
        let count = await tracker.executionCount
        #expect(count == 0)
        #expect(!server.handlerCalled)
    }

    @Test("Route middleware reject after global middleware")
    func routeMiddlewareRejectAfterGlobal() async throws {
        let globalChain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        globalChain.use(self.acceptingMiddleware(metadata: ["global": "value"]))

        let router = Router<TestContext>()
        let server = MockServer()
        let error = MCPError(code: .invalidRequest, message: "Route reject")

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(self.rejectingMiddleware(error: error))
        }

        let request = Request(id: .string("1"), method: "tools/list")
        var envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        // Global middleware accepts
        envelope = try await globalChain.envelope(envelope, context: context)
        #expect(envelope.metadata["global"] as? String == "value")

        // Route middleware rejects
        let response = try await router.route(envelope, context: context)

        #expect(!server.handlerCalled)

        // Verify error response
        if case .object(let obj) = response.data,
           case .object(let errorObj)? = obj["error"],
           case .string(let message)? = errorObj["message"] {
            #expect(message == "Route reject")
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Params only available in route middleware not global")
    func paramsOnlyInRouteMiddleware() async throws {
        let globalChain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        var globalParams: Params?
        var routeParams: Params?

        let globalMiddleware = PreRequestMiddlewareHelpers.from { (_: TestContext, envelope: TransportEnvelope) in
            globalParams = envelope.pathParams
            return .passthrough
        }.eraseToAnyPreRequestMiddleware()

        globalChain.use(globalMiddleware)

        let router = Router<TestContext>()
        let server = MockServer()

        let routeMiddleware = PreRequestMiddlewareHelpers.from { (_: TestContext, envelope: TransportEnvelope) in
            routeParams = envelope.pathParams
            return .passthrough
        }.eraseToAnyPreRequestMiddleware()

        router.addServer(path: "/test/{id}", server: server) { route in
            route.usePreRequestMiddleware(routeMiddleware)
        }

        let request = Request(id: .string("1"), method: "tools/list")
        var envelope = TransportEnvelope(mcpRequest: request, routePath: "/test/123")
        let context = TestContext()

        // Run global middleware (before routing)
        envelope = try await globalChain.envelope(envelope, context: context)

        // Run router (which matches path and runs route middleware)
        _ = try await router.route(envelope, context: context)

        // Global middleware should see nil Params
        #expect(globalParams == nil)

        // Route middleware should see Params
        #expect(routeParams?.string("id") == "123")
    }

    @Test("Multi-tenant auth scenario")
    func multiTenantAuthScenario() async throws {
        let router = Router<TestContext>()
        let server = MockServer()

        // Simulate tenant-aware auth middleware
        let tenantAuthMiddleware = PreRequestMiddlewareHelpers.from { (context: TestContext, envelope: TransportEnvelope) in
            guard let customerId = envelope.pathParams?.string("customerId") else {
                return .reject(MCPError(code: .invalidRequest, message: "Missing customerId"))
            }

            // Check if user has access to this customer (simulated)
            let userId = context.metadata["userId"] ?? "unknown"
            let hasAccess = userId == "authorized-user" && customerId == "cust-123"

            if !hasAccess {
                return .reject(MCPError(code: .invalidRequest, message: "Access denied"))
            }

            return .accept(metadata: ["customerId": customerId])
        }.eraseToAnyPreRequestMiddleware()

        router.addServer(path: "/customers/{customerId}/files", server: server) { route in
            route.usePreRequestMiddleware(tenantAuthMiddleware)
        }

        // Test authorized user
        let request1 = Request(id: .string("1"), method: "tools/list")
        let envelope1 = TransportEnvelope(mcpRequest: request1, routePath: "/customers/cust-123/files")
        let authorizedContext = TestContext(metadata: ["userId": "authorized-user"])

        _ = try await router.route(envelope1, context: authorizedContext)

        // Should succeed
        #expect(server.handlerCalled)

        // Reset server
        server.handlerCalled = false

        // Test unauthorized user
        let request2 = Request(id: .string("2"), method: "tools/list")
        let envelope2 = TransportEnvelope(mcpRequest: request2, routePath: "/customers/cust-123/files")
        let unauthorizedContext = TestContext(metadata: ["userId": "unauthorized-user"])

        let response2 = try await router.route(envelope2, context: unauthorizedContext)

        // Should be rejected
        #expect(!server.handlerCalled)

        if case .object(let obj) = response2.data,
           case .object(let errorObj)? = obj["error"],
           case .string(let message)? = errorObj["message"] {
            #expect(message == "Access denied")
        } else {
            Issue.record("Expected error response")
        }
    }

    @Test("Route-specific auth on admin path")
    func routeSpecificAuthOnAdminPath() async throws {
        let router = Router<TestContext>()
        let adminServer = MockServer()
        let publicServer = MockServer()

        // Admin middleware requires admin role
        let adminAuthMiddleware = PreRequestMiddlewareHelpers.from { (context: TestContext, _: TransportEnvelope) in
            let role = context.metadata["role"] ?? ""
            if role != "admin" {
                return .reject(MCPError(code: .invalidRequest, message: "Admin access required"))
            }
            return .passthrough
        }.eraseToAnyPreRequestMiddleware()

        router.addServer(path: "/admin/{tenant}", server: adminServer) { route in
            route.usePreRequestMiddleware(adminAuthMiddleware)
        }

        router.addServer(path: "/public/files", server: publicServer)

        // Test admin path with admin user
        let adminRequest = Request(id: .string("1"), method: "tools/list")
        let adminEnvelope = TransportEnvelope(mcpRequest: adminRequest, routePath: "/admin/tenant-123")
        let adminContext = TestContext(metadata: ["role": "admin"])

        _ = try await router.route(adminEnvelope, context: adminContext)
        #expect(adminServer.handlerCalled)

        // Test admin path with non-admin user
        adminServer.handlerCalled = false
        let nonAdminContext = TestContext(metadata: ["role": "user"])
        let response = try await router.route(adminEnvelope, context: nonAdminContext)

        #expect(!adminServer.handlerCalled)
        if case .object(let obj) = response.data,
           case .object? = obj["error"] {
            // Expected error
        } else {
            Issue.record("Expected error response")
        }

        // Test public path (no auth required)
        let publicRequest = Request(id: .string("2"), method: "tools/list")
        let publicEnvelope = TransportEnvelope(mcpRequest: publicRequest, routePath: "/public/files")

        _ = try await router.route(publicEnvelope, context: nonAdminContext)
        #expect(publicServer.handlerCalled)
    }

    @Test("Metadata flows through layers")
    func metadataFlowThroughLayers() async throws {
        let globalChain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        globalChain.use(self.acceptingMiddleware(metadata: ["requestId": "123"]))

        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(
                self.acceptingMiddleware(metadata: ["userId": "user-456"])
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        var envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        // Global middleware
        envelope = try await globalChain.envelope(envelope, context: context)

        // Route middleware
        _ = try await router.route(envelope, context: context)

        // Handler should see both
        #expect(server.receivedMetadata["requestId"] as? String == "123")
        #expect(server.receivedMetadata["userId"] as? String == "user-456")
    }

    @Test("Complex routing scenario with multiple versioned routes")
    func complexRoutingScenario() async throws {
        let router = Router<TestContext>()
        let server1 = MockServer()
        let server2 = MockServer()
        let server3 = MockServer()

        router.addServer(path: "/api/v1/users/{userId}", server: server1) { route in
            route.usePreRequestMiddleware(
                self.acceptingMiddleware(metadata: ["version": "v1"])
            )
        }

        router.addServer(path: "/api/v2/users/{userId}/files/{fileId}", server: server2) { route in
            route.usePreRequestMiddleware(
                self.acceptingMiddleware(metadata: ["version": "v2"])
            )
        }

        router.addServer(path: "/health", server: server3)

        let context = TestContext()

        // Test route 1
        let request1 = Request(id: .string("1"), method: "tools/list")
        let envelope1 = TransportEnvelope(mcpRequest: request1, routePath: "/api/v1/users/user-123")
        _ = try await router.route(envelope1, context: context)

        #expect(server1.handlerCalled)
        #expect(server1.receivedParams?.string("userId") == "user-123")
        #expect(server1.receivedMetadata["version"] as? String == "v1")

        // Test route 2
        let request2 = Request(id: .string("2"), method: "tools/list")
        let envelope2 = TransportEnvelope(mcpRequest: request2, routePath: "/api/v2/users/user-456/files/file-789")
        _ = try await router.route(envelope2, context: context)

        #expect(server2.handlerCalled)
        #expect(server2.receivedParams?.string("userId") == "user-456")
        #expect(server2.receivedParams?.string("fileId") == "file-789")
        #expect(server2.receivedMetadata["version"] as? String == "v2")

        // Test route 3
        let request3 = Request(id: .string("3"), method: "tools/list")
        let envelope3 = TransportEnvelope(mcpRequest: request3, routePath: "/health")
        _ = try await router.route(envelope3, context: context)

        #expect(server3.handlerCalled)
        // Route with no parameters should have empty Params (not nil)
        #expect(server3.receivedParams != nil)
        // Verify it's truly empty by checking that a non-existent key returns nil
        #expect(server3.receivedParams?.string("anyKey") == nil)
        #expect(server3.receivedMetadata.isEmpty)
    }

    @Test("Global passthrough with route accept")
    func globalPassthroughRouteAccept() async throws {
        let globalChain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        globalChain.use(self.passthroughMiddleware())

        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(
                self.acceptingMiddleware(metadata: ["route": "routeValue"])
            )
        }

        let request = Request(id: .string("1"), method: "tools/list")
        var envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        // Global passthrough
        envelope = try await globalChain.envelope(envelope, context: context)

        // Route accepts
        _ = try await router.route(envelope, context: context)

        // Only route metadata should be present
        #expect(server.receivedMetadata["route"] as? String == "routeValue")
        #expect(server.receivedMetadata.count == 1)
    }

    @Test("All middleware passthrough")
    func allMiddlewarePassthrough() async throws {
        let globalChain = PreRequestMiddlewareChain<TransportEnvelope, TestContext>()
        globalChain.use(self.passthroughMiddleware())

        let router = Router<TestContext>()
        let server = MockServer()

        router.addServer(path: "/test", server: server) { route in
            route.usePreRequestMiddleware(self.passthroughMiddleware())
            route.usePreRequestMiddleware(self.passthroughMiddleware())
        }

        let request = Request(id: .string("1"), method: "tools/list")
        var envelope = TransportEnvelope(mcpRequest: request, routePath: "/test")
        let context = TestContext()

        // Global passthrough
        envelope = try await globalChain.envelope(envelope, context: context)

        // Route passthroughs
        _ = try await router.route(envelope, context: context)

        // No metadata should be added
        #expect(server.handlerCalled)
        #expect(server.receivedMetadata.isEmpty)
    }
}
