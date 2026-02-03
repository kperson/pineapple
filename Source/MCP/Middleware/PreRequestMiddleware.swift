import Foundation
// MARK: - Middleware Response

/// Response from pre-request middleware indicating whether to accept, reject, or pass through a request
///
/// Middleware returns one of three responses after processing a request:
/// - **accept**: Continue processing and merge provided metadata
/// - **passthrough**: Continue processing without adding metadata
/// - **reject**: Stop processing and return error to client
///
/// ## Response Semantics
///
/// ### Accept with Metadata
/// ```swift
/// return .accept(metadata: AuthMetadata(userId: "user-123", role: "admin"))
/// ```
/// - Request continues to next middleware/handler
/// - Metadata is merged into envelope via `envelope.combine(with: metadata)`
/// - Accumulated metadata available in all subsequent middleware and handlers
/// - Use for: auth context, tracing IDs, user data, request annotations
///
/// ### Passthrough
/// ```swift
/// return .passthrough
/// ```
/// - Request continues to next middleware/handler
/// - No metadata changes to envelope
/// - Use for: logging-only middleware, metrics collection, validation that doesn't add context
///
/// ### Reject with Error
/// ```swift
/// return .reject(MCPError(code: .invalidRequest, message: "Unauthorized"))
/// ```
/// - Processing stops immediately
/// - Error returned to client as MCP error response
/// - No subsequent middleware or handlers execute
/// - Use for: failed auth, validation errors, rate limiting, access denial
///
/// ## Examples
///
/// ```swift
/// // Authentication middleware
/// func handle(context: LambdaContext, envelope: RequestEnvelope) async throws -> PreRequestMiddlewareResponse<AuthMetadata> {
///     guard let token = context.headers["Authorization"] else {
///         return .reject(MCPError(code: .invalidRequest, message: "Missing auth header"))
///     }
///
///     let user = try await verifyToken(token)
///     return .accept(metadata: AuthMetadata(userId: user.id, role: user.role))
/// }
///
/// // Logging middleware (no metadata)
/// func handle(context: Context, envelope: RequestEnvelope) async throws -> PreRequestMiddlewareResponse<Void> {
///     logger.info("Request: \(envelope.mcpRequest.method)")
///     return .passthrough
/// }
///
/// // Rate limiting middleware
/// func handle(context: Context, envelope: RequestEnvelope) async throws -> PreRequestMiddlewareResponse<Void> {
///     let allowed = try await checkRateLimit(userId: envelope.metadata.userId)
///     if !allowed {
///         return .reject(MCPError(code: .invalidRequest, message: "Rate limit exceeded"))
///     }
///     return .passthrough
/// }
/// ```
public enum PreRequestMiddlewareResponse<Metadata> {

    /// Accept the request and add metadata to the envelope
    ///
    /// The provided metadata will be merged into the envelope via `envelope.combine(with: metadata)`,
    /// making it available to all subsequent middleware and the final handler.
    ///
    /// - Parameter metadata: Metadata to merge into envelope (auth context, tracing data, etc.)
    case accept(metadata: Metadata)

    /// Continue processing without adding metadata
    ///
    /// Request passes through to next middleware/handler without modifying the envelope.
    /// Use when middleware performs side effects (logging, metrics) but doesn't need
    /// to attach contextual information.
    case passthrough

    /// Reject the request with an error
    ///
    /// Processing stops immediately and the error is returned to the client as an
    /// MCP error response. No subsequent middleware or handlers will execute.
    ///
    /// - Parameter error: MCP error to return (code, message, optional data)
    case reject(MCPError)

}

/// Result of executing a middleware chain
///
/// Similar to `MiddlewareResponse` but carries the enriched envelope instead of just metadata.
/// Returned by `MiddlewareChain.execute()` to allow callers to handle rejection without exceptions.
///
/// ## Example
///
/// ```swift
/// let result = try await chain.execute(context: ctx, envelope: env)
/// switch result {
/// case .accept(let enrichedEnvelope):
    ///     // Continue with enriched envelope
/// case .passthrough(let envelope):
///     // Continue with unchanged envelope
/// case .reject(let error):
///     // Handle rejection
/// }
/// ```
public enum PreRequestMiddlewareChainResult<MiddlewareEnvelope> {

    /// Chain completed successfully with enriched envelope
    ///
    /// At least one middleware added metadata via `.accept()`. The envelope
    /// contains all accumulated metadata from the chain.
    ///
    /// - Parameter envelope: Enriched envelope with accumulated metadata
    case accept(_ envelope: MiddlewareEnvelope)

    /// Chain completed without adding metadata
    ///
    /// All middleware returned `.passthrough` or chain was empty. The envelope
    /// is unchanged from the input.
    ///
    /// - Parameter envelope: Unchanged envelope
    case passthrough(_ envelope: MiddlewareEnvelope)

    /// Chain rejected the request
    ///
    /// One middleware returned `.reject()`, stopping the chain. The error should
    /// be returned to the client.
    ///
    /// - Parameter error: MCP error from rejecting middleware
    case reject(_ error: MCPError)
}


