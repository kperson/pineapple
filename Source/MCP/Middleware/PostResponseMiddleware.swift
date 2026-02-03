import Foundation
// MARK: - Post-Response Middleware

/// Response from post-response middleware indicating whether to transform the response or pass it through
///
/// Post-response middleware returns one of two responses after processing:
/// - **accept**: Return a modified response
/// - **passthrough**: Return the original response unchanged
///
/// ## Response Semantics
///
/// ### Accept with Modified Response
/// ```swift
/// return .accept(modifiedResponse)
/// ```
/// - Modified response is returned to client
/// - Use for: adding headers, compression, redacting sensitive data, transforming responses
///
/// ### Passthrough
/// ```swift
/// return .passthrough
/// ```
/// - Original response returned unchanged
/// - Use for: logging, metrics, auditing (side-effects only)
///
/// ## Examples
///
/// ```swift
/// // Logging middleware (passthrough)
/// func handle(context: Context, envelope: E, response: R, timing: RequestTiming) async throws -> PostResponseMiddlewareResponse<R> {
///     logger.info("Request completed in \(timing.duration)s")
///     return .passthrough
/// }
///
/// // Add correlation header (accept) - Lambda example
/// func handle(context: LambdaMCPContext, envelope: E, response: APIGatewayResponse, timing: RequestTiming) async throws -> PostResponseMiddlewareResponse<APIGatewayResponse> {
///     var modified = response
///     modified.headers["X-Request-ID"] = context.lambdaContext.requestID
///     return .accept(modified)
/// }
/// ```
public enum PostResponseMiddlewareResponse<Response> {

    /// Return a modified response
    ///
    /// The modified response will be returned to the client. Use this when you need to:
    /// - Add or modify response headers (Lambda/Hummingbird)
    /// - Compress or encrypt response data
    /// - Redact sensitive fields
    /// - Transform response structure
    ///
    /// - Parameter response: The modified response to return
    case accept(_ response: Response)

    /// Return the original response unchanged
    ///
    /// The original response passes through without modification. Use when middleware
    /// performs side effects (logging, metrics) but doesn't need to modify the response.
    case passthrough
}

