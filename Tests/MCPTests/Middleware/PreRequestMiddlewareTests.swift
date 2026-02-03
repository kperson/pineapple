import Testing
@testable import MCP

/// Comprehensive unit tests for the Pre-Request Middleware system
///
/// Tests cover:
/// 1. Envelope Protocol - Metadata accumulation
/// 2. PreRequestMiddlewareResponse - Accept/Passthrough/Reject responses
/// 3. FuncPreRequestMiddleware - Closure-based middleware
/// 4. PreRequestMiddlewareHelpers - Factory methods
/// 5. AnyPreRequestMiddleware - Type erasure
/// 6. PreRequestMiddlewareChain - Core functionality
/// 7. PreRequestMiddlewareChain - Rejection & short-circuiting
/// 8. PreRequestMiddlewareChain - Metadata accumulation
/// 9. PreRequestMiddlewareChain - Error handling
@Suite("PreRequestMiddleware Tests")
struct PreRequestMiddlewareTests {

    // MARK: - Test Fixtures

    /// Simple metadata type for testing
    struct TestMetadata: Equatable {
        var userId: String?
        var traceId: String?
        var count: Int = 0
        var flags: [String] = []

        static let empty = TestMetadata()
    }

    /// Test envelope implementation
    struct TestEnvelope: Envelope {
        let requestId: String
        var metadata: TestMetadata

        func combine(with meta: TestMetadata) -> TestEnvelope {
            var updated = self
            // Merge logic: last write wins for strings, accumulate for count
            updated.metadata.userId = meta.userId ?? metadata.userId
            updated.metadata.traceId = meta.traceId ?? metadata.traceId
            updated.metadata.count = metadata.count + meta.count
            updated.metadata.flags = metadata.flags + meta.flags
            return updated
        }
    }

    /// Test context type
    struct TestContext {
        let headers: [String: String]
        let environment: [String: String]

        static let empty = TestContext(headers: [:], environment: [:])
    }

    /// Mock middleware that always accepts with metadata
    struct AcceptMiddleware: PreRequestMiddleware {
        let metadataToAdd: TestMetadata
        var executionCount = 0

        func handle(context: TestContext, envelope: TestEnvelope) async throws -> PreRequestMiddlewareResponse<TestMetadata> {
            return .accept(metadata: metadataToAdd)
        }
    }

    /// Mock middleware that always passes through
    struct PassthroughMiddleware: PreRequestMiddleware {
        func handle(context: TestContext, envelope: TestEnvelope) async throws -> PreRequestMiddlewareResponse<TestMetadata> {
            return .passthrough
        }
    }

    /// Mock middleware that always rejects
    struct RejectMiddleware: PreRequestMiddleware {
        let error: MCPError

        func handle(context: TestContext, envelope: TestEnvelope) async throws -> PreRequestMiddlewareResponse<TestMetadata> {
            return .reject(error)
        }
    }

    /// Mock middleware that throws an error
    struct ErrorThrowingMiddleware: PreRequestMiddleware {
        struct TestError: Error, Equatable {
            let message: String
        }

        let error: TestError

        func handle(context: TestContext, envelope: TestEnvelope) async throws -> PreRequestMiddlewareResponse<TestMetadata> {
            throw error
        }
    }

    /// Middleware that tracks execution
    actor ExecutionTracker {
        var executionCount = 0
        var envelopesReceived: [TestEnvelope] = []

        func recordExecution(envelope: TestEnvelope) {
            executionCount += 1
            envelopesReceived.append(envelope)
        }

        func getCount() -> Int {
            return executionCount
        }

        func reset() {
            executionCount = 0
            envelopesReceived = []
        }
    }

    /// Middleware that tracks when it's called
    struct TrackingMiddleware: PreRequestMiddleware {
        let tracker: ExecutionTracker
        let response: PreRequestMiddlewareResponse<TestMetadata>

        func handle(context: TestContext, envelope: TestEnvelope) async throws -> PreRequestMiddlewareResponse<TestMetadata> {
            await tracker.recordExecution(envelope: envelope)
            return response
        }
    }

    // MARK: - 1. Envelope Tests (5 tests)

    @Test("Envelope combine merges metadata correctly")
    func envelopeCombineMergesMetadata() {
        // Given: An envelope with initial metadata
        let envelope = TestEnvelope(
            requestId: "req-1",
            metadata: TestMetadata(userId: "user-1", traceId: nil, count: 1)
        )

        // When: Combining with new metadata
        let newMetadata = TestMetadata(userId: nil, traceId: "trace-1", count: 2)
        let combined = envelope.combine(with: newMetadata)

        // Then: Metadata should be merged correctly
        #expect(combined.requestId == "req-1")
        #expect(combined.metadata.userId == "user-1") // Preserved from original
        #expect(combined.metadata.traceId == "trace-1") // Added from new
        #expect(combined.metadata.count == 3) // Accumulated (1 + 2)
    }