// MARK: - Middleware Protocol

/// Protocol for request interceptors in the MCP processing pipeline
///
/// Middleware provides a powerful extension point for cross-cutting concerns that apply
/// to all or many MCP requests. Each middleware can inspect requests, add contextual
/// metadata, or reject requests before they reach handlers.
///
/// ## Common Use Cases
///
/// - **Authentication**: Verify tokens, validate sessions, extract user identity
/// - **Authorization**: Check permissions, enforce access control policies
/// - **Logging**: Record requests, audit actions, track usage patterns
/// - **Tracing**: Add correlation IDs, distributed tracing spans, request flow tracking
/// - **Rate Limiting**: Throttle requests, prevent abuse, enforce quotas
/// - **Validation**: Check request structure, sanitize input, verify preconditions
/// - **Metrics**: Collect timing data, count requests, track errors
/// - **Caching**: Check cache before processing, store results
/// - **Transformation**: Modify requests, normalize data, apply defaults
///
/// ## Architecture
///
/// Middleware executes in a chain before the MCP server processes requests:
///
/// ```
/// HTTP/Stdio/Lambda Request
///     ↓
/// Create Envelope
///     ↓
/// ┌─────────────────────────┐
/// │  Middleware Chain       │
/// ├─────────────────────────┤
/// │  1. Auth Middleware     │  ← Extract & verify user
/// │  2. Logging Middleware  │  ← Log request details
/// │  3. Metrics Middleware  │  ← Record timing
/// │  4. Custom Middleware   │  ← Business logic
/// └─────────────────────────┘
///     ↓
/// MCP Router/Server
///     ↓
/// Tool/Resource/Prompt Handler
/// ```
///
/// Each middleware receives:
/// - **Context**: Transport-specific data (headers, environment, Lambda context)
/// - **Envelope**: MCP request + accumulated metadata from previous middleware
///
/// Each middleware returns:
/// - **accept(metadata)**: Continue and add metadata
/// - **passthrough**: Continue without adding metadata
/// - **reject(error)**: Stop processing and return error
///
/// ## Associated Types
///
/// ### MiddlewareEnvelope
/// The envelope type this middleware processes. Must conform to `Envelope` protocol.
/// Different transports may use different envelope types with different metadata structures.
///
/// Example:
/// ```swift
/// struct LambdaEnvelope: Envelope {
///     let mcpRequest: MCPRequest
///     var metadata: AuthMetadata
///     func combine(with meta: AuthMetadata) -> LambdaEnvelope { ... }
/// }
/// ```
///
/// ### Context
/// Transport-specific context providing access to:
/// - **LambdaMCPContext**: Lambda context, API Gateway request, event
/// - **HummingbirdMCPContext**: HTTP request, response, headers
/// - **StdioMCPContext**: Environment variables, process info
///
/// ## Type Alias
///
/// ### MiddlewareHandlerResponse
/// Convenience alias for the response type: `PreRequestMiddlewareResponse<MiddlewareEnvelope.Metadata>`
///
/// ## Example Implementation
///
/// ```swift
/// // Authentication middleware for Lambda
/// struct LambdaAuthMiddleware: Middleware {
///     typealias MiddlewareEnvelope = LambdaRequestEnvelope
///     typealias Context = LambdaMCPContext
///
///     func handle(
///         context: LambdaMCPContext,
///         envelope: LambdaRequestEnvelope
///     ) async throws -> PreRequestMiddlewareResponse<AuthMetadata> {
///         // Extract token from API Gateway headers
///         guard let authHeader = context.apiGatewayRequest.headers["Authorization"],
///               let token = authHeader.split(separator: " ").last else {
///             return .reject(MCPError(
///                 code: .invalidRequest,
///                 message: "Missing or invalid Authorization header"
///             ))
///         }
///
///         // Verify token (async operation)
///         do {
///             let claims = try await jwtVerifier.verify(String(token))
///             let userId = claims.subject
///             let role = claims["role"] as? String ?? "user"
///
///             // Add auth metadata to envelope
///             return .accept(metadata: AuthMetadata(
///                 userId: userId,
///                 role: role,
///                 authenticatedAt: Date()
///             ))
///         } catch {
///             return .reject(MCPError(
///                 code: .invalidRequest,
///                 message: "Invalid token: \(error.localizedDescription)"
///             ))
///         }
///     }
/// }
///
/// // Usage
/// let adapter = LambdaAdapter()
///     .usePreRequestMiddleware(LambdaAuthMiddleware())
///     .usePreRequestMiddleware(LoggingMiddleware())
/// ```
///
/// ## Accessing Context Data
///
/// Different contexts provide different capabilities:
///
/// ```swift
/// // Lambda: Access API Gateway data
/// func handle(context: LambdaMCPContext, envelope: E) async throws -> PreRequestMiddlewareResponse<M> {
///     let queryParams = context.apiGatewayRequest.queryStringParameters
///     let headers = context.apiGatewayRequest.headers
///     let sourceIP = context.apiGatewayRequest.requestContext.identity.sourceIp
///     // ...
/// }
///
/// // Hummingbird: Access HTTP request
/// func handle(context: HummingbirdMCPContext, envelope: E) async throws -> PreRequestMiddlewareResponse<M> {
///     let cookies = context.request.cookies
///     let userAgent = context.request.headers["User-Agent"]
///     // ...
/// }
///
/// // Stdio: Access environment
/// func handle(context: StdioMCPContext, envelope: E) async throws -> PreRequestMiddlewareResponse<M> {
///     let workingDir = context.workingDirectory
///     let env = context.environmentVariables
///     // ...
/// }
/// ```
///
/// ## Metadata Flow
///
/// Metadata accumulates through the chain and becomes available in handlers:
///
/// ```swift
/// // Middleware 1: Add auth
/// return .accept(metadata: AuthMetadata(userId: "user-123"))
///
/// // Middleware 2: Add tracing
/// return .accept(metadata: TracingMetadata(traceId: UUID()))
///
/// // Handler receives envelope with both:
/// envelope.metadata.userId   // "user-123"
/// envelope.metadata.traceId  // UUID from middleware 2
/// ```
public protocol PreRequestMiddleware {