/// Protocol for response interceptors at the transport adapter level
///
/// Post-response middleware provides extension points for observability, transformation,
/// and augmentation of responses after they've been generated and converted to transport-
/// specific formats (APIGatewayResponse, Hummingbird.Response, etc.) but before they're
/// sent to clients.
///
/// **Important**: Post-response middleware runs at the **adapter level**, not router level.
/// This means middleware works with transport-specific response types and can modify
/// headers, status codes, and other transport-specific features.
///
/// ## Common Use Cases
///
/// - **Logging**: Record response details, status, size, timing with full request context
/// - **Metrics**: Collect request duration, success rates, response sizes per user/tenant
/// - **Auditing**: Track successful operations with correlation to request metadata
/// - **Header Manipulation**: Add correlation IDs, timing headers, cache control
/// - **Transformation**: Compress data, redact sensitive fields (transport-aware)
/// - **Error Enrichment**: Add debug information to error responses
///
/// ## Architecture
///
/// Post-response middleware executes at the adapter level after transport conversion:
///
/// ```
/// Router → TransportResponse (JSON)
///     ↓
/// Adapter converts to transport-specific response
///     ↓
/// ┌────────────────────────────────────┐
/// │  Post-Response Middleware Chain    │
/// ├────────────────────────────────────┤
/// │  1. Metrics Middleware             │  ← Record timing
/// │  2. Logging Middleware             │  ← Log response + request
/// │  3. Header Middleware              │  ← Add X-Request-ID
/// │  4. Custom Middleware              │  ← Business logic
/// └────────────────────────────────────┘
///     ↓
/// APIGatewayResponse / Hummingbird.Response / Stdio output
///     ↓
/// Client
/// ```
///
/// Each middleware receives:
/// - **Context**: Transport-specific context (LambdaMCPContext, HummingbirdMCPContext, StdioMCPContext)
/// - **Envelope**: Original request + accumulated metadata from pre-request middleware
/// - **Response**: Transport-specific response (APIGatewayResponse, Hummingbird.Response, etc.)
/// - **Timing**: Start/end times and request duration
///
/// Each middleware returns:
/// - **accept(response)**: Return modified transport-specific response
/// - **passthrough**: Return original response unchanged
///
/// ## Transport-Specific Response Types
///
/// - **Lambda**: `APIGatewayResponse` - Can modify headers, status code, body
/// - **Hummingbird**: `Hummingbird.Response` - Can modify headers, status code, body
/// - **Stdio**: `TransportResponse` - Can modify JSON response data
///
/// ## Example Implementations
///
/// ### Lambda: Add Request ID Header
/// ```swift
/// struct RequestIDMiddleware: PostResponseMiddleware {
///     typealias ResponseEnvelope = TransportEnvelope
///     typealias Response = APIGatewayResponse
///     typealias Context = LambdaMCPContext
///
///     func handle(
///         context: LambdaMCPContext,
///         envelope: TransportEnvelope,
///         response: APIGatewayResponse,
///         timing: RequestTiming
///     ) async throws -> PostResponseMiddlewareResponse<APIGatewayResponse> {
///         var modified = response
///         modified.headers["X-Request-ID"] = context.lambdaContext.requestID
///         modified.headers["X-Duration-Ms"] = "\(timing.duration * 1000)"
///         return .accept(modified)
///     }
/// }
/// ```
///
/// ### Hummingbird: CORS Headers
/// ```swift
/// struct CORSMiddleware: PostResponseMiddleware {
///     typealias ResponseEnvelope = TransportEnvelope
///     typealias Response = Hummingbird.Response
///     typealias Context = HummingbirdMCPContext
///
///     func handle(
///         context: HummingbirdMCPContext,
///         envelope: TransportEnvelope,
///         response: Hummingbird.Response,
///         timing: RequestTiming
///     ) async throws -> PostResponseMiddlewareResponse<Hummingbird.Response> {
///         var modified = response
///         modified.headers[.init("Access-Control-Max-Age")!] = "3600"
///         return .accept(modified)
///     }
/// }
/// ```
///
/// ### Universal: Logging with Correlation
/// ```swift
/// // Works with any transport (just different Response types)
/// let logger = PostResponseMiddlewareHelpers.from {
///     (context: LambdaMCPContext, envelope: TransportEnvelope, response: APIGatewayResponse, timing: RequestTiming) in
///
///     context.lambdaContext.logger.info("Request completed", metadata: [
///         "method": .string(envelope.mcpRequest.method),
///         "userId": .string(envelope.metadata["userId"] as? String ?? "unknown"),
///         "durationMs": .stringConvertible(timing.duration * 1000),
///         "statusCode": .stringConvertible(response.statusCode.rawValue)
///     ])
///     return .passthrough
/// }
/// ```
///
/// ## Usage
///
/// ```swift
/// // Lambda
/// let adapter = LambdaAdapter()
///     .usePostResponseMiddleware(RequestIDMiddleware())
///     .usePostResponseMiddleware(loggingMiddleware)
///
/// // Hummingbird
/// let adapter = HummingbirdAdapter()
///     .usePostResponseMiddleware(CORSMiddleware())
///     .usePostResponseMiddleware(metricsMiddleware)
/// ```
public protocol PostResponseMiddleware {

    /// The transport-specific response type
    ///
    /// - Lambda: `APIGatewayResponse`
    /// - Hummingbird: `Hummingbird.Response`
    /// - Stdio: `TransportResponse`
    associatedtype Response

    /// Transport-specific context type
    ///
    /// Same as pre-request middleware. Provides access to:
    /// - **LambdaMCPContext**: Lambda execution context and API Gateway request
    /// - **HummingbirdMCPContext**: HTTP request and response context
    /// - **StdioMCPContext**: Environment variables and process information
    associatedtype Context