    @Test("Envelope combine handles multiple updates")
    func envelopeCombineMultipleUpdates() {
        // Given: An envelope with empty metadata
        var envelope = TestEnvelope(
            requestId: "req-2",
            metadata: .empty
        )

        // When: Combining multiple times
        envelope = envelope.combine(with: TestMetadata(userId: "user-1", count: 1))
        envelope = envelope.combine(with: TestMetadata(traceId: "trace-1", count: 2))
        envelope = envelope.combine(with: TestMetadata(count: 3))

        // Then: All metadata should accumulate
        #expect(envelope.metadata.userId == "user-1")
        #expect(envelope.metadata.traceId == "trace-1")
        #expect(envelope.metadata.count == 6) // 1 + 2 + 3
    }

    @Test("Envelope combine resolves conflicts with last write wins")
    func envelopeCombineConflictResolution() {
        // Given: An envelope with userId
        let envelope = TestEnvelope(
            requestId: "req-3",
            metadata: TestMetadata(userId: "user-original")
        )

        // When: Combining with conflicting userId (last write wins)
        let newMetadata = TestMetadata(userId: "user-new")
        let combined = envelope.combine(with: newMetadata)

        // Then: New value should override
        #expect(combined.metadata.userId == "user-new")
    }

    @Test("Envelope combine preserves original metadata when combining with empty")
    func envelopeCombineEmptyMetadata() {
        // Given: An envelope with metadata
        let envelope = TestEnvelope(
            requestId: "req-4",
            metadata: TestMetadata(userId: "user-1", traceId: "trace-1", count: 5)
        )

        // When: Combining with empty metadata
        let combined = envelope.combine(with: .empty)

        // Then: Original metadata should be preserved
        #expect(combined.metadata.userId == "user-1")
        #expect(combined.metadata.traceId == "trace-1")
        #expect(combined.metadata.count == 5)
    }

    @Test("Envelope combine concatenates array metadata")
    func envelopeCombineComplexMetadata() {
        // Given: An envelope with array metadata
        let envelope = TestEnvelope(
            requestId: "req-5",
            metadata: TestMetadata(flags: ["flag1", "flag2"])
        )

        // When: Combining with additional array items
        let newMetadata = TestMetadata(flags: ["flag3", "flag4"])
        let combined = envelope.combine(with: newMetadata)

        // Then: Arrays should be concatenated
        #expect(combined.metadata.flags == ["flag1", "flag2", "flag3", "flag4"])
    }

    // MARK: - 2. PreRequestMiddlewareResponse Tests (5 tests)

    @Test("PreRequestMiddlewareResponse accept case works correctly")
    func preRequestMiddlewareResponseAccept() {
        // Given: Metadata to accept
        let metadata = TestMetadata(userId: "user-1", count: 1)

        // When: Creating accept response
        let response = PreRequestMiddlewareResponse.accept(metadata: metadata)

        // Then: Should match accept case
        if case .accept(let meta) = response {
            #expect(meta.userId == "user-1")
            #expect(meta.count == 1)
        } else {
            Issue.record("Expected .accept, got \(response)")
        }
    }

    @Test("PreRequestMiddlewareResponse passthrough case works correctly")
    func preRequestMiddlewareResponsePassthrough() {
        // When: Creating passthrough response
        let response: PreRequestMiddlewareResponse<TestMetadata> = .passthrough

        // Then: Should match passthrough case
        if case .passthrough = response {
            // Success
        } else {
            Issue.record("Expected .passthrough, got \(response)")
        }
    }

    @Test("PreRequestMiddlewareResponse reject case works correctly")
    func preRequestMiddlewareResponseReject() {
        // Given: An error
        let error = MCPError(code: -32600, message: "Test error")

        // When: Creating reject response
        let response: PreRequestMiddlewareResponse<TestMetadata> = .reject(error)

        // Then: Should match reject case
        if case .reject(let err) = response {
            #expect(err.code == -32600)
            #expect(err.message == "Test error")
        } else {
            Issue.record("Expected .reject, got \(response)")
        }
    }

    @Test("PreRequestMiddlewareResponse can extract metadata from accept")
    func preRequestMiddlewareResponseExtractMetadata() {
        // Given: Accept response with metadata
        let response = PreRequestMiddlewareResponse.accept(metadata: TestMetadata(userId: "user-1", traceId: "trace-1"))

        // When: Extracting metadata
        if case .accept(let metadata) = response {
            // Then: Metadata should be extractable
            #expect(metadata.userId == "user-1")
            #expect(metadata.traceId == "trace-1")
        } else {
            Issue.record("Could not extract metadata from accept response")
        }
    }

    @Test("PreRequestMiddlewareResponse can extract error from reject")
    func preRequestMiddlewareResponseExtractError() {
        // Given: Reject response with error
        let originalError = MCPError(code: -32601, message: "Method not found", data: ["method": "test"])
        let response: PreRequestMiddlewareResponse<TestMetadata> = .reject(originalError)

        // When: Extracting error
        if case .reject(let error) = response {
            // Then: Error should be extractable with all fields
            #expect(error.code == -32601)
            #expect(error.message == "Method not found")
            if case .object(let obj) = error.data {
                #expect(obj["method"] == .string("test"))
            } else {
                Issue.record("Expected object data")
            }
        } else {
            Issue.record("Could not extract error from reject response")
        }
    }