    /// The envelope type this middleware processes
    ///
    /// Must conform to `Envelope` protocol. Different transports may use different
    /// envelope types with transport-specific metadata structures.
    associatedtype MiddlewareEnvelope: Envelope

    /// Transport-specific context type
    ///
    /// Provides access to transport-specific data:
    /// - **LambdaMCPContext**: Lambda execution context and API Gateway request
    /// - **HummingbirdMCPContext**: HTTP request and response objects
    /// - **StdioMCPContext**: Environment variables and process information
    associatedtype Context

    /// Convenience alias for the response type
    ///
    /// Equivalent to `PreRequestMiddlewareResponse<MiddlewareEnvelope.Metadata>`
    typealias PreRequestMiddlewareHandlerResponse = PreRequestMiddlewareResponse<MiddlewareEnvelope.Metadata>

    /// Handle a request in the middleware chain
    ///
    /// This method is called for each request passing through the middleware chain.
    /// Implementations should:
    /// 1. Inspect the context and envelope
    /// 2. Perform any async operations (auth, logging, etc.)
    /// 3. Return accept (with metadata), passthrough, or reject
    ///
    /// - Parameters:
    ///   - context: Transport-specific context with headers, environment, etc.
    ///   - envelope: Request envelope with MCP request and accumulated metadata
    /// - Returns: Response indicating whether to accept, pass through, or reject
    /// - Throws: Can throw errors that will propagate to the client
    func handle(context: Context, envelope: MiddlewareEnvelope) async throws -> PreRequestMiddlewareResponse<MiddlewareEnvelope.Metadata>

}
// MARK: - Middleware Helpers

/// Factory utilities for creating middleware from closures
///
/// `MiddlewareHelpers` provides convenient factory methods for creating middleware without
/// needing to define explicit struct or class types. This is ideal for simple, inline
/// middleware that doesn't require complex state or initialization.
///
/// ## Benefits
///
/// - **Concise**: No need to define separate types for simple middleware
/// - **Inline**: Create middleware at the point of use
/// - **Type-safe**: Closure signature enforces correct types
/// - **Async-ready**: Full support for async/await operations
///
/// ## When to Use
///
/// Use closure-based middleware for:
/// - Simple logging or metrics collection
/// - Quick prototypes and testing
/// - One-off middleware that won't be reused
/// - Middleware that doesn't need complex initialization
///
/// For complex middleware with:
/// - Initialization parameters (API keys, configuration)
/// - Shared state across requests
/// - Complex business logic
/// - Reusability across projects
///
/// Consider defining a proper struct/class conforming to `Middleware` instead.
///
/// ## Examples
///
/// ### Logging Middleware
/// ```swift
/// let logger = PreRequestMiddlewareHelpers.from { (context: LambdaMCPContext, envelope: RequestEnvelope) in
///     context.lambdaContext.logger.info("MCP Request", metadata: [
///         "method": .string(envelope.mcpRequest.method),
///         "requestId": .string(context.lambdaContext.requestID)
///     ])
///     return .passthrough
/// }
/// ```
///
/// ### Simple Auth Check
/// ```swift
/// let auth = PreRequestMiddlewareHelpers.from { (context: HummingbirdMCPContext, envelope: RequestEnvelope) in
///     guard let apiKey = context.request.headers["X-API-Key"],
///           apiKey == expectedKey else {
///         return .reject(MCPError(code: .invalidRequest, message: "Invalid API key"))
///     }
///     return .accept(metadata: AuthMetadata(authenticated: true))
/// }
/// ```
///
/// ### Request Validation
/// ```swift
/// let validator = PreRequestMiddlewareHelpers.from { (context: Context, envelope: RequestEnvelope) in
///     // Validate request size
///     let requestSize = try JSONEncoder().encode(envelope.mcpRequest).count
///     guard requestSize < 1_000_000 else {
///         return .reject(MCPError(code: .invalidRequest, message: "Request too large"))
///     }
///     return .passthrough
/// }
/// ```
///
/// ### Async External Service
/// ```swift
/// let featureFlags = PreRequestMiddlewareHelpers.from { (context: Context, envelope: RequestEnvelope) in
///     // Async call to feature flag service
///     let flags = try await featureFlagClient.fetch(userId: envelope.metadata.userId)
///     return .accept(metadata: FeatureFlagMetadata(flags: flags))
/// }
/// ```
///
/// ## Usage Pattern
///
/// ```swift
/// // Create middleware with helper
/// let middleware1 = PreRequestMiddlewareHelpers.from { (ctx, env) in .passthrough }
/// let middleware2 = PreRequestMiddlewareHelpers.from { (ctx, env) in .passthrough }
///
/// // Add to adapter chain
/// let adapter = LambdaAdapter()
///     .usePreRequestMiddleware(middleware1)
///     .usePreRequestMiddleware(middleware2)
/// ```
public class PreRequestMiddlewareHelpers {