    /// Convenience alias for the response type
    typealias PostResponseHandlerResponse = PostResponseMiddlewareResponse<Response>

    /// Handle a response in the post-response middleware chain
    ///
    /// This method is called after the router generates a response and the adapter
    /// converts it to a transport-specific format, but before it's sent to the client.
    ///
    /// Implementations should:
    /// 1. Inspect the context and envelope (which includes timing)
    /// 2. Perform any async operations (logging, metrics, external calls)
    /// 3. Return accept (with modified response) or passthrough
    ///
    /// ## Access to Request, Response, and Timing
    ///
    /// The envelope contains the original request (with metadata from pre-request
    /// middleware), the current response, and timing information:
    ///
    /// ```swift
    /// // Access request context
    /// let userId = envelope.request.metadata["userId"] as? String
    /// let method = envelope.request.mcpRequest.method
    ///
    /// // Access response
    /// let statusCode = envelope.response.statusCode
    ///
    /// // Access timing
    /// let durationMs = envelope.timing.duration * 1000
    ///
    /// logger.info("User \(userId) called \(method), status=\(statusCode), duration=\(durationMs)ms")
    /// ```
    ///
    /// - Parameters:
    ///   - context: Transport-specific context (same as pre-request middleware)
    ///   - envelope: Response envelope containing request, response, and timing
    /// - Returns: Response indicating whether to transform or pass through
    /// - Throws: Can throw errors that will propagate to the client
    func handle(
        context: Context,
        envelope: ResponseEnvelope<Response>
    ) async throws -> PostResponseMiddlewareResponse<Response>
}
// MARK: - Post-Response Middleware Helpers

/// Factory utilities for creating post-response middleware from closures
///
/// `PostResponseMiddlewareHelpers` provides convenient factory methods for creating
/// post-response middleware without needing to define explicit struct or class types.
/// This is ideal for simple, inline middleware for logging, metrics, and response
/// transformation.
///
/// ## Benefits
///
/// - **Concise**: No need to define separate types for simple middleware
/// - **Inline**: Create middleware at the point of use
/// - **Type-safe**: Closure signature enforces correct types
/// - **Async-ready**: Full support for async/await operations
///
/// ## Examples
///
/// ### Response Logging
/// ```swift
/// let logger = PostResponseMiddlewareHelpers.from {
///     (context: LambdaMCPContext, envelope: ResponseEnvelope<APIGatewayResponse>) in
///
///     context.lambdaContext.logger.info("Response", metadata: [
///         "method": .string(envelope.request.mcpRequest.method),
///         "durationMs": .stringConvertible(envelope.timing.duration * 1000),
///         "statusCode": .stringConvertible(envelope.response.statusCode.rawValue)
///     ])
///     return .passthrough
/// }
/// ```
///
/// ### Add Request ID Header
/// ```swift
/// let requestId = PostResponseMiddlewareHelpers.from {
///     (context: LambdaMCPContext, envelope: ResponseEnvelope<APIGatewayResponse>) in
///
///     var modified = envelope.response
///     modified.headers["X-Request-ID"] = context.lambdaContext.requestID
///     modified.headers["X-Duration-Ms"] = "\(envelope.timing.duration * 1000)"
///     return .accept(modified)
/// }
/// ```
///
/// ## Usage Pattern
///
/// ```swift
/// // Create middleware with helper
/// let middleware1 = PostResponseMiddlewareHelpers.from { ctx, env in .passthrough }
/// let middleware2 = PostResponseMiddlewareHelpers.from { ctx, env in .passthrough }
///
/// // Add to adapter chain
/// let adapter = LambdaAdapter()
///     .usePostResponseMiddleware(middleware1)
///     .usePostResponseMiddleware(middleware2)
/// ```
public class PostResponseMiddlewareHelpers {