    // MARK: - 3. FuncPreRequestMiddleware Tests (7 tests)

    @Test("FuncPreRequestMiddleware returns accept with metadata")
    func funcPreRequestMiddlewareAccept() async throws {
        // Given: A closure that returns accept
        let middleware = FuncPreRequestMiddleware<TestEnvelope, TestContext> { context, envelope in
            return .accept(metadata: TestMetadata(userId: "user-from-closure", count: 1))
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)

        // Then: Should return accept with metadata
        if case .accept(let metadata) = response {
            #expect(metadata.userId == "user-from-closure")
            #expect(metadata.count == 1)
        } else {
            Issue.record("Expected .accept, got \(response)")
        }
    }

    @Test("FuncPreRequestMiddleware returns passthrough")
    func funcPreRequestMiddlewarePassthrough() async throws {
        // Given: A closure that returns passthrough
        let middleware = FuncPreRequestMiddleware<TestEnvelope, TestContext> { _, _ in
            return .passthrough
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)

        // Then: Should return passthrough
        if case .passthrough = response {
            // Success
        } else {
            Issue.record("Expected .passthrough, got \(response)")
        }
    }

    @Test("FuncPreRequestMiddleware returns reject with error")
    func funcPreRequestMiddlewareReject() async throws {
        // Given: A closure that returns reject
        let middleware = FuncPreRequestMiddleware<TestEnvelope, TestContext> { _, _ in
            return .reject(MCPError(code: -32600, message: "Invalid request"))
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)

        // Then: Should return reject
        if case .reject(let error) = response {
            #expect(error.code == -32600)
            #expect(error.message == "Invalid request")
        } else {
            Issue.record("Expected .reject, got \(response)")
        }
    }

    @Test("FuncPreRequestMiddleware handles async operations")
    func funcPreRequestMiddlewareAsyncExecution() async throws {
        // Given: A closure with async operation
        let middleware = FuncPreRequestMiddleware<TestEnvelope, TestContext> { _, _ in
            // Simulate async work
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            return .accept(metadata: TestMetadata(userId: "async-user"))
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)

        // Then: Should complete and return accept
        if case .accept(let metadata) = response {
            #expect(metadata.userId == "async-user")
        } else {
            Issue.record("Expected .accept after async operation")
        }
    }

    @Test("FuncPreRequestMiddleware propagates thrown errors")
    func funcPreRequestMiddlewareErrorPropagation() async throws {
        // Given: A closure that throws
        struct TestError: Error {}
        let middleware = FuncPreRequestMiddleware<TestEnvelope, TestContext> { _, _ in
            throw TestError()
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Calling the middleware should propagate the error
        await #expect(throws: TestError.self) {
            _ = try await middleware.handle(context: context, envelope: envelope)
        }
    }

    @Test("FuncPreRequestMiddleware can access context")
    func funcPreRequestMiddlewareContextAccess() async throws {
        // Given: A closure that reads from context
        let middleware = FuncPreRequestMiddleware<TestEnvelope, TestContext> { context, _ in
            let apiKey = context.headers["X-API-Key"]
            return .accept(metadata: TestMetadata(userId: apiKey))
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext(headers: ["X-API-Key": "secret-key"], environment: [:])

        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)

        // Then: Should have accessed context
        if case .accept(let metadata) = response {
            #expect(metadata.userId == "secret-key")
        } else {
            Issue.record("Expected .accept with context data")
        }
    }

    @Test("FuncPreRequestMiddleware can access envelope")
    func funcPreRequestMiddlewareEnvelopeAccess() async throws {
        // Given: A closure that reads from envelope
        let middleware = FuncPreRequestMiddleware<TestEnvelope, TestContext> { _, envelope in
            // Read existing metadata and add to count
            let newCount = envelope.metadata.count + 10
            return .accept(metadata: TestMetadata(count: newCount))
        }

        let envelope = TestEnvelope(
            requestId: "req-1",
            metadata: TestMetadata(count: 5)
        )
        let context = TestContext.empty

        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)

