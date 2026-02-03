import Foundation

// MARK: - Middleware Architecture
//
// This file implements a generic, type-safe middleware system for MCP request processing.
//
// ## Core Concepts
//
// 1. **Envelope Protocol**: Containers that wrap MCP requests and accumulate metadata
// 2. **Middleware Protocol**: Request interceptors that can inspect, modify, or reject requests
// 3. **Middleware Chain**: Sequential execution of middleware with metadata accumulation
// 4. **Type Erasure**: Heterogeneous middleware storage via AnyMiddleware
//
// ## Request Flow
//
// ```
// Transport (HTTP/Stdio/Lambda)
//     ↓
// Create Envelope with MCP Request
//     ↓
// Middleware Chain Execution:
//     Middleware 1 (Auth)      → Accept + add userId
//     Middleware 2 (Logging)   → Accept + add traceId
//     Middleware 3 (Metrics)   → Passthrough
//     ↓
// Enriched Envelope with accumulated metadata
//     ↓
// MCP Server/Router
//     ↓
// Handler (with full context)
// ```
//
// ## Metadata Accumulation
//
// Each middleware can add metadata that flows through to handlers:
// - **Auth middleware**: Add user ID, role, tenant ID
// - **Tracing middleware**: Add trace ID, span ID, parent context
// - **Logging middleware**: Add request ID, correlation ID
// - **Metrics middleware**: Add timing, counters
//
// Metadata merges via `envelope.combine(with: metadata)`, allowing handlers
// to access all contextual information from the middleware chain.
//
// ## Transport-Specific Contexts
//
// The generic `Context` type provides transport-specific information:
// - **LambdaMCPContext**: Lambda context, API Gateway request, event data
// - **HummingbirdMCPContext**: HTTP request, response, headers, cookies
// - **StdioMCPContext**: Environment variables, process ID, working directory
//
// This enables middleware to access transport-specific data (headers, query params, etc.)
// while remaining type-safe and testable.
//

// MARK: - Envelope Protocol

/// Container protocol for MCP requests with accumulated metadata
///
/// Envelopes wrap MCP requests and provide a mechanism for middleware to attach
/// metadata that flows through to handlers. Each middleware can add its own metadata
/// via the `combine(with:)` method, building up a rich context for request processing.
///
/// ## Purpose
///
/// The Envelope protocol enables:
/// - **Metadata accumulation** across middleware chain
/// - **Type-safe metadata** via generic associated type
/// - **Transport abstraction** - same middleware works across HTTP/Stdio/Lambda
/// - **Immutable updates** - `combine` returns new envelope, original unchanged
///
/// ## Implementation Requirements
///
/// Types conforming to Envelope must:
/// 1. Define a `Metadata` associated type (can be struct, tuple, or dictionary)
/// 2. Implement `combine(with:)` to merge new metadata with existing data
/// 3. Provide a way to access the underlying MCP request
///
/// ## Example Implementation
///
/// ```swift
/// struct AuthMetadata {
///     var userId: String?
///     var role: String?
/// }
///
/// struct RequestEnvelope: Envelope {
///     let mcpRequest: MCPRequest
///     var metadata: AuthMetadata
///
///     func combine(with meta: AuthMetadata) -> RequestEnvelope {
///         var updated = self
///         updated.metadata.userId = meta.userId ?? metadata.userId
///         updated.metadata.role = meta.role ?? metadata.role
///         return updated
///     }
/// }
/// ```
///
/// ## Usage in Middleware
///
/// ```swift
/// func handle(context: Context, envelope: MyEnvelope) async throws -> MiddlewareResponse<AuthMetadata> {
///     // Extract user from context
///     let userId = try await authenticateUser(context)
///
///     // Return metadata to be merged
///     return .accept(metadata: AuthMetadata(userId: userId, role: "admin"))
/// }
/// // Chain automatically calls: envelope = envelope.combine(with: metadata)
/// ```
public protocol Envelope {

    /// The type of metadata this envelope can accumulate
    ///
    /// Common patterns:
    /// - `[String: Any]` - Dynamic dictionary (flexible but untyped)
    /// - Custom struct - Type-safe metadata (recommended)
    /// - Tuple - Multiple related values
    /// - `Void` - No metadata (pass-through only)
    associatedtype Metadata