    /// Create post-response middleware from an async closure
    ///
    /// Converts a closure into a `FuncPostResponseMiddleware` instance that conforms
    /// to the `PostResponseMiddleware` protocol. The closure receives transport context
    /// and response envelope (containing request, response, and timing).
    ///
    /// This is the recommended way to create simple post-response middleware without
    /// defining explicit types.
    ///
    /// ## Type Parameters
    ///
    /// - `Response`: Transport-specific response type (APIGatewayResponse, Hummingbird.Response, etc.)
    /// - `Context`: Transport-specific context type (Lambda/Hummingbird/Stdio)
    ///
    /// All types are inferred from the closure signature.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Types inferred from closure signature
    /// let middleware = PostResponseMiddlewareHelpers.from {
    ///     (context: LambdaMCPContext, envelope: ResponseEnvelope<APIGatewayResponse>) in
    ///
    ///     // Access request, response, and timing from envelope
    ///     let method = envelope.request.mcpRequest.method
    ///     let statusCode = envelope.response.statusCode
    ///     let durationMs = envelope.timing.duration * 1000
    ///
    ///     return .passthrough
    /// }
    /// ```
    ///
    /// - Parameter handler: Async closure implementing post-response middleware logic
    /// - Returns: `FuncPostResponseMiddleware` wrapping the closure
    public static func from<Response, Context>(
        _ handler: @escaping (Context, ResponseEnvelope<Response>) async throws -> PostResponseMiddlewareResponse<Response>
    ) -> FuncPostResponseMiddleware<Response, Context> {
        FuncPostResponseMiddleware(callback: handler)
    }

}

/// Closure-based post-response middleware implementation
///
/// `FuncPostResponseMiddleware` wraps a closure to conform to the `PostResponseMiddleware`
/// protocol, enabling functional-style middleware without defining explicit types.
///
/// ## Purpose
///
/// This struct bridges the gap between closures and the `PostResponseMiddleware` protocol,
/// allowing you to use closures anywhere a `PostResponseMiddleware` is expected.
///
/// ## Direct Usage
///
/// While you can create `FuncPostResponseMiddleware` directly, it's more common to use
/// `PostResponseMiddlewareHelpers.from()` which provides better type inference.
///
/// ## Type Parameters
///
/// - `Response`: Transport-specific response type
/// - `Context`: Transport-specific context type
public struct FuncPostResponseMiddleware<Response, Context>: PostResponseMiddleware {

    /// The middleware handler closure
    ///
    /// Stored closure that implements the middleware logic. Called by `handle()`.
    let callback: (Context, ResponseEnvelope<Response>) async throws -> PostResponseMiddlewareResponse<Response>

    /// Execute the middleware closure
    ///
    /// Delegates to the stored closure, passing through all parameters.
    ///
    /// - Parameters:
    ///   - context: Transport-specific context
    ///   - envelope: Response envelope containing request, response, and timing
    /// - Returns: Post-response middleware response (accept/passthrough)
    /// - Throws: Any errors thrown by the closure
    public func handle(
        context: Context,
        envelope: ResponseEnvelope<Response>
    ) async throws -> PostResponseMiddlewareResponse<Response> {
        return try await callback(context, envelope)
    }
}

// MARK: - Type-Erased Post-Response Middleware

/// Type-erased post-response middleware wrapper for heterogeneous collections
///
/// `AnyPostResponseMiddleware` wraps any `PostResponseMiddleware` implementation,
/// hiding its concrete type behind a common interface. This enables storing middleware
/// of different types (structs, classes, closures) in homogeneous collections like arrays.
///
/// ## Purpose
///
/// Enables transport adapters to maintain arrays of post-response middleware with
/// different concrete types while ensuring type safety for envelope, response, and
/// context types.
///
/// ## Example
///
/// ```swift
/// // Store different middleware types in same array
/// let middlewares: [AnyPostResponseMiddleware<APIGatewayResponse, LambdaMCPContext>] = [
///     RequestIDMiddleware().eraseToAnyPostResponseMiddleware(),
///     LoggingMiddleware().eraseToAnyPostResponseMiddleware(),
///     PostResponseMiddlewareHelpers.from { ctx, env in .passthrough }.eraseToAnyPostResponseMiddleware()
/// ]
/// ```
public struct AnyPostResponseMiddleware<Response, Context>: PostResponseMiddleware {