    /// Create middleware from an async closure
    ///
    /// Converts a closure into a type-erased `FuncMiddleware` instance that conforms
    /// to the `Middleware` protocol. The closure receives transport context and request
    /// envelope, and returns a middleware response.
    ///
    /// This is the recommended way to create simple middleware without defining
    /// explicit types.
    ///
    /// ## Type Parameters
    ///
    /// - `MiddlewareEnvelope`: The envelope type (must conform to `Envelope`)
    /// - `Context`: Transport-specific context type (Lambda/Hummingbird/Stdio)
    ///
    /// Both types are inferred from the closure signature.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Types inferred from closure signature
    /// let middleware = PreRequestMiddlewareHelpers.from {
    ///     (context: LambdaMCPContext, envelope: LambdaRequestEnvelope) in
    ///
    ///     // Your middleware logic
    ///     return .passthrough
    /// }
    /// ```
    ///
    /// - Parameter handler: Async closure implementing middleware logic
    /// - Returns: `FuncMiddleware` wrapping the closure, ready to use in chains
    public static func from<MiddlewareEnvelope: Envelope, Context>(
        _ handler: @escaping (Context, MiddlewareEnvelope) async throws -> PreRequestMiddlewareResponse<MiddlewareEnvelope.Metadata>
    ) -> FuncPreRequestMiddleware<MiddlewareEnvelope, Context> {
        FuncPreRequestMiddleware(callback: handler)
    }

}

/// Closure-based middleware implementation
///
/// `FuncMiddleware` wraps a closure to conform to the `Middleware` protocol, enabling
/// functional-style middleware without defining explicit types. It's the underlying
/// implementation created by `PreRequestMiddlewareHelpers.from()`.
///
/// ## Purpose
///
/// This struct bridges the gap between closures and the `Middleware` protocol,
/// allowing you to use closures anywhere a `Middleware` is expected.
///
/// ## Direct Usage
///
/// While you can create `FuncMiddleware` directly, it's more common to use
/// `PreRequestMiddlewareHelpers.from()` which provides better type inference:
///
/// ```swift
/// // Direct creation (verbose)
/// let middleware1 = FuncPreRequestMiddleware<RequestEnvelope, LambdaMCPContext> { context, envelope in
///     return .passthrough
/// }
///
/// // Helper method (recommended - types inferred)
/// let middleware2 = PreRequestMiddlewareHelpers.from { (context: LambdaMCPContext, envelope: RequestEnvelope) in
///     return .passthrough
/// }
/// ```
///
/// ## Type Parameters
///
/// - `MiddlewareEnvelope`: The envelope type (must conform to `Envelope`)
/// - `Context`: Transport-specific context type
///
/// ## Implementation Details
///
/// `FuncMiddleware` simply stores the closure and delegates to it when `handle()` is called.
/// This allows closures to participate in middleware chains alongside struct/class middleware.
public struct FuncPreRequestMiddleware<MiddlewareEnvelope: Envelope, Context>: PreRequestMiddleware {

    /// The middleware handler closure
    ///
    /// Stored closure that implements the middleware logic. Called by `handle()`.
    let callback: (Context, MiddlewareEnvelope) async throws -> PreRequestMiddlewareResponse<MiddlewareEnvelope.Metadata>

    /// Execute the middleware closure
    ///
    /// Delegates to the stored closure, passing through context and envelope.
    ///
    /// - Parameters:
    ///   - context: Transport-specific context
    ///   - envelope: Request envelope with accumulated metadata
    /// - Returns: Middleware response (accept/passthrough/reject)
    /// - Throws: Any errors thrown by the closure
    public func handle(context: Context, envelope: MiddlewareEnvelope) async throws -> PreRequestMiddlewareResponse<MiddlewareEnvelope.Metadata> {
        return try await callback(context, envelope)
    }
}

// MARK: - Type-Erased Middleware

