import Testing
import Foundation
@testable import MCP

@Suite("Post-Response Middleware Tests")
struct PostResponseMiddlewareTests {
    
    // MARK: - Test Fixtures
    
    /// Simple test response type
    struct TestResponse: Equatable {
        var statusCode: Int
        var headers: [String: String]
        var body: String
    }
    
    /// Test context type
    struct TestContext {
        let userId: String
        let requestId: String
        
        static let empty = TestContext(userId: "", requestId: "")
    }
    
    /// Test envelope for requests
    struct TestRequestEnvelope {
        let mcpRequest: Request
        var metadata: [String: Any]
        
        func combine(with meta: [String: Any]) -> TestRequestEnvelope {
            var updated = self
            updated.metadata.merge(meta) { _, new in new }
            return updated
        }
    }
    
    // MARK: - Helper Methods
    
    func createTestRequest() -> Request {
        Request(id: .string("test-1"), method: "tools/call")
    }
    
    func createRequestEnvelope() -> TransportEnvelope {
        TransportEnvelope(
            mcpRequest: createTestRequest(),
            routePath: "/test"
        )
    }
    
    func createResponseEnvelope(
        response: TestResponse,
        startTime: Date = Date().addingTimeInterval(-1),
        endTime: Date = Date()
    ) -> ResponseEnvelope<TestResponse> {
        ResponseEnvelope(
            request: TransportEnvelope(
                mcpRequest: Request(id: .string("test-1"), method: "tools/call"),
                routePath: "/test"
            ),
            response: response,
            timing: RequestTiming(startTime: startTime, endTime: endTime)
        )
    }
    
    func createTestResponse() -> TestResponse {
        TestResponse(
            statusCode: 200,
            headers: [:],
            body: "{}"
        )
    }
    
    // MARK: - PostResponseMiddlewareResponse Tests
    
    @Test("PostResponseMiddlewareResponse accept returns modified response")
    func testAcceptReturnsModifiedResponse() {
        // Given: A modified response
        let modifiedResponse = TestResponse(
            statusCode: 201,
            headers: ["X-Modified": "true"],
            body: "{\"modified\": true}"
        )
        
        // When: Creating accept response
        let response = PostResponseMiddlewareResponse.accept(modifiedResponse)
        
        // Then: Should match accept case with response
        if case .accept(let resp) = response {
            #expect(resp.statusCode == 201)
            #expect(resp.headers["X-Modified"] == "true")
            #expect(resp.body == "{\"modified\": true}")
        } else {
            #expect(Bool(false), "Expected .accept, got \(response)")
        }
    }
    
    @Test("PostResponseMiddlewareResponse passthrough returns original")
    func testPassthroughReturnsOriginal() {
        // When: Creating passthrough response
        let response: PostResponseMiddlewareResponse<TestResponse> = .passthrough
        
        // Then: Should match passthrough case
        if case .passthrough = response {
            // Success
        } else {
            #expect(Bool(false), "Expected .passthrough, got \(response)")
        }
    }
    
    // MARK: - FuncPostResponseMiddleware Tests
    
    @Test("FuncPostResponseMiddleware executes closure with accept")
    func testFuncMiddlewareExecutesClosureWithAccept() async throws {
        // Given: A middleware that modifies the response
        let middleware = FuncPostResponseMiddleware<TestResponse, TestContext> { context, envelope in
            var modified = envelope.response
            modified.headers["X-User-ID"] = context.userId
            return .accept(modified)
        }
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext(userId: "user-123", requestId: "req-456")
        
        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)
        