    /// The wrapped middleware's handle method
    ///
    /// Stores a closure that calls the original middleware's `handle()` method.
    /// This enables type erasure while preserving functionality.
    private let _handle: (Context, ResponseEnvelope<Response>) async throws -> PostResponseMiddlewareResponse<Response>

    /// Wrap a concrete post-response middleware, erasing its type
    ///
    /// Creates a type-erased wrapper around any post-response middleware implementation.
    /// The original middleware's behavior is preserved, but its concrete type is hidden.
    ///
    /// ## Type Constraints
    ///
    /// The middleware being wrapped must have:
    /// - Same `Context` type as this `AnyPostResponseMiddleware`
    /// - Same `Response` type as this `AnyPostResponseMiddleware`
    ///
    /// These constraints are enforced at compile time.
    ///
    /// - Parameter middleware: Any post-response middleware implementation with matching types
    public init<M: PostResponseMiddleware>(_ middleware: M)
    where M.Context == Context,
          M.Response == Response {
        self._handle = middleware.handle
    }

    /// Execute the wrapped middleware
    ///
    /// Forwards the call to the wrapped middleware's `handle()` method. The caller
    /// is unaware of the original middleware's type.
    ///
    /// - Parameters:
    ///   - context: Transport-specific context
    ///   - envelope: Response envelope containing request, response, and timing
    /// - Returns: Post-response middleware response from the wrapped implementation
    /// - Throws: Any errors thrown by the wrapped middleware
    public func handle(
        context: Context,
        envelope: ResponseEnvelope<Response>
    ) async throws -> PostResponseMiddlewareResponse<Response> {
        return try await _handle(context, envelope)
    }
}

/// Extension providing convenient type erasure for all post-response middleware
public extension PostResponseMiddleware {

    /// Erase this middleware to `AnyPostResponseMiddleware`
    ///
    /// Convenience method for type erasure. Wraps this middleware in
    /// `AnyPostResponseMiddleware`, hiding its concrete type.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyMiddleware: PostResponseMiddleware { /* ... */ }
    ///
    /// let middleware = MyMiddleware()
    ///
    /// // Type erasure with extension method (readable)
    /// let erased1 = middleware.eraseToAnyPostResponseMiddleware()
    ///
    /// // Type erasure with initializer (verbose)
    /// let erased2 = AnyPostResponseMiddleware(middleware)
    /// ```
    ///
    /// - Returns: Type-erased wrapper around this middleware
    func eraseToAnyPostResponseMiddleware() -> AnyPostResponseMiddleware<Response, Context> {
        return AnyPostResponseMiddleware(self)
    }

}
// MARK: - Post-Response Middleware Chain