/// Type-erased middleware wrapper for heterogeneous collections
///
/// `AnyMiddleware` wraps any `Middleware` implementation, hiding its concrete type
/// behind a common interface. This enables storing middleware of different types
/// (structs, classes, closures) in homogeneous collections like arrays.
///
/// ## Purpose
///
/// Swift's type system requires collections to have a single concrete type. Without
/// type erasure, you cannot store `AuthMiddleware`, `LoggingMiddleware`, and
/// `RateLimitMiddleware` in the same array, even though they all conform to `Middleware`.
///
/// `AnyMiddleware` solves this by:
/// 1. Wrapping any middleware implementation
/// 2. Forwarding `handle()` calls to the wrapped implementation
/// 3. Presenting a uniform type that can be stored in collections
///
/// ## When It's Used
///
/// - **MiddlewareChain**: Stores middleware in `[AnyPreRequestMiddleware<E, C>]` internally
/// - **Dynamic middleware lists**: When you need to build middleware arrays at runtime
/// - **Library code**: When exposing middleware without revealing implementation types
///
/// ## Type Parameters
///
/// - `MiddlewareEnvelope`: The envelope type (must conform to `Envelope`)
/// - `Context`: Transport-specific context type
///
/// Both must match across all middleware in the same collection.
///
/// ## Examples
///
/// ### Manual Type Erasure
/// ```swift
/// struct AuthMiddleware: Middleware { /* ... */ }
/// struct LoggingMiddleware: Middleware { /* ... */ }
/// struct MetricsMiddleware: Middleware { /* ... */ }
///
/// // Without type erasure - compile error!
/// // let middlewares = [AuthMiddleware(), LoggingMiddleware()]  // Error: different types
///
/// // With type erasure - works!
/// let middlewares: [AnyPreRequestMiddleware<RequestEnvelope, LambdaMCPContext>] = [
///     AnyMiddleware(AuthMiddleware()),
///     AnyMiddleware(LoggingMiddleware()),
///     AnyMiddleware(MetricsMiddleware())
/// ]
/// ```
///
/// ### Using the Extension Method
/// ```swift
/// // More concise with .eraseToAnyPreRequestMiddleware()
/// let middlewares = [
///     AuthMiddleware().eraseToAnyPreRequestMiddleware(),
///     LoggingMiddleware().eraseToAnyPreRequestMiddleware(),
///     PreRequestMiddlewareHelpers.from { ctx, env in .passthrough }.eraseToAnyPreRequestMiddleware()
/// ]
/// ```
///
/// ### Dynamic Middleware Building
/// ```swift
/// func buildMiddlewareStack(includeAuth: Bool) -> [AnyPreRequestMiddleware<E, C>] {
///     var stack: [AnyPreRequestMiddleware<E, C>] = []
///
///     // Always add logging
///     stack.append(LoggingMiddleware().eraseToAnyPreRequestMiddleware())
///
///     // Conditionally add auth
///     if includeAuth {
///         stack.append(AuthMiddleware().eraseToAnyPreRequestMiddleware())
///     }
///
///     // Add metrics
///     stack.append(MetricsMiddleware().eraseToAnyPreRequestMiddleware())
///
///     return stack
/// }
/// ```
///
/// ## Implementation Details
///
/// Type erasure works by storing the `handle()` method as a closure, not the
/// middleware instance itself. This means:
/// - No runtime overhead beyond a closure call
/// - Original middleware type information is lost (by design)
/// - Middleware is executed as if called directly
public struct AnyPreRequestMiddleware<MiddlewareEnvelope: Envelope, Context>: PreRequestMiddleware {

    /// The wrapped middleware's handle method
    ///
    /// Stores a closure that calls the original middleware's `handle()` method.
    /// This enables type erasure while preserving functionality.
    private let _handle: (Context, MiddlewareEnvelope) async throws -> PreRequestMiddlewareResponse<MiddlewareEnvelope.Metadata>

    /// Wrap a concrete middleware, erasing its type
    ///
    /// Creates a type-erased wrapper around any middleware implementation. The original
    /// middleware's behavior is preserved, but its concrete type is hidden.
    ///
    /// ## Type Constraints
    ///
    /// The middleware being wrapped must have:
    /// - Same `Context` type as this `AnyMiddleware`
    /// - Same `MiddlewareEnvelope` type as this `AnyMiddleware`
    ///
    /// These constraints are enforced at compile time.
    ///
    /// - Parameter middleware: Any middleware implementation with matching types
    public init<M: PreRequestMiddleware>(_ middleware: M) where M.Context == Context, M.MiddlewareEnvelope == MiddlewareEnvelope {
        self._handle = middleware.handle
    }

    /// Execute the wrapped middleware
    ///
    /// Forwards the call to the wrapped middleware's `handle()` method. The caller
    /// is unaware of the original middleware's type.
    ///
    /// - Parameters:
    ///   - context: Transport-specific context
    ///   - envelope: Request envelope with accumulated metadata
    /// - Returns: Middleware response from the wrapped implementation
    /// - Throws: Any errors thrown by the wrapped middleware
    public func handle(context: Context, envelope: MiddlewareEnvelope) async throws -> PreRequestMiddlewareResponse<MiddlewareEnvelope.Metadata> {
        return try await _handle(context, envelope)
    }
}