        // Then: Should return accept with modified response
        if case .accept(let modifiedResponse) = response {
            #expect(modifiedResponse.headers["X-User-ID"] == "user-123")
        } else {
            #expect(Bool(false), "Expected .accept")
        }
    }
    
    @Test("FuncPostResponseMiddleware executes closure with passthrough")
    func testFuncMiddlewareExecutesClosureWithPassthrough() async throws {
        // Given: A middleware that just logs (passthrough)
        let middleware = FuncPostResponseMiddleware<TestResponse, TestContext> { _, _ in
            // Just passthrough
            return .passthrough
        }
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext.empty
        
        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)
        
        // Then: Should return passthrough
        if case .passthrough = response {
            // Success
        } else {
            #expect(Bool(false), "Expected .passthrough")
        }
    }
    
    @Test("FuncPostResponseMiddleware can access timing information")
    func testFuncMiddlewareAccessesTiming() async throws {
        // Given: A middleware that reads timing
        var capturedDuration: TimeInterval?
        let middleware = FuncPostResponseMiddleware<TestResponse, TestContext> { _, envelope in
            capturedDuration = envelope.timing.duration
            return .passthrough
        }
        
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(1.5) // 1.5 seconds
        let envelope = createResponseEnvelope(
            response: createTestResponse(),
            startTime: startTime,
            endTime: endTime
        )
        let context = TestContext.empty
        
        // When: Calling the middleware
        _ = try await middleware.handle(context: context, envelope: envelope)
        
        // Then: Should have accessed timing
        #expect(capturedDuration != nil)
        #expect(abs(capturedDuration! - 1.5) < 0.001) // Within 1ms tolerance
    }
    
    @Test("FuncPostResponseMiddleware can access request metadata")
    func testFuncMiddlewareAccessesRequestMetadata() async throws {
        // Given: A middleware that reads request data
        var capturedMethod: String?
        let middleware = FuncPostResponseMiddleware<TestResponse, TestContext> { _, envelope in
            capturedMethod = envelope.request.mcpRequest.method
            return .passthrough
        }
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext.empty
        
        // When: Calling the middleware
        _ = try await middleware.handle(context: context, envelope: envelope)
        
        // Then: Should have accessed request
        #expect(capturedMethod == "tools/call")
    }
    
    // MARK: - PostResponseMiddlewareHelpers Tests
    
    @Test("PostResponseMiddlewareHelpers creates middleware from closure")
    func testHelpersCreatesMiddlewareFromClosure() async throws {
        // Given: Creating middleware via helper
        let middleware = PostResponseMiddlewareHelpers.from { (context: TestContext, envelope: ResponseEnvelope<TestResponse>) in
            var modified = envelope.response
            modified.headers["X-Request-ID"] = context.requestId
            modified.headers["X-Duration-Ms"] = "\(envelope.timing.duration * 1000)"
            return .accept(modified)
        }
        
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(0.5)
        let envelope = createResponseEnvelope(
            response: createTestResponse(),
            startTime: startTime,
            endTime: endTime
        )
        let context = TestContext(userId: "user-1", requestId: "req-789")
        
        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)
        
        // Then: Should work correctly
        if case .accept(let modifiedResponse) = response {
            #expect(modifiedResponse.headers["X-Request-ID"] == "req-789")
            #expect(modifiedResponse.headers["X-Duration-Ms"] == "500.0")
        } else {
            #expect(Bool(false), "Expected .accept")
        }
    }
    
    @Test("PostResponseMiddlewareHelpers infers types from closure")
    func testHelpersInfersTypes() async throws {
        // Given: Creating middleware with inferred types (no explicit annotations)
        let middleware = PostResponseMiddlewareHelpers.from { (ctx: TestContext, env: ResponseEnvelope<TestResponse>) in
            // Types inferred
            var resp = env.response
            resp.body = "{\"user\": \"\(ctx.userId)\"}"
            return .accept(resp)
        }
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext(userId: "inferred-user", requestId: "req-1")
        
        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)
        
        // Then: Types should have been correctly inferred
        if case .accept(let modifiedResponse) = response {
            #expect(modifiedResponse.body == "{\"user\": \"inferred-user\"}")
        } else {
            #expect(Bool(false), "Expected .accept")
        }
    }
    
    // MARK: - AnyPostResponseMiddleware Tests
    
    @Test("AnyPostResponseMiddleware wraps concrete middleware")
    func testAnyMiddlewareWrapsConcrete() async throws {
        // Given: A concrete middleware
        struct AddHeaderMiddleware: PostResponseMiddleware {
            func handle(
                context: TestContext,
                envelope: ResponseEnvelope<TestResponse>
            ) async throws -> PostResponseMiddlewareResponse<TestResponse> {
                var modified = envelope.response
                modified.headers["X-Custom"] = "value"
                return .accept(modified)
            }
        }
        
        let concrete = AddHeaderMiddleware()
        let wrapped = AnyPostResponseMiddleware(concrete)
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext.empty
        
        // When: Calling wrapped middleware
        let response = try await wrapped.handle(context: context, envelope: envelope)
        
        // Then: Should work the same as the original
        if case .accept(let modifiedResponse) = response {
            #expect(modifiedResponse.headers["X-Custom"] == "value")
        } else {
            #expect(Bool(false), "Expected .accept")
        }
    }
    
    @Test("AnyPostResponseMiddleware eraseToAnyPostResponseMiddleware extension")
    func testEraseToAnyExtension() async throws {
        // Given: A concrete middleware
        struct TestMiddleware: PostResponseMiddleware {
            func handle(
                context: TestContext,
                envelope: ResponseEnvelope<TestResponse>
            ) async throws -> PostResponseMiddlewareResponse<TestResponse> {
                return .passthrough
            }
        }
        
        let middleware = TestMiddleware()
        let erased = middleware.eraseToAnyPostResponseMiddleware()
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext.empty
        
        // When: Calling erased middleware
        let response = try await erased.handle(context: context, envelope: envelope)
        
        // Then: Should work correctly
        if case .passthrough = response {
            // Success
        } else {
            #expect(Bool(false), "Expected .passthrough")
        }
    }
    
    @Test("AnyPostResponseMiddleware allows heterogeneous collections")
    func testAnyMiddlewareAllowsHeterogeneousCollections() async throws {
        // Given: Different middleware types
        struct Middleware1: PostResponseMiddleware {
            func handle(
                context: TestContext,
                envelope: ResponseEnvelope<TestResponse>
            ) async throws -> PostResponseMiddlewareResponse<TestResponse> {
                var resp = envelope.response
                resp.headers["M1"] = "true"
                return .accept(resp)
            }
        }
        
        let m1 = Middleware1()
        let m2 = PostResponseMiddlewareHelpers.from { (_: TestContext, _: ResponseEnvelope<TestResponse>) in
            return .passthrough
        }
        
        // When: Storing in heterogeneous array
        let middlewares: [AnyPostResponseMiddleware<TestResponse, TestContext>] = [
            m1.eraseToAnyPostResponseMiddleware(),
            m2.eraseToAnyPostResponseMiddleware()
        ]
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext.empty
        
        // Then: All should be callable
        #expect(middlewares.count == 2)
        
        let response1 = try await middlewares[0].handle(context: context, envelope: envelope)
        if case .accept(let resp) = response1 {
            #expect(resp.headers["M1"] == "true")
        } else {
            #expect(Bool(false), "Expected .accept from first middleware")
        }
        
        let response2 = try await middlewares[1].handle(context: context, envelope: envelope)
        if case .passthrough = response2 {
            // Success
        } else {
            #expect(Bool(false), "Expected .passthrough from second middleware")
        }
    }
    
    // MARK: - PostResponseMiddlewareChain Tests
    
    @Test("PostResponseMiddlewareChain empty chain returns original response")
    func testEmptyChainReturnsOriginal() async throws {
        // Given: An empty chain
        let chain = PostResponseMiddlewareChain<TestResponse, TestContext>()
        
        let originalResponse = TestResponse(
            statusCode: 200,
            headers: ["X-Original": "true"],
            body: "{\"original\": true}"
        )
        let envelope = createResponseEnvelope(response: originalResponse)
        let context = TestContext.empty
        
        // When: Running the chain
        let finalResponse = try await chain.execute(context: context, envelope: envelope)
        
        // Then: Should return original response unchanged
        #expect(finalResponse == originalResponse)
    }
    
    @Test("PostResponseMiddlewareChain single middleware with accept")
    func testSingleMiddlewareWithAccept() async throws {
        // Given: Chain with one middleware
        let chain = PostResponseMiddlewareChain<TestResponse, TestContext>()
        chain.use(PostResponseMiddlewareHelpers.from { (ctx: TestContext, env: ResponseEnvelope<TestResponse>) in
            var modified = env.response
            modified.headers["X-Modified"] = "true"
            modified.headers["X-User"] = ctx.userId
            return .accept(modified)
        })
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext(userId: "user-456", requestId: "req-1")
        
        // When: Running the chain
        let finalResponse = try await chain.execute(context: context, envelope: envelope)
        
        // Then: Should have modified response
        #expect(finalResponse.headers["X-Modified"] == "true")
        #expect(finalResponse.headers["X-User"] == "user-456")
    }
    
    @Test("PostResponseMiddlewareChain single middleware with passthrough")
    func testSingleMiddlewareWithPassthrough() async throws {
        // Given: Chain with passthrough middleware
        let chain = PostResponseMiddlewareChain<TestResponse, TestContext>()
        chain.use(PostResponseMiddlewareHelpers.from { (_: TestContext, _: ResponseEnvelope<TestResponse>) in
            return .passthrough
        })
        
        let originalResponse = TestResponse(
            statusCode: 201,
            headers: ["X-Test": "value"],
            body: "{\"test\": true}"
        )
        let envelope = createResponseEnvelope(response: originalResponse)
        let context = TestContext.empty
        
        // When: Running the chain
        let finalResponse = try await chain.execute(context: context, envelope: envelope)
        
        // Then: Should return original response
        #expect(finalResponse == originalResponse)
    }
    
    @Test("PostResponseMiddlewareChain multiple middleware transformations")
    func testMultipleMiddlewareTransformations() async throws {
        // Given: Chain with multiple transforming middleware
        let chain = PostResponseMiddlewareChain<TestResponse, TestContext>()
        
        // Middleware 1: Add request ID header
        chain.use(PostResponseMiddlewareHelpers.from { (ctx, env: ResponseEnvelope<TestResponse>) in
            var resp = env.response
            resp.headers["X-Request-ID"] = ctx.requestId
            return .accept(resp)
        })
        
        // Middleware 2: Add timing header
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            var resp = env.response
            resp.headers["X-Duration-Ms"] = "\(env.timing.duration * 1000)"
            return .accept(resp)
        })
        
        // Middleware 3: Add user header
        chain.use(PostResponseMiddlewareHelpers.from { (ctx, env: ResponseEnvelope<TestResponse>) in
            var resp = env.response
            resp.headers["X-User-ID"] = ctx.userId
            return .accept(resp)
        })
        
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(0.25)
        let envelope = createResponseEnvelope(
            response: createTestResponse(),
            startTime: startTime,
            endTime: endTime
        )
        let context = TestContext(userId: "user-789", requestId: "req-123")
        
        // When: Running the chain
        let finalResponse = try await chain.execute(context: context, envelope: envelope)
        
        // Then: Should have all headers from all middleware
        #expect(finalResponse.headers["X-Request-ID"] == "req-123")
        #expect(finalResponse.headers["X-Duration-Ms"] == "250.0")
        #expect(finalResponse.headers["X-User-ID"] == "user-789")
    }
    
    @Test("PostResponseMiddlewareChain mixed accept and passthrough")
    func testMixedAcceptAndPassthrough() async throws {
        // Given: Chain with mix of accept and passthrough
        let chain = PostResponseMiddlewareChain<TestResponse, TestContext>()
        
        // Middleware 1: Modify
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            var resp = env.response
            resp.headers["M1"] = "modified"
            return .accept(resp)
        })
        
        // Middleware 2: Passthrough (just logging)
        chain.use(PostResponseMiddlewareHelpers.from { (_: TestContext, _: ResponseEnvelope<TestResponse>) in
            // Just observe, don't modify
            return .passthrough
        })
        
        // Middleware 3: Modify
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            var resp = env.response
            resp.headers["M3"] = "modified"
            return .accept(resp)
        })
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext.empty
        
        // When: Running the chain
        let finalResponse = try await chain.execute(context: context, envelope: envelope)
        
        // Then: Should have modifications from M1 and M3
        #expect(finalResponse.headers["M1"] == "modified")
        #expect(finalResponse.headers["M3"] == "modified")
    }
    
    @Test("PostResponseMiddlewareChain response flows through chain")
    func testResponseFlowsThroughChain() async throws {
        // Given: Chain that progressively builds response
        let chain = PostResponseMiddlewareChain<TestResponse, TestContext>()
        
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            var resp = env.response
            resp.statusCode = 201
            return .accept(resp)
        })
        
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            // Should see statusCode 201 from previous middleware
            var resp = env.response
            resp.body = "{\"status\": \(resp.statusCode)}"
            return .accept(resp)
        })
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext.empty
        
        // When: Running the chain
        let finalResponse = try await chain.execute(context: context, envelope: envelope)
        
        // Then: Should reflect changes from both middleware
        #expect(finalResponse.statusCode == 201)
        #expect(finalResponse.body == "{\"status\": 201}")
    }
    
    @Test("PostResponseMiddlewareChain preserves timing across chain")
    func testPreservesTimingAcrossChain() async throws {
        // Given: Chain with multiple middleware
        let chain = PostResponseMiddlewareChain<TestResponse, TestContext>()
        
        var capturedTimings: [TimeInterval] = []
        
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            capturedTimings.append(env.timing.duration)
            return .passthrough
        })
        
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            capturedTimings.append(env.timing.duration)
            return .passthrough
        })
        
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            capturedTimings.append(env.timing.duration)
            return .passthrough
        })
        
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(2.0)
        let envelope = createResponseEnvelope(
            response: createTestResponse(),
            startTime: startTime,
            endTime: endTime
        )
        let context = TestContext.empty
        
        // When: Running the chain
        _ = try await chain.execute(context: context, envelope: envelope)
        
        // Then: All middleware should see the same timing
        #expect(capturedTimings.count == 3)
        for timing in capturedTimings {
            #expect(abs(timing - 2.0) < 0.001) // All should see 2.0 seconds
        }
    }
    
    @Test("PostResponseMiddlewareChain order matters")
    func testOrderMatters() async throws {
        // Given: Chain where order affects outcome
        let chain = PostResponseMiddlewareChain<TestResponse, TestContext>()
        
        // First: Set body to A
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            var resp = env.response
            resp.body = "A"
            return .accept(resp)
        })
        
        // Second: Append to body (should see "A")
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            var resp = env.response
            resp.body = resp.body + "B"
            return .accept(resp)
        })
        
        // Third: Append to body (should see "AB")
        chain.use(PostResponseMiddlewareHelpers.from { (_, env: ResponseEnvelope<TestResponse>) in
            var resp = env.response
            resp.body = resp.body + "C"
            return .accept(resp)
        })
        
        let envelope = createResponseEnvelope(response: createTestResponse())
        let context = TestContext.empty
        
        // When: Running the chain
        let finalResponse = try await chain.execute(context: context, envelope: envelope)
        
        // Then: Should have executed in order
        #expect(finalResponse.body == "ABC")
    }
    
    // MARK: - RequestTiming Tests
    
    @Test("RequestTiming calculates duration correctly")
    func testRequestTimingCalculatesDuration() {
        // Given: Start and end times
        let startTime = Date(timeIntervalSince1970: 1000.0)
        let endTime = Date(timeIntervalSince1970: 1003.5)
        
        // When: Creating timing
        let timing = RequestTiming(startTime: startTime, endTime: endTime)
        
        // Then: Duration should be calculated correctly
        #expect(timing.duration == 3.5)
        #expect(timing.startTime == startTime)
        #expect(timing.endTime == endTime)
    }
    
    @Test("RequestTiming duration in milliseconds")
    func testRequestTimingDurationInMilliseconds() {
        // Given: Timing with known duration
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(0.250) // 250ms
        let timing = RequestTiming(startTime: startTime, endTime: endTime)
        
        // When: Converting to milliseconds
        let durationMs = timing.duration * 1000
        
        // Then: Should be approximately 250ms
        #expect(abs(durationMs - 250.0) < 1.0) // Within 1ms tolerance
    }
    
    // MARK: - ResponseEnvelope Tests
    
    @Test("ResponseEnvelope contains request, response, and timing")
    func testResponseEnvelopeContainsAllData() {
        // Given: Request, response, and timing
        let requestEnvelope = createRequestEnvelope()
        let response = createTestResponse()
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(1.0)
        let timing = RequestTiming(startTime: startTime, endTime: endTime)
        
        // When: Creating response envelope
        let envelope = ResponseEnvelope(
            request: requestEnvelope,
            response: response,
            timing: timing
        )
        
        // Then: Should contain all data
        #expect(envelope.request.mcpRequest.method == "tools/call")
        #expect(envelope.response == response)
        #expect(envelope.timing.duration == 1.0)
    }
    
    @Test("ResponseEnvelope provides access to request metadata")
    func testResponseEnvelopeAccessesRequestMetadata() {
        // Given: Request with metadata
        var requestEnvelope = createRequestEnvelope()
        requestEnvelope = requestEnvelope.combine(with: ["userId": "user-123"])
        
        let response = createTestResponse()
        let timing = RequestTiming(startTime: Date(), endTime: Date())
        
        // When: Creating response envelope
        let envelope = ResponseEnvelope(
            request: requestEnvelope,
            response: response,
            timing: timing
        )
        
        // Then: Should provide access to request metadata
        #expect(envelope.request.metadata["userId"] as? String == "user-123")
    }
}