/// Sequential executor for post-response middleware with response transformation
///
/// `PostResponseMiddlewareChain` orchestrates the execution of multiple post-response
/// middleware in sequence, allowing each to observe or transform the response before
/// it's sent to the client.
///
/// ## Purpose
///
/// The chain provides:
/// - **Sequential execution**: Middleware runs in registration order
/// - **Response transformation**: Each middleware can modify the response
/// - **Side effects**: Logging, metrics, auditing without modification
/// - **Type safety**: Ensures all middleware share compatible envelope, response, and context types
///
/// ## Processing Flow
///
/// ```
/// Initial Response (from handler)
///     ↓
/// ┌─────────────────────────────────────────────┐
/// │ Middleware 1 (Metrics)                      │
/// │   - Records timing                          │
/// │   - Returns: .passthrough                   │
/// └─────────────────────────────────────────────┘
///     ↓ response unchanged
/// Response
///     ↓
/// ┌─────────────────────────────────────────────┐
/// │ Middleware 2 (Add Headers)                  │
/// │   - Adds X-Request-ID header                │
/// │   - Returns: .accept(modifiedResponse)      │
/// └─────────────────────────────────────────────┘
///     ↓ response = modifiedResponse
/// Modified Response
///     ↓
/// ┌─────────────────────────────────────────────┐
/// │ Middleware 3 (Logging)                      │
/// │   - Logs response details                   │
/// │   - Returns: .passthrough                   │
/// └─────────────────────────────────────────────┘
///     ↓ response unchanged
/// Final Response → Client
/// ```
///
/// ## Type Parameters
///
/// - `ResponseEnvelope`: The envelope type (must conform to `Envelope`)
/// - `Response`: Transport-specific response type (APIGatewayResponse, Hummingbird.Response, etc.)
/// - `Context`: Transport-specific context type (Lambda/Hummingbird/Stdio)
///
/// All middleware in the chain must share these types.
///
/// ## Creating a Chain
///
/// ```swift
/// // Create chain with type parameters
/// let chain = PostResponseMiddlewareChain<APIGatewayResponse, LambdaMCPContext>()
///
/// // Add middleware with .use()
/// chain.use(RequestIDMiddleware())
/// chain.use(LoggingMiddleware())
/// chain.use(PostResponseMiddlewareHelpers.from { ctx, env in .passthrough })
///
/// // Execute chain
/// let finalResponse = try await chain.execute(
///     context: context,
///     envelope: responseEnvelope,
///     timing: timing
/// )
/// ```
///
/// ## Usage in Transport Adapters
///
/// Transport adapters use chains internally:
///
/// ```swift
/// // LambdaAdapter example
/// let adapter = LambdaAdapter()
///     .usePostResponseMiddleware(RequestIDMiddleware())
///     .usePostResponseMiddleware(LoggingMiddleware())
///
/// // Internally, adapter creates and runs a chain:
/// let chain = PostResponseMiddlewareChain<TransportEnvelope, APIGatewayResponse, LambdaMCPContext>()
/// chain.use(requestIdMiddleware)
/// chain.use(loggingMiddleware)
///
/// // On each request (after handler completes):
/// let finalResponse = try await chain.execute(
///     context: context,
///     envelope: envelope,
///     response: initialResponse,
///     timing: timing
/// )
/// ```
///
/// ## Order Matters
///
/// Middleware executes in registration order. Transformations apply sequentially:
///
/// ```swift
/// // ✅ Good: Add headers, then log the headers
/// chain.use(AddHeadersMiddleware())  // Adds X-Request-ID
/// chain.use(LoggingMiddleware())     // Logs including X-Request-ID
///
/// // ❌ Bad: Log before headers added
/// chain.use(LoggingMiddleware())     // Logs without X-Request-ID
/// chain.use(AddHeadersMiddleware())  // Adds X-Request-ID (too late for log)
/// ```
public class PostResponseMiddlewareChain<Response, Context> {

    /// Internal storage of type-erased middleware
    ///
    /// Middleware is stored as `AnyPostResponseMiddleware` to allow heterogeneous
    /// collections (structs, classes, closures all in the same array).
    private var middlewareArr: [AnyPostResponseMiddleware<Response, Context>] = []

    /// Initialize an empty post-response middleware chain
    public init() {}

    /// Append middleware to the end of the chain
    ///
    /// Middleware executes in the order added via `use()`. Each call appends
    /// to the chain, so the first middleware registered runs first.
    ///
    /// ## Type Safety
    ///
    /// The middleware's `Context` and `Response` types must match the chain's types.
    /// This is enforced at compile time via generic constraints.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let chain = PostResponseMiddlewareChain<APIGatewayResponse, LambdaMCPContext>()
    ///
    /// // Add different middleware types
    /// chain.use(RequestIDMiddleware())
    /// chain.use(LoggingMiddleware())
    /// chain.use(PostResponseMiddlewareHelpers.from { ctx, env in .passthrough })
    /// ```
    ///
    /// - Parameter middleware: Middleware to add (automatically type-erased)
    public func use<M: PostResponseMiddleware>(
        _ middleware: M
    ) where Context == M.Context,
            Response == M.Response {
        middlewareArr.append(middleware.eraseToAnyPostResponseMiddleware())
    }