/// Extension providing convenient type erasure for all middleware
public extension PreRequestMiddleware {

    /// Erase this middleware to `AnyMiddleware`
    ///
    /// Convenience method for type erasure. Wraps this middleware in `AnyMiddleware`,
    /// hiding its concrete type. Equivalent to `AnyMiddleware(self)` but more readable.
    ///
    /// ## Purpose
    ///
    /// Use this when you need to:
    /// - Add middleware to heterogeneous collections
    /// - Store middleware in arrays with different concrete types
    /// - Pass middleware to APIs that expect type-erased middleware
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyMiddleware: Middleware { /* ... */ }
    ///
    /// let middleware = MyMiddleware()
    ///
    /// // Type erasure with extension method (readable)
    /// let erased1 = middleware.eraseToAnyPreRequestMiddleware()
    ///
    /// // Type erasure with initializer (verbose)
    /// let erased2 = AnyMiddleware(middleware)
    ///
    /// // Use in array
    /// let stack = [
    ///     AuthMiddleware().eraseToAnyPreRequestMiddleware(),
    ///     MyMiddleware().eraseToAnyPreRequestMiddleware(),
    ///     LoggingMiddleware().eraseToAnyPreRequestMiddleware()
    /// ]
    /// ```
    ///
    /// - Returns: Type-erased wrapper around this middleware
    func eraseToAnyPreRequestMiddleware() -> AnyPreRequestMiddleware<MiddlewareEnvelope, Context> {
        return AnyPreRequestMiddleware(self)
    }

}
// MARK: - Middleware Chain

/// Sequential executor for middleware with metadata accumulation
///
/// `MiddlewareChain` orchestrates the execution of multiple middleware in sequence,
/// building up contextual metadata at each step. It's the core engine that powers
/// the middleware system in MCP transport adapters.
///
/// ## Purpose
///
/// The chain provides:
/// - **Sequential execution**: Middleware runs in registration order
/// - **Metadata accumulation**: Each middleware's metadata merges into the envelope
/// - **Early termination**: Any middleware can stop processing by rejecting
/// - **Type safety**: Ensures all middleware share compatible envelope and context types
///
/// ## Processing Flow
///
/// ```
/// Initial Envelope
///     ↓
/// ┌─────────────────────────────────────────────┐
/// │ Middleware 1 (Auth)                         │
/// │   - Verifies token                          │
/// │   - Returns: .accept(userId: "user-123")    │
/// └─────────────────────────────────────────────┘
///     ↓ envelope = envelope.combine(metadata)
/// Envelope { metadata: { userId: "user-123" } }
///     ↓
/// ┌─────────────────────────────────────────────┐
/// │ Middleware 2 (Tracing)                      │
/// │   - Generates trace ID                      │
/// │   - Returns: .accept(traceId: "trace-456")  │
/// └─────────────────────────────────────────────┘
///     ↓ envelope = envelope.combine(metadata)
/// Envelope { metadata: { userId: "user-123", traceId: "trace-456" } }
///     ↓
/// ┌─────────────────────────────────────────────┐
/// │ Middleware 3 (Logging)                      │
/// │   - Logs request                            │
/// │   - Returns: .passthrough                   │
/// └─────────────────────────────────────────────┘
///     ↓ no changes
/// Envelope { metadata: { userId: "user-123", traceId: "trace-456" } }
///     ↓
/// MCP Router/Server
/// ```
///
/// ## Metadata Flow
///
/// Each middleware in the chain can:
/// - **Read** metadata added by previous middleware
/// - **Add** new metadata via `.accept(metadata: ...)`
/// - **Pass through** without changing metadata
/// - **Reject** and halt the entire chain
///
/// Metadata merges via `envelope.combine(with: metadata)`, making all accumulated
/// context available to handlers.
///
/// ## Type Parameters
///
/// - `MiddlewareEnvelope`: The envelope type (must conform to `Envelope`)
/// - `Context`: Transport-specific context type (Lambda/Hummingbird/Stdio)
///
/// All middleware in the chain must share these types.
///
/// ## Creating a Chain
///
/// ```swift
/// // Create chain with type parameters
/// let chain = PreRequestMiddlewareChain<RequestEnvelope, LambdaMCPContext>()
///
/// // Add middleware with .use()
/// chain.use(AuthMiddleware())
/// chain.use(LoggingMiddleware())
/// chain.use(PreRequestMiddlewareHelpers.from { ctx, env in .passthrough })
///
/// // Execute chain
/// let enrichedEnvelope = try await chain.envelope(initialEnvelope, context: lambdaContext)
/// ```
///
/// ## Usage in Transport Adapters
///
/// Transport adapters (Lambda, Hummingbird, Stdio) use chains internally:
///
/// ```swift
/// // LambdaAdapter example
/// let adapter = LambdaAdapter()
///     .usePreRequestMiddleware(AuthMiddleware())
///     .usePreRequestMiddleware(LoggingMiddleware())
///
/// // Internally, adapter creates and runs a chain:
/// let chain = PreRequestMiddlewareChain<LambdaRequestEnvelope, LambdaMCPContext>()
/// chain.use(authMiddleware)
/// chain.use(loggingMiddleware)
///
/// // On each request:
/// let enrichedEnvelope = try await chain.envelope(envelope, context: context)
/// let response = try await router.route(enrichedEnvelope)
/// ```
///
/// ## Error Handling
///
/// Middleware can reject requests with `MCPError`:
///
/// ```swift
/// chain.use(PreRequestMiddlewareHelpers.from { ctx, env in
///     guard authorized else {
///         return .reject(MCPError(code: .invalidRequest, message: "Unauthorized"))
///     }
///     return .passthrough
/// })
///
/// // If middleware rejects:
/// do {
///     let result = try await chain.envelope(envelope, context: context)
/// } catch let error as MCPError {
///     // Handle rejection: return error to client
/// }
/// ```
///
/// ## Order Matters
///
/// Middleware executes in registration order. Dependencies should come first:
///
/// ```swift
/// // ✅ Good: Auth before authorization
/// chain.use(AuthMiddleware())          // Adds userId
/// chain.use(AuthorizationMiddleware()) // Uses userId
///
/// // ❌ Bad: Authorization before auth
/// chain.use(AuthorizationMiddleware()) // No userId yet!
/// chain.use(AuthMiddleware())
/// ```
///
/// ## Performance Considerations
///
/// - **Async overhead**: Each middleware is an async call
/// - **Metadata merging**: `combine()` called for each `.accept()`
/// - **Short-circuit**: `.reject()` stops processing immediately
/// - **Type erasure**: Minimal overhead via closure storage
///
/// For best performance:
/// - Keep middleware focused and fast
/// - Use `.passthrough` when no metadata needed
/// - Place rejecting middleware (auth) early in chain
///
/// ## Implementation Details
///
/// The chain uses:
/// - **Recursive execution**: `runChain()` processes one middleware at a time
/// - **Type erasure**: Stores `[AnyPreRequestMiddleware<E, C>]` internally
/// - **Immutable envelopes**: Each middleware receives and returns envelopes
public class PreRequestMiddlewareChain<MiddlewareEnvelope: Envelope, Context> {