        // Then: Should have read and modified envelope data
        if case .accept(let metadata) = response {
            #expect(metadata.count == 15) // 5 + 10
        } else {
            Issue.record("Expected .accept with modified envelope data")
        }
    }

    // MARK: - 4. PreRequestMiddlewareHelpers Tests (4 tests)

    @Test("PreRequestMiddlewareHelpers creates middleware from closure")
    func preRequestMiddlewareHelpersFromClosure() async throws {
        // Given: Creating middleware via helper
        let middleware = PreRequestMiddlewareHelpers.from { (context: TestContext, envelope: TestEnvelope) in
            return .accept(metadata: TestMetadata(userId: "helper-user"))
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)

        // Then: Should work exactly like FuncPreRequestMiddleware
        if case .accept(let metadata) = response {
            #expect(metadata.userId == "helper-user")
        } else {
            Issue.record("Expected .accept")
        }
    }

    @Test("PreRequestMiddlewareHelpers supports type inference")
    func preRequestMiddlewareHelpersTypeInference() async throws {
        // Given: Creating middleware with inferred types (no explicit type annotations needed)
        let middleware = PreRequestMiddlewareHelpers.from { (ctx: TestContext, env: TestEnvelope) in
            // Types are inferred from closure signature
            let userId = ctx.headers["user-id"]
            return .accept(metadata: TestMetadata(userId: userId, count: env.metadata.count + 1))
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: TestMetadata(count: 5))
        let context = TestContext(headers: ["user-id": "inferred-user"], environment: [:])

        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)

        // Then: Types should have been correctly inferred
        if case .accept(let metadata) = response {
            #expect(metadata.userId == "inferred-user")
            #expect(metadata.count == 6)
        } else {
            Issue.record("Expected .accept")
        }
    }

    @Test("PreRequestMiddlewareHelpers supports async closures")
    func preRequestMiddlewareHelpersAsyncClosure() async throws {
        // Given: Creating middleware with async closure
        let middleware = PreRequestMiddlewareHelpers.from { (_: TestContext, _: TestEnvelope) in
            // Simulate async work
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            return .accept(metadata: TestMetadata(userId: "async-helper"))
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling the middleware
        let response = try await middleware.handle(context: context, envelope: envelope)

        // Then: Should handle async operations
        if case .accept(let metadata) = response {
            #expect(metadata.userId == "async-helper")
        } else {
            Issue.record("Expected .accept after async operation")
        }
    }

    @Test("PreRequestMiddlewareHelpers propagates errors from throwing closures")
    func preRequestMiddlewareHelpersThrowingClosure() async throws {
        // Given: Creating middleware that throws
        struct HelperError: Error {}
        let middleware = PreRequestMiddlewareHelpers.from { (_: TestContext, _: TestEnvelope) in
            throw HelperError()
        }

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Should propagate thrown errors
        await #expect(throws: HelperError.self) {
            _ = try await middleware.handle(context: context, envelope: envelope)
        }
    }

    // MARK: - 5. AnyPreRequestMiddleware Tests (8 tests)

    @Test("AnyPreRequestMiddleware wraps middleware correctly")
    func anyPreRequestMiddlewareWrapsMiddleware() async throws {
        // Given: A concrete middleware
        let concrete = AcceptMiddleware(metadataToAdd: TestMetadata(userId: "wrapped-user"))

        // When: Wrapping in AnyPreRequestMiddleware
        let wrapped = AnyPreRequestMiddleware(concrete)

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // Then: Should work the same as the original
        let response = try await wrapped.handle(context: context, envelope: envelope)
        if case .accept(let metadata) = response {
            #expect(metadata.userId == "wrapped-user")
        } else {
            Issue.record("Expected .accept")
        }
    }

    @Test("AnyPreRequestMiddleware forwards handle calls")
    func anyPreRequestMiddlewareForwardsHandle() async throws {
        // Given: A passthrough middleware wrapped in AnyPreRequestMiddleware
        let passthrough = PassthroughMiddleware()
        let wrapped = AnyPreRequestMiddleware(passthrough)

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling handle on wrapped middleware
        let response = try await wrapped.handle(context: context, envelope: envelope)

        // Then: Should forward to the wrapped middleware
        if case .passthrough = response {
            // Success
        } else {
            Issue.record("Expected .passthrough")
        }
    }

    @Test("AnyPreRequestMiddleware preserves accept behavior")
    func anyPreRequestMiddlewarePreservesAcceptBehavior() async throws {
        // Given: Accept middleware with specific metadata
        let middleware = AcceptMiddleware(metadataToAdd: TestMetadata(
            userId: "test-user",
            traceId: "trace-123",
            count: 42
        ))
        let wrapped = AnyPreRequestMiddleware(middleware)

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling the wrapped middleware
        let response = try await wrapped.handle(context: context, envelope: envelope)

        // Then: Should preserve all accept behavior and metadata
        if case .accept(let metadata) = response {
            #expect(metadata.userId == "test-user")
            #expect(metadata.traceId == "trace-123")
            #expect(metadata.count == 42)
        } else {
            Issue.record("Expected .accept")
        }
    }

    @Test("AnyPreRequestMiddleware preserves passthrough behavior")
    func anyPreRequestMiddlewarePreservesPassthroughBehavior() async throws {
        // Given: Multiple passthrough middleware
        let passthrough1 = PassthroughMiddleware()
        let passthrough2 = FuncPreRequestMiddleware<TestEnvelope, TestContext> { _, _ in .passthrough }

        let wrapped1 = AnyPreRequestMiddleware(passthrough1)
        let wrapped2 = AnyPreRequestMiddleware(passthrough2)

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling both wrapped middleware
        let response1 = try await wrapped1.handle(context: context, envelope: envelope)
        let response2 = try await wrapped2.handle(context: context, envelope: envelope)

        // Then: Both should passthrough
        if case .passthrough = response1 {
            // Success
        } else {
            Issue.record("Expected .passthrough from wrapped1")
        }

        if case .passthrough = response2 {
            // Success
        } else {
            Issue.record("Expected .passthrough from wrapped2")
        }
    }

    @Test("AnyPreRequestMiddleware preserves reject behavior")
    func anyPreRequestMiddlewarePreservesRejectBehavior() async throws {
        // Given: Reject middleware with specific error
        let error = MCPError(code: -32001, message: "Custom error", data: ["reason": "test"])
        let middleware = RejectMiddleware(error: error)
        let wrapped = AnyPreRequestMiddleware(middleware)

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Calling the wrapped middleware
        let response = try await wrapped.handle(context: context, envelope: envelope)

        // Then: Should preserve reject behavior and error details
        if case .reject(let rejectedError) = response {
            #expect(rejectedError.code == -32001)
            #expect(rejectedError.message == "Custom error")
        } else {
            Issue.record("Expected .reject")
        }
    }

    @Test("AnyPreRequestMiddleware preserves thrown errors")
    func anyPreRequestMiddlewarePreservesErrors() async throws {
        // Given: Middleware that throws
        let throwingMiddleware = ErrorThrowingMiddleware(
            error: ErrorThrowingMiddleware.TestError(message: "test error")
        )
        let wrapped = AnyPreRequestMiddleware(throwingMiddleware)

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Should propagate the thrown error
        do {
            _ = try await wrapped.handle(context: context, envelope: envelope)
            Issue.record("Should have thrown error")
        } catch let error as ErrorThrowingMiddleware.TestError {
            #expect(error.message == "test error")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("AnyPreRequestMiddleware eraseToAnyPreRequestMiddleware works")
    func anyPreRequestMiddlewareEraseToAnyPreRequestMiddleware() async throws {
        // Given: A concrete middleware
        let middleware = AcceptMiddleware(metadataToAdd: TestMetadata(userId: "erased-user"))

        // When: Using the extension method
        let erased = middleware.eraseToAnyPreRequestMiddleware()

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // Then: Should work the same as AnyPreRequestMiddleware initializer
        let response = try await erased.handle(context: context, envelope: envelope)
        if case .accept(let metadata) = response {
            #expect(metadata.userId == "erased-user")
        } else {
            Issue.record("Expected .accept")
        }
    }

    @Test("AnyPreRequestMiddleware enables heterogeneous collections")
    func anyPreRequestMiddlewareHeterogeneousCollection() async throws {
        // Given: Different middleware types
        let acceptMW = AcceptMiddleware(metadataToAdd: TestMetadata(userId: "accept"))
        let passthroughMW = PassthroughMiddleware()
        let funcMW = PreRequestMiddlewareHelpers.from { (_: TestContext, _: TestEnvelope) in
            return .accept(metadata: TestMetadata(count: 1))
        }

        // When: Storing in a heterogeneous array
        let middlewares: [AnyPreRequestMiddleware<TestEnvelope, TestContext>] = [
            acceptMW.eraseToAnyPreRequestMiddleware(),
            passthroughMW.eraseToAnyPreRequestMiddleware(),
            funcMW.eraseToAnyPreRequestMiddleware()
        ]

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // Then: All should be callable
        #expect(middlewares.count == 3)

        // Test first middleware (accept)
        let response1 = try await middlewares[0].handle(context: context, envelope: envelope)
        if case .accept(let meta) = response1 {
            #expect(meta.userId == "accept")
        } else {
            Issue.record("Expected .accept from first middleware")
        }

        // Test second middleware (passthrough)
        let response2 = try await middlewares[1].handle(context: context, envelope: envelope)
        if case .passthrough = response2 {
            // Success
        } else {
            Issue.record("Expected .passthrough from second middleware")
        }

        // Test third middleware (func)
        let response3 = try await middlewares[2].handle(context: context, envelope: envelope)
        if case .accept(let meta) = response3 {
            #expect(meta.count == 1)
        } else {
            Issue.record("Expected .accept from third middleware")
        }
    }

    // MARK: - 6. PreRequestMiddlewareChain - Core Tests (7 tests)

    @Test("PreRequestMiddlewareChain empty chain returns original envelope")
    func preRequestMiddlewareChainEmptyChain() async throws {
        // Given: An empty chain
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()

        let envelope = TestEnvelope(
            requestId: "req-1",
            metadata: TestMetadata(userId: "original", count: 5)
        )
        let context = TestContext.empty

        // When: Running the empty chain
        let result = try await chain.envelope(envelope, context: context)

        // Then: Should return the original envelope unchanged
        #expect(result.requestId == "req-1")
        #expect(result.metadata.userId == "original")
        #expect(result.metadata.count == 5)
    }

    @Test("PreRequestMiddlewareChain single accept middleware combines metadata")
    func preRequestMiddlewareChainSingleMiddlewareAccept() async throws {
        // Given: Chain with one accept middleware
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(userId: "middleware-user", count: 10)))

        let envelope = TestEnvelope(requestId: "req-1", metadata: TestMetadata(count: 5))
        let context = TestContext.empty

        // When: Running the chain
        let result = try await chain.envelope(envelope, context: context)

        // Then: Metadata should be combined
        #expect(result.metadata.userId == "middleware-user")
        #expect(result.metadata.count == 15) // 5 + 10
    }

    @Test("PreRequestMiddlewareChain single passthrough middleware leaves envelope unchanged")
    func preRequestMiddlewareChainSingleMiddlewarePassthrough() async throws {
        // Given: Chain with one passthrough middleware
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(PassthroughMiddleware())

        let envelope = TestEnvelope(
            requestId: "req-1",
            metadata: TestMetadata(userId: "original", count: 5)
        )
        let context = TestContext.empty

        // When: Running the chain
        let result = try await chain.envelope(envelope, context: context)

        // Then: Envelope should be unchanged
        #expect(result.metadata.userId == "original")
        #expect(result.metadata.count == 5)
    }

    @Test("PreRequestMiddlewareChain single reject middleware throws error")
    func preRequestMiddlewareChainSingleMiddlewareReject() async throws {
        // Given: Chain with one reject middleware
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        let error = MCPError(code: -32600, message: "Rejected by middleware")
        chain.use(RejectMiddleware(error: error))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Should throw the reject error
        do {
            _ = try await chain.envelope(envelope, context: context)
            Issue.record("Should have thrown MCPError")
        } catch let mcpError as MCPError {
            #expect(mcpError.code == -32600)
            #expect(mcpError.message == "Rejected by middleware")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("PreRequestMiddlewareChain two accept middleware accumulate metadata")
    func preRequestMiddlewareChainTwoMiddlewareBothAccept() async throws {
        // Given: Chain with two accepting middleware
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(userId: "first-user", count: 1)))
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(traceId: "second-trace", count: 2)))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Running the chain
        let result = try await chain.envelope(envelope, context: context)

        // Then: Both metadata should be accumulated
        #expect(result.metadata.userId == "first-user") // From first middleware
        #expect(result.metadata.traceId == "second-trace") // From second middleware
        #expect(result.metadata.count == 3) // 1 + 2
    }

    @Test("PreRequestMiddlewareChain passthrough then accept adds only second metadata")
    func preRequestMiddlewareChainTwoMiddlewareFirstPassSecond() async throws {
        // Given: Chain with passthrough then accept
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(PassthroughMiddleware())
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(userId: "second-user", count: 5)))

        let envelope = TestEnvelope(requestId: "req-1", metadata: TestMetadata(count: 10))
        let context = TestContext.empty

        // When: Running the chain
        let result = try await chain.envelope(envelope, context: context)

        // Then: Only second middleware's metadata should be added
        #expect(result.metadata.userId == "second-user")
        #expect(result.metadata.count == 15) // 10 + 5
    }

    @Test("PreRequestMiddlewareChain all passthrough leaves envelope unchanged")
    func preRequestMiddlewareChainThreeMiddlewareAllPassthrough() async throws {
        // Given: Chain with three passthrough middleware
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(PassthroughMiddleware())
        chain.use(PassthroughMiddleware())
        chain.use(PassthroughMiddleware())

        let envelope = TestEnvelope(
            requestId: "req-1",
            metadata: TestMetadata(userId: "original", count: 42)
        )
        let context = TestContext.empty

        // When: Running the chain
        let result = try await chain.envelope(envelope, context: context)

        // Then: Envelope should pass through unchanged
        #expect(result.metadata.userId == "original")
        #expect(result.metadata.count == 42)
    }

    // MARK: - 7. PreRequestMiddlewareChain - Rejection Tests (5 tests)

    @Test("PreRequestMiddlewareChain first reject stops chain execution")
    func preRequestMiddlewareChainFirstRejects() async throws {
        // Given: Chain where first middleware rejects
        let tracker = ExecutionTracker()
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(RejectMiddleware(error: MCPError(code: -32001, message: "First rejects")))
        chain.use(TrackingMiddleware(tracker: tracker, response: .passthrough))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Should reject and not run second middleware
        do {
            _ = try await chain.envelope(envelope, context: context)
            Issue.record("Should have rejected")
        } catch let error as MCPError {
            #expect(error.code == -32001)
            #expect(error.message == "First rejects")
        }

        // Verify second middleware never executed
        let count = await tracker.getCount()
        #expect(count == 0, "Second middleware should not have been called")
    }

    @Test("PreRequestMiddlewareChain middle reject stops after previous middleware")
    func preRequestMiddlewareChainMiddleRejects() async throws {
        // Given: Chain where middle middleware rejects
        let tracker1 = ExecutionTracker()
        let tracker2 = ExecutionTracker()

        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(TrackingMiddleware(tracker: tracker1, response: .passthrough))
        chain.use(RejectMiddleware(error: MCPError(code: -32002, message: "Middle rejects")))
        chain.use(TrackingMiddleware(tracker: tracker2, response: .passthrough))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Should reject after first middleware
        do {
            _ = try await chain.envelope(envelope, context: context)
            Issue.record("Should have rejected")
        } catch let error as MCPError {
            #expect(error.code == -32002)
        }

        // Verify execution pattern
        let count1 = await tracker1.getCount()
        let count2 = await tracker2.getCount()
        #expect(count1 == 1, "First middleware should have executed")
        #expect(count2 == 0, "Third middleware should not have executed")
    }

    @Test("PreRequestMiddlewareChain last reject executes all previous middleware")
    func preRequestMiddlewareChainLastRejects() async throws {
        // Given: Chain where last middleware rejects
        let tracker = ExecutionTracker()
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(TrackingMiddleware(tracker: tracker, response: .passthrough))
        chain.use(RejectMiddleware(error: MCPError(code: -32003, message: "Last rejects")))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Should reject after all previous middleware
        do {
            _ = try await chain.envelope(envelope, context: context)
            Issue.record("Should have rejected")
        } catch let error as MCPError {
            #expect(error.code == -32003)
        }

        // Verify first middleware executed
        let count = await tracker.getCount()
        #expect(count == 1, "First middleware should have executed")
    }

    @Test("PreRequestMiddlewareChain reject preserves error details")
    func preRequestMiddlewareChainRejectError() async throws {
        // Given: Chain with reject containing detailed error info
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        let errorData: [String: Any] = [
            "reason": "authentication_failed",
            "code": "AUTH_001"
        ]
        chain.use(RejectMiddleware(error: MCPError(
            code: -32600,
            message: "Authentication failed",
            data: errorData
        )))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Error details should be preserved
        do {
            _ = try await chain.envelope(envelope, context: context)
            Issue.record("Should have rejected")
        } catch let error as MCPError {
            #expect(error.code == -32600)
            #expect(error.message == "Authentication failed")
            if case .object(let obj) = error.data {
                #expect(obj["reason"] == .string("authentication_failed"))
                #expect(obj["code"] == .string("AUTH_001"))
            } else {
                Issue.record("Expected error data to be preserved")
            }
        }
    }

    @Test("PreRequestMiddlewareChain reject stops execution at correct point")
    func preRequestMiddlewareChainExecutionCount() async throws {
        // Given: Chain with multiple middleware before rejection
        let tracker1 = ExecutionTracker()
        let tracker2 = ExecutionTracker()
        let tracker3 = ExecutionTracker()
        let tracker4 = ExecutionTracker()

        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(TrackingMiddleware(tracker: tracker1, response: .accept(metadata: TestMetadata(count: 1))))
        chain.use(TrackingMiddleware(tracker: tracker2, response: .passthrough))
        chain.use(RejectMiddleware(error: MCPError(code: -32000, message: "Stop here")))
        chain.use(TrackingMiddleware(tracker: tracker3, response: .passthrough))
        chain.use(TrackingMiddleware(tracker: tracker4, response: .passthrough))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Running the chain
        do {
            _ = try await chain.envelope(envelope, context: context)
            Issue.record("Should have rejected")
        } catch is MCPError {
            // Expected
        }

        // Then: Only middleware before rejection should have executed
        let count1 = await tracker1.getCount()
        let count2 = await tracker2.getCount()
        let count3 = await tracker3.getCount()
        let count4 = await tracker4.getCount()

        #expect(count1 == 1, "First middleware should execute")
        #expect(count2 == 1, "Second middleware should execute")
        #expect(count3 == 0, "Third middleware should NOT execute (after reject)")
        #expect(count4 == 0, "Fourth middleware should NOT execute (after reject)")
    }

    // MARK: - 8. PreRequestMiddlewareChain - Metadata Tests (4 tests)

    @Test("PreRequestMiddlewareChain accumulates metadata across middleware")
    func preRequestMiddlewareChainMetadataAccumulation() async throws {
        // Given: Chain where each middleware reads previous metadata
        let tracker = ExecutionTracker()
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()

        // First middleware adds userId
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(userId: "user-1", count: 1)))

        // Second middleware can see userId from first
        chain.use(TrackingMiddleware(tracker: tracker, response: .accept(metadata: TestMetadata(traceId: "trace-1", count: 2))))

        // Third middleware sees both
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(count: 3)))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Running the chain
        let result = try await chain.envelope(envelope, context: context)

        // Then: All metadata should be accumulated
        #expect(result.metadata.userId == "user-1") // From first
        #expect(result.metadata.traceId == "trace-1") // From second
        #expect(result.metadata.count == 6) // 1 + 2 + 3

        // Verify middleware saw accumulated metadata
        let envelopes = await tracker.envelopesReceived
        #expect(envelopes.count == 1)
        // Second middleware should see userId from first
        #expect(envelopes[0].metadata.userId == "user-1")
        #expect(envelopes[0].metadata.count == 1)
    }

    @Test("PreRequestMiddlewareChain preserves metadata order")
    func preRequestMiddlewareChainMetadataOrder() async throws {
        // Given: Chain that adds metadata in specific order
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(flags: ["flag1"])))
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(flags: ["flag2"])))
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(flags: ["flag3"])))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Running the chain
        let result = try await chain.envelope(envelope, context: context)

        // Then: Flags should accumulate in order
        #expect(result.metadata.flags == ["flag1", "flag2", "flag3"])
    }

    @Test("PreRequestMiddlewareChain does not mutate original envelope")
    func preRequestMiddlewareChainMetadataImmutability() async throws {
        // Given: Chain with middleware
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(userId: "new-user", count: 10)))

        let originalEnvelope = TestEnvelope(
            requestId: "req-1",
            metadata: TestMetadata(userId: "original-user", count: 5)
        )
        let context = TestContext.empty

        // When: Running the chain
        let result = try await chain.envelope(originalEnvelope, context: context)

        // Then: Original envelope should be unchanged
        #expect(originalEnvelope.metadata.userId == "original-user")
        #expect(originalEnvelope.metadata.count == 5)

        // And result should have combined metadata
        #expect(result.metadata.userId == "new-user")
        #expect(result.metadata.count == 15) // 5 + 10
    }

    @Test("PreRequestMiddlewareChain handles complex nested metadata")
    func preRequestMiddlewareChainComplexMetadata() async throws {
        // Given: Chain with complex nested metadata
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()

        // Add multiple types of metadata
        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(
            userId: "user-123",
            traceId: "trace-abc",
            count: 1,
            flags: ["auth", "verified"]
        )))

        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(
            count: 2,
            flags: ["premium"]
        )))

        chain.use(AcceptMiddleware(metadataToAdd: TestMetadata(
            count: 3,
            flags: ["active"]
        )))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Running the chain
        let result = try await chain.envelope(envelope, context: context)

        // Then: All complex metadata should be properly combined
        #expect(result.metadata.userId == "user-123")
        #expect(result.metadata.traceId == "trace-abc")
        #expect(result.metadata.count == 6) // 1 + 2 + 3
        #expect(result.metadata.flags == ["auth", "verified", "premium", "active"])
    }

    // MARK: - 9. PreRequestMiddlewareChain - Error Tests (3 tests)

    @Test("PreRequestMiddlewareChain propagates thrown errors")
    func preRequestMiddlewareChainThrowError() async throws {
        // Given: Chain where middleware throws error (not reject)
        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(ErrorThrowingMiddleware(
            error: ErrorThrowingMiddleware.TestError(message: "Something went wrong")
        ))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Error should propagate as thrown error
        do {
            _ = try await chain.envelope(envelope, context: context)
            Issue.record("Should have thrown TestError")
        } catch let error as ErrorThrowingMiddleware.TestError {
            #expect(error.message == "Something went wrong")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("PreRequestMiddlewareChain error stops chain execution")
    func preRequestMiddlewareChainErrorStopsChain() async throws {
        // Given: Chain where middleware throws in the middle
        let tracker1 = ExecutionTracker()
        let tracker2 = ExecutionTracker()

        let chain = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain.use(TrackingMiddleware(tracker: tracker1, response: .passthrough))
        chain.use(ErrorThrowingMiddleware(
            error: ErrorThrowingMiddleware.TestError(message: "Error in middle")
        ))
        chain.use(TrackingMiddleware(tracker: tracker2, response: .passthrough))

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When: Running the chain
        do {
            _ = try await chain.envelope(envelope, context: context)
            Issue.record("Should have thrown error")
        } catch is ErrorThrowingMiddleware.TestError {
            // Expected
        }

        // Then: Only first middleware should have executed
        let count1 = await tracker1.getCount()
        let count2 = await tracker2.getCount()
        #expect(count1 == 1, "First middleware should execute before error")
        #expect(count2 == 0, "Third middleware should NOT execute after error")
    }

    @Test("PreRequestMiddlewareChain preserves different error types")
    func preRequestMiddlewareChainErrorType() async throws {
        // Given: Multiple chains with different error types
        struct CustomError1: Error { let code: Int }
        struct CustomError2: Error { let message: String }

        let chain1 = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain1.use(PreRequestMiddlewareHelpers.from { (_: TestContext, _: TestEnvelope) in
            throw CustomError1(code: 404)
        })

        let chain2 = PreRequestMiddlewareChain<TestEnvelope, TestContext>()
        chain2.use(PreRequestMiddlewareHelpers.from { (_: TestContext, _: TestEnvelope) in
            throw CustomError2(message: "Not found")
        })

        let envelope = TestEnvelope(requestId: "req-1", metadata: .empty)
        let context = TestContext.empty

        // When/Then: Each chain preserves its error type
        do {
            _ = try await chain1.envelope(envelope, context: context)
            Issue.record("Should have thrown CustomError1")
        } catch let error as CustomError1 {
            #expect(error.code == 404)
        }

        do {
            _ = try await chain2.envelope(envelope, context: context)
            Issue.record("Should have thrown CustomError2")
        } catch let error as CustomError2 {
            #expect(error.message == "Not found")
        }
    }
}