    /// Merge new metadata into this envelope
    ///
    /// Called by the middleware chain when middleware returns `.accept(metadata:)`.
    /// Implementations should merge the new metadata with existing metadata,
    /// handling conflicts appropriately (last-write-wins, merge deeply, etc.).
    ///
    /// - Parameter meta: New metadata to merge
    /// - Returns: New envelope with merged metadata (immutable update)
    func combine(with meta: Metadata) -> Self

}

// MARK: - Request Timing

/// Timing information for request processing
///
/// Captures the start and end times of a request, allowing middleware to:
/// - Log exact timestamps for correlation with external systems
/// - Calculate request duration
/// - Track request processing time for metrics
///
/// ## Usage in Post-Response Middleware
///
/// ```swift
/// let logger = PostResponseMiddleware.from { context, envelope, response, timing in
///     context.logger.info("Request completed", metadata: [
///         "startTime": "\(timing.startTime)",
///         "endTime": "\(timing.endTime)",
///         "durationMs": timing.duration * 1000
///     ])
///     return .passthrough
/// }
/// ```
public struct RequestTiming {

    /// When the request started processing
    public let startTime: Date

    /// When the request finished processing
    public let endTime: Date

    /// Request processing duration in seconds
    ///
    /// Convenience property that calculates `endTime - startTime`.
    /// For milliseconds, multiply by 1000.
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Create timing information
    ///
    /// - Parameters:
    ///   - startTime: When request processing began
    ///   - endTime: When request processing completed
    public init(startTime: Date, endTime: Date) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - Response Envelope

/// Container combining request envelope with response for post-response middleware
///
/// `ResponseEnvelope` packages both the original request (with accumulated metadata
/// from pre-request middleware), the current response, and timing information together,
/// providing post-response middleware with full context about the request processing.
///
/// ## Purpose
///
/// This enables post-response middleware to:
/// - Access request metadata (user ID, trace ID, etc.) for correlation
/// - Access the request details (method, params) for logging
/// - Access and potentially modify the response
/// - Access timing information (start time, end time, duration)
/// - Make decisions based on request, response, and timing data
///
/// ## Usage in Post-Response Middleware
///
/// ```swift
/// let logger = PostResponseMiddlewareHelpers.from { context, envelope in
///     // Access request context
///     let userId = envelope.request.metadata["userId"]
///     let method = envelope.request.mcpRequest.method
///
///     // Access response (transport-specific type)
///     let statusCode = envelope.response.statusCode
///
///     // Access timing information
///     let durationMs = envelope.timing.duration * 1000
///
///     context.logger.info("Request completed", metadata: [
///         "userId": .string(userId ?? "unknown"),
///         "method": .string(method),
///         "statusCode": .stringConvertible(statusCode),
///         "durationMs": .stringConvertible(durationMs)
///     ])
///     return .passthrough
/// }
/// ```
///
/// ## Generic Response Type
///
/// The envelope is generic over the response type to support different transports:
/// - Lambda: `ResponseEnvelope<APIGatewayResponse>`
/// - Hummingbird: `ResponseEnvelope<Hummingbird.Response>`
/// - Stdio: `ResponseEnvelope<TransportResponse>`
public struct ResponseEnvelope<Response> {

    /// The original request envelope with accumulated metadata
    ///
    /// Contains the MCP request and all metadata added by pre-request middleware.
    /// Use this to access request details and correlate with the response.
    public let request: TransportEnvelope

    /// The current response (potentially modified by previous middleware)
    ///
    /// This is the transport-specific response type:
    /// - Lambda: `APIGatewayResponse` (can modify headers, status, body)
    /// - Hummingbird: `Hummingbird.Response` (can modify headers, status, body)
    /// - Stdio: `TransportResponse` (can modify JSON response data)
    public let response: Response

    /// Request processing timing information
    ///
    /// Contains start time, end time, and computed duration.
    /// Use this for logging, metrics, and performance monitoring.
    public let timing: RequestTiming

    /// Create a response envelope
    ///
    /// - Parameters:
    ///   - request: Original request envelope with metadata
    ///   - response: Transport-specific response
    ///   - timing: Request processing timing information
    public init(request: TransportEnvelope, response: Response, timing: RequestTiming) {
        self.request = request
        self.response = response
        self.timing = timing
    }
}