    /// Internal storage of type-erased middleware
    ///
    /// Middleware is stored as `AnyMiddleware` to allow heterogeneous collections
    /// (structs, classes, closures all in the same array).
    private var middlewareArr: [AnyPreRequestMiddleware<MiddlewareEnvelope, Context>] = []

    /// Initialize an empty middleware chain
    public init () {}

    /// Append middleware to the end of the chain
    ///
    /// Middleware executes in the order added via `use()`. Each call appends
    /// to the chain, so the first middleware registered runs first.
    ///
    /// ## Type Safety
    ///
    /// The middleware's `Context` and `MiddlewareEnvelope` types must match the
    /// chain's types. This is enforced at compile time via generic constraints.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let chain = PreRequestMiddlewareChain<RequestEnvelope, LambdaMCPContext>()
    ///
    /// // Add different middleware types
    /// chain.use(AuthMiddleware())
    /// chain.use(LoggingMiddleware())
    /// chain.use(PreRequestMiddlewareHelpers.from { ctx, env in .passthrough })
    /// ```
    ///
    /// - Parameter middleware: Middleware to add (automatically type-erased)
    public func use<M: PreRequestMiddleware>(
        _ middleware: M
    ) where Context == M.Context, MiddlewareEnvelope == M.MiddlewareEnvelope {
        middlewareArr.append(middleware.eraseToAnyPreRequestMiddleware())
    }

    /// Execute the middleware chain and return enriched envelope
    ///
    /// Runs all middleware in sequence, accumulating metadata in the envelope.
    /// Processing continues until:
    /// - All middleware accept/passthrough → returns enriched envelope
    /// - Any middleware rejects → throws error immediately
    ///
    /// ## Execution Semantics
    ///
    /// For each middleware in order:
    /// 1. Call `middleware.handle(context: context, envelope: currentEnvelope)`
    /// 2. Handle response:
    ///    - `.accept(metadata)`: Merge via `envelope.combine(with: metadata)`, continue
    ///    - `.passthrough`: Continue without changes
    ///    - `.reject(error)`: Throw error, stop chain
    /// 3. Return final envelope with all accumulated metadata
    ///
    /// ## Example
    ///
    /// ```swift
    /// let chain = PreRequestMiddlewareChain<RequestEnvelope, LambdaMCPContext>()
    /// chain.use(authMiddleware)
    /// chain.use(loggingMiddleware)
    ///
    /// do {
    ///     // Execute chain
    ///     let enrichedEnvelope = try await chain.envelope(
    ///         initialEnvelope,
    ///         context: lambdaContext
    ///     )
    ///
    ///     // enrichedEnvelope.metadata contains all accumulated context
    ///     print(enrichedEnvelope.metadata.userId)   // from authMiddleware
    ///     print(enrichedEnvelope.metadata.traceId)  // from loggingMiddleware
    ///
    ///     // Pass to handler
    ///     let response = try await handler.handle(enrichedEnvelope)
    /// } catch let error as MCPError {
    ///     // Middleware rejected request
    ///     return errorResponse(error)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - envelope: Initial request envelope with MCP request
    ///   - context: Transport-specific context (headers, environment, etc.)
    /// - Returns: Envelope enriched with metadata from all accepting middleware
    /// - Throws: `MCPError` if any middleware rejects the request
    public func envelope(_ envelope: MiddlewareEnvelope, context: Context) async throws -> MiddlewareEnvelope {
        return try await runChain(envelope: envelope, chain: middlewareArr, context: context)
    }