    /// Execute the post-response middleware chain
    ///
    /// Runs all middleware in sequence, allowing each to transform the response.
    /// Processing continues through all middleware, with each receiving the potentially
    /// modified response from the previous middleware.
    ///
    /// ## Execution Semantics
    ///
    /// For each middleware in order:
    /// 1. Call `middleware.handle(context: context, envelope: envelope)`
    /// 2. Handle response:
    ///    - `.accept(modifiedResponse)`: Use modified response for next middleware
    ///    - `.passthrough`: Pass current response unchanged to next middleware
    /// 3. Return final response (potentially modified by middleware chain)
    ///
    /// ## Example
    ///
    /// ```swift
    /// let chain = PostResponseMiddlewareChain<APIGatewayResponse, LambdaMCPContext>()
    /// chain.use(requestIdMiddleware)
    /// chain.use(loggingMiddleware)
    ///
    /// let timing = RequestTiming(startTime: startTime, endTime: Date())
    /// let envelope = ResponseEnvelope(request: requestEnvelope, response: initialResponse, timing: timing)
    ///
    /// // Execute chain
    /// let finalResponse = try await chain.execute(
    ///     context: lambdaContext,
    ///     envelope: envelope
    /// )
    ///
    /// // finalResponse may be modified by middleware
    /// // (e.g., headers added, body transformed, etc.)
    /// return finalResponse
    /// ```
    ///
    /// - Parameters:
    ///   - context: Transport-specific context (same as pre-request)
    ///   - envelope: Response envelope containing request, response, and timing
    /// - Returns: Final response (potentially modified by middleware)
    /// - Throws: Any errors thrown by middleware
    public func execute(
        context: Context,
        envelope: ResponseEnvelope<Response>
    ) async throws -> Response {
        return try await runChain(
            context: context,
            envelope: envelope,
            chain: middlewareArr
        )
    }

    /// Internal recursive chain execution
    ///
    /// Processes middleware one at a time using recursion. This approach:
    /// - Handles each middleware response before proceeding
    /// - Transforms response incrementally via updated envelopes
    /// - Maintains clean async/await semantics
    ///
    /// ## Algorithm
    ///
    /// ```
    /// if chain is empty:
    ///     return envelope.response (base case)
    /// else:
    ///     execute first middleware with current envelope
    ///     if accept(modifiedResponse):
    ///         create new envelope with modified response
    ///         recurse with tail and new envelope
    ///     if passthrough:
    ///         recurse with tail and unchanged envelope
    /// ```
    ///
    /// - Parameters:
    ///   - context: Transport-specific context
    ///   - envelope: Response envelope (updated with each modification, timing preserved)
    ///   - chain: Remaining middleware to execute
    /// - Returns: Final response
    /// - Throws: Any errors from middleware
    private func runChain(
        context: Context,
        envelope: ResponseEnvelope<Response>,
        chain: [AnyPostResponseMiddleware<Response, Context>]
    ) async throws -> Response {
        if let first = chain.first {
            let middlewareResponse = try await first.handle(
                context: context,
                envelope: envelope
            )
            switch middlewareResponse {
            case .accept(let modifiedResponse):
                // Create new envelope with modified response (preserve timing)
                let newEnvelope = ResponseEnvelope(
                    request: envelope.request,
                    response: modifiedResponse,
                    timing: envelope.timing
                )
                let tail = Array(chain.dropFirst())
                return try await runChain(
                    context: context,
                    envelope: newEnvelope,  // Use envelope with modified response
                    chain: tail
                )
            case .passthrough:
                let tail = Array(chain.dropFirst())
                return try await runChain(
                    context: context,
                    envelope: envelope,  // Keep unchanged envelope
                    chain: tail
                )
            }
        } else {
            return envelope.response
        }
    }
}