    /// Execute the middleware chain and return a result
    ///
    /// Similar to `envelope()` but returns a `MiddlewareChainResult` instead of throwing.
    /// This allows callers to handle rejection as a value rather than an exception.
    ///
    /// ## Use Cases
    ///
    /// Use this method when you need to:
    /// - Handle rejection and acceptance in the same switch statement
    /// - Get the enriched envelope along with the result
    /// - Avoid try/catch for middleware rejection handling
    ///
    /// ## Example
    ///
    /// ```swift
    /// let result = try await chain.execute(context: ctx, envelope: env)
    /// switch result {
    /// case .accept(let enrichedEnvelope):
    ///     // Process with enriched metadata
    /// case .passthrough(let envelope):
    ///     // Process without additional metadata
    /// case .reject(let error):
    ///     // Handle rejection
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - context: Transport-specific context
    ///   - envelope: Initial request envelope
    /// - Returns: MiddlewareChainResult with enriched envelope or error
    public func execute(context: Context, envelope: MiddlewareEnvelope) async throws -> PreRequestMiddlewareChainResult<MiddlewareEnvelope> {
        do {
            let result = try await self.runChainWithTracking(envelope: envelope, chain: middlewareArr, context: context)
            if middlewareArr.isEmpty || !result.anyAccepted {
                return .passthrough(result.envelope)
            } else {
                return .accept(result.envelope)
            }
        } catch let error as MCPError {
            return .reject(error)
        }
    }

    /// Internal helper struct for tracking middleware execution results
    private struct ChainExecutionResult {
        let envelope: MiddlewareEnvelope
        let anyAccepted: Bool
    }

    /// Internal recursive chain execution with tracking
    ///
    /// Same as runChain but also tracks whether any middleware returned .accept()
    private func runChainWithTracking(envelope: MiddlewareEnvelope, chain: [AnyPreRequestMiddleware<MiddlewareEnvelope, Context>], context: Context) async throws -> ChainExecutionResult {
        if let first = chain.first {
            let response = try await first.handle(context: context, envelope: envelope)
            switch response {
            case .accept(metadata: let metadata):
                let tail = Array(chain.dropFirst())
                let newEnvelope = envelope.combine(with: metadata)
                let restResult = try await runChainWithTracking(envelope: newEnvelope, chain: tail, context: context)
                return ChainExecutionResult(envelope: restResult.envelope, anyAccepted: true)
            case .passthrough:
                let tail = Array(chain.dropFirst())
                return try await runChainWithTracking(envelope: envelope, chain: tail, context: context)
            case .reject(let error): throw error
            }
        } else {
            return ChainExecutionResult(envelope: envelope, anyAccepted: false)
        }
    }

    /// Internal recursive chain execution
    ///
    /// Processes middleware one at a time using recursion. This approach:
    /// - Handles each middleware response before proceeding
    /// - Builds up metadata incrementally
    /// - Short-circuits on rejection
    /// - Maintains clean async/await semantics
    ///
    /// ## Algorithm
    ///
    /// ```
    /// if chain is empty:
    ///     return envelope (base case)
    /// else:
    ///     execute first middleware
    ///     if accept(metadata):
    ///         merge metadata into envelope
    ///         recurse with tail and merged envelope
    ///     if passthrough:
    ///         recurse with tail and unchanged envelope
    ///     if reject(error):
    ///         throw error (stops recursion)
    /// ```
    ///
    /// - Parameters:
    ///   - envelope: Current envelope (accumulating metadata)
    ///   - chain: Remaining middleware to execute
    ///   - context: Transport-specific context
    /// - Returns: Final envelope with all metadata
    /// - Throws: `MCPError` if any middleware rejects
    private func runChain(envelope: MiddlewareEnvelope, chain: [AnyPreRequestMiddleware<MiddlewareEnvelope, Context>], context: Context) async throws -> MiddlewareEnvelope {
        if let first = chain.first {
            let response = try await first.handle(context: context, envelope: envelope)
            switch response {
            case .accept(metadata: let metadata):
                let tail = Array(chain.dropFirst())
                let newEnvelope = envelope.combine(with: metadata)
                return try await runChain(envelope: newEnvelope, chain: tail, context: context)
            case .passthrough:
                let tail = Array(chain.dropFirst())
                return try await runChain(envelope: envelope, chain: tail, context: context)
            case .reject(let error): throw error
            }
        } else {
            return envelope
        }
    }
}
