import Foundation
import Logging
import JSONValueCoding

// MARK: - MCP Initialization Types

/// Server capabilities advertised during initialization
///
/// Declares which MCP features (tools, resources, prompts) the server supports.
/// Empty dictionaries indicate the feature is supported; nil means not supported.
struct Capabilities: Encodable {
    /// Tools capability - server can execute tools if present
    let tools: [String: String]?

    /// Resources capability - server can serve resources if present
    let resources: [String: String]?

    /// Prompts capability - server can provide prompts if present
    let prompts: [String: String]?
}

/// Server identification information
///
/// Provides name and version information about the MCP server.
struct ServerInfo: Encodable {
    /// Human-readable server name
    let name: String

    /// Server version string (e.g., "1.0.0")
    let version: String
}

/// MCP protocol initialization response
///
/// Sent in response to the `initialize` method call from a client.
/// Advertises server capabilities and protocol version.
struct InitializeResponse: Encodable {
    /// MCP protocol version this server implements
    let protocolVersion: String = "2025-06-18"

    /// Server capabilities (tools, resources, prompts)
    let capabilities: Capabilities

    /// Server identification information
    let serverInfo: ServerInfo
}



// MARK: - JSON-RPC 2.0 Protocol

/// JSON-RPC 2.0 request message
///
/// The MCP protocol is built on JSON-RPC 2.0, which provides a standardized
/// request/response messaging format. All MCP requests follow this structure.
///
/// ## MCP Methods
///
/// Common MCP method names:
/// - `initialize` - Server initialization and capability exchange
/// - `tools/list` - List available tools
/// - `tools/call` - Execute a tool
/// - `resources/list` - List static resources
/// - `resources/templates/list` - List resource templates
/// - `resources/read` - Read resource content
/// - `prompts/list` - List available prompts
/// - `prompts/get` - Get a prompt with arguments
///
/// ## Example
///
/// ```swift
/// let request = Request(
///     id: .string("req-123"),
///     method: "tools/call",
///     params: [
///         "name": .string("read_file"),
///         "arguments": .object(["path": .string("/data.json")])
///     ]
/// )
/// ```
public struct Request: Codable {

    /// JSON-RPC version (always "2.0")
    public let jsonrpc: String = "2.0"

    /// Optional request identifier for matching requests with responses
    public let id: RequestId?

    /// Method name to invoke (e.g., "tools/call", "resources/read")
    public let method: String

    /// Optional method parameters as key-value pairs
    public let params: [String: JSONValue]?
    
    public init(id: RequestId?, method: String, params: [String: JSONValue]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(RequestId.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent([String: JSONValue].self, forKey: .params)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }
    
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
}

/// JSON-RPC 2.0 response message
///
/// Generic response structure that can contain either a successful result or an error.
/// The type parameter allows for strongly-typed results based on the method called.
///
/// ## Response Types
///
/// - Success: Contains `result` field with method-specific data
/// - Error: Contains `error` field with error code and message
///
/// ## Examples
///
/// ```swift
/// // Success response
/// let response = Response(
///     id: .string("req-123"),
///     result: ToolCallResponse(content: [...])
/// )
///
/// // Error response
/// let errorResponse = Response<String>.fromError(
///     id: .string("req-123"),
///     error: MCPError(code: .methodNotFound, message: "Tool not found")
/// )
/// ```
public struct Response<Result: Encodable>: Encodable {

    /// JSON-RPC version (always "2.0")
    public let jsonrpc: String = "2.0"

    /// Request identifier matching the original request
    public let id: RequestId?

    /// Successful result (mutually exclusive with error)
    public let result: Result?

    /// Error information (mutually exclusive with result)
    public let error: MCPError?
    
    public init(id: RequestId?, result: Result?) {
        self.id = id
        self.result = result
        self.error = nil
    }
    
    public init(id: RequestId?, error: MCPError) {
        self.id = id
        self.result = nil
        self.error = error
    }

    /// Create an error response with String result type
    ///
    /// Convenience method for creating error responses when the result type is not known.
    /// Uses String as a placeholder since error responses don't include result data.
    ///
    /// - Parameters:
    ///   - id: Request identifier
    ///   - error: Error information
    /// - Returns: Response with error populated and result nil
    public static func fromError(id: RequestId?, error: MCPError) -> Response<String> {
        Response<String>(id: id, error: error)
    }
                
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(result, forKey: .result)
    }
    
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }
}

/// JSON-RPC 2.0 request identifier
///
/// Request IDs can be either strings or numbers according to the JSON-RPC spec.
/// Used to match responses with their corresponding requests.
///
/// ## Examples
///
/// ```swift
/// let stringId = RequestId.string("req-123")
/// let numberId = RequestId.number(42)
/// ```
public enum RequestId: Codable, Sendable {

    /// String-based request identifier
    case string(String)

    /// Numeric request identifier
    case number(Int)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .number(intValue)
        } else {
            throw DecodingError.typeMismatch(
                RequestId.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Int")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }
}

/// Standard JSON-RPC 2.0 error codes
///
/// Predefined error codes from the JSON-RPC 2.0 specification.
/// Custom application errors should use codes outside the reserved range (-32768 to -32000).
///
/// ## Error Code Meanings
///
/// - **parseError**: Invalid JSON received
/// - **invalidRequest**: JSON is not a valid Request object
/// - **methodNotFound**: Requested method does not exist
/// - **invalidParams**: Invalid method parameters
/// - **internalError**: Internal server error
public enum MCPErrorCode: Int, CaseIterable {
    /// Invalid JSON was received by the server (-32700)
    case parseError = -32700

    /// The JSON sent is not a valid Request object (-32600)
    case invalidRequest = -32600

    /// The method does not exist or is not available (-32601)
    case methodNotFound = -32601

    /// Invalid method parameter(s) (-32602)
    case invalidParams = -32602

    /// Internal JSON-RPC error (-32603)
    case internalError = -32603
}

/// JSON-RPC 2.0 error object
///
/// Represents an error that occurred during request processing.
/// Includes an error code, human-readable message, and optional additional data.
///
/// ## Examples
///
/// ```swift
/// // Using standard error code
/// let error = MCPError(
///     code: .methodNotFound,
///     message: "Tool 'unknown_tool' not found"
/// )
///
/// // With additional data
/// let error = MCPError(
///     code: .invalidParams,
///     message: "Missing required parameter",
///     data: ["parameter": "path"]
/// )
///
/// // Custom error code
/// let error = MCPError(
///     code: 1001,
///     message: "Custom application error"
/// )
/// ```
public struct MCPError: Codable, Error {

    /// Error code (standard JSON-RPC or custom)
    public let code: Int

    /// Human-readable error message
    public let message: String

    /// Optional additional error data
    public let data: JSONValue?
    
    private enum CodingKeys: String, CodingKey {
        case code, message, data
    }
    
    public init(code: Int, message: String, data: [String: Any]? = nil) {
        self.code = code
        self.message = message
        self.data = data.map(JSONValue.init)
    }
    
    public init(code: MCPErrorCode, message: String, data: [String: Any]? = nil) {
        self.init(code: code.rawValue, message: message, data: data)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        data = try container.decodeIfPresent(JSONValue.self, forKey: .data)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(data, forKey: .data)
    }
    
}

// MARK: - Transport Envelope Types

/// Transport-agnostic envelope for MCP requests
///
/// Wraps an MCP request with routing and metadata information, decoupling
/// the protocol layer from transport implementation (HTTP, stdio, Lambda, etc.).
///
/// ## Architecture
///
/// The envelope pattern enables:
/// - **Transport independence**: Same MCP server works with HTTP, stdio, Lambda
/// - **Middleware support**: Metadata can be added/modified by middleware
/// - **Routing**: Path parameters extracted from URLs
/// - **Context preservation**: Headers, authentication, tracing data
///
/// ## Example
///
/// ```swift
/// // Lambda adapter creates envelope from API Gateway request
/// let envelope = TransportEnvelope(
///     mcpRequest: request,
///     routePath: "/mcp/customer-123/files",
///     metadata: [
///         "userId": cognitoUserId,
///         "requestId": lambdaRequestId
///     ]
/// )
///
/// // Router matches path and extracts parameters
/// let response = try await router.route(envelope)
/// ```
public struct TransportEnvelope: Envelope, @unchecked Sendable {

    public typealias Metadata = [String: Any]

    /// The MCP protocol message (decoded from transport body)
    public let mcpRequest: Request

    /// Route path for router pattern matching (e.g., "/files/{customerId}")
    public let routePath: String

    /// Transport-specific metadata (headers, auth, context, etc.)
    ///
    /// Common metadata keys:
    /// - Authentication: "userId", "tenantId", "roles"
    /// - Tracing: "requestId", "traceId", "spanId"
    /// - Transport: "sourceIP", "userAgent", "headers"
    public let metadata: [String: Any]

    /// Path parameters extracted from route pattern matching
    ///
    /// This is `nil` for global adapter middleware (before routing), and populated
    /// after the Router matches a path pattern for route-specific middleware.
    ///
    /// Example:
    /// ```swift
    /// // Route pattern: "/customers/{customerId}/files"
    /// // Request path: "/customers/cust-123/files"
    /// // pathParams.string("customerId") returns "cust-123"
    /// ```
    public var pathParams: Params?

    public init(mcpRequest: Request, routePath: String, metadata: [String: Any] = [:], pathParams: Params? = nil) {
        self.mcpRequest = mcpRequest
        self.routePath = routePath
        self.metadata = metadata
        self.pathParams = pathParams
    }

    /// Merge new metadata into this envelope, creating a new instance
    ///
    /// This method implements the `Envelope` protocol's `combine(with:)` requirement,
    /// enabling middleware to accumulate metadata as requests flow through the chain.
    ///
    /// ## Merge Semantics
    ///
    /// When metadata keys conflict, the **new value wins** (last-write-wins):
    /// ```swift
    /// let envelope1 = TransportEnvelope(
    ///     mcpRequest: request,
    ///     routePath: "/api",
    ///     metadata: ["userId": "user-123", "role": "user"]
    /// )
    ///
    /// let envelope2 = envelope1.combine(with: ["role": "admin", "traceId": "trace-456"])
    ///
    /// // envelope2.metadata:
    /// // {
    /// //   "userId": "user-123",     // kept from original
    /// //   "role": "admin",          // overwritten by new
    /// //   "traceId": "trace-456"    // added from new
    /// // }
    /// ```
    ///
    /// ## Immutability
    ///
    /// This method returns a **new** `TransportEnvelope` with merged metadata. The
    /// original envelope is unchanged:
    /// ```swift
    /// let original = TransportEnvelope(mcpRequest: req, routePath: "/", metadata: ["key": "value1"])
    /// let updated = original.combine(with: ["key": "value2"])
    ///
    /// print(original.metadata["key"])  // "value1" (unchanged)
    /// print(updated.metadata["key"])   // "value2" (new instance)
    /// ```
    ///
    /// ## Usage in Middleware Chain
    ///
    /// The `MiddlewareChain` calls this method automatically when middleware returns
    /// `.accept(metadata)`:
    /// ```swift
    /// // Middleware 1: Add auth
    /// func handle(context: C, envelope: TransportEnvelope) async throws -> MiddlewareResponse<[String: Any]> {
    ///     return .accept(metadata: ["userId": "user-123", "role": "admin"])
    /// }
    /// // Chain calls: envelope = envelope.combine(with: ["userId": "user-123", "role": "admin"])
    ///
    /// // Middleware 2: Add tracing
    /// func handle(context: C, envelope: TransportEnvelope) async throws -> MiddlewareResponse<[String: Any]> {
    ///     return .accept(metadata: ["traceId": UUID().uuidString])
    /// }
    /// // Chain calls: envelope = envelope.combine(with: ["traceId": "..."])
    ///
    /// // Final envelope.metadata contains:
    /// // ["userId": "user-123", "role": "admin", "traceId": "..."]
    /// ```
    ///
    /// ## Empty Metadata
    ///
    /// Combining with empty metadata is a no-op (but still creates a new instance):
    /// ```swift
    /// let envelope1 = TransportEnvelope(mcpRequest: req, routePath: "/", metadata: ["key": "value"])
    /// let envelope2 = envelope1.combine(with: [:])
    /// // envelope2.metadata == envelope1.metadata
    /// ```
    ///
    /// ## Common Metadata Keys
    ///
    /// By convention, middleware adds these metadata keys:
    /// - **Authentication**: `"userId"`, `"tenantId"`, `"sessionId"`, `"roles"`
    /// - **Authorization**: `"permissions"`, `"scopes"`, `"groups"`
    /// - **Tracing**: `"requestId"`, `"traceId"`, `"spanId"`, `"parentSpanId"`
    /// - **Transport**: `"sourceIP"`, `"userAgent"`, `"referrer"`, `"method"`
    /// - **Timing**: `"requestStartTime"`, `"middlewareDuration"`
    ///
    /// ## Type Safety Note
    ///
    /// `TransportEnvelope` uses `[String: Any]` for maximum flexibility across transports.
    /// For type-safe metadata, consider defining custom envelope types with structured
    /// metadata:
    /// ```swift
    /// struct AuthMetadata {
    ///     var userId: String?
    ///     var role: String?
    /// }
    ///
    /// struct TypedEnvelope: Envelope {
    ///     typealias Metadata = AuthMetadata
    ///     let mcpRequest: Request
    ///     var metadata: AuthMetadata
    ///
    ///     func combine(with meta: AuthMetadata) -> TypedEnvelope {
    ///         var updated = self
    ///         updated.metadata.userId = meta.userId ?? metadata.userId
    ///         updated.metadata.role = meta.role ?? metadata.role
    ///         return updated
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter meta: New metadata to merge (last-write-wins on conflicts)
    /// - Returns: New `TransportEnvelope` with merged metadata
    public func combine(with meta: [String: Any]) -> TransportEnvelope {
        var baseMetadata = self.metadata
        baseMetadata.merge(meta) { (_, new) in new }
        return .init(mcpRequest: mcpRequest, routePath: routePath, metadata: baseMetadata, pathParams: pathParams)
    }
}

/// Transport response envelope
///
/// Wraps an MCP response with transport-specific metadata, maintaining
/// transport independence similar to TransportEnvelope.
///
/// ## Example
///
/// ```swift
/// // Server processes request and returns response
/// let responseData = try await server.handleRequest(envelope)
///
/// // Wrap in transport response
/// let response = TransportResponse(
///     data: responseData,
///     metadata: ["statusCode": 200]
/// )
///
/// // Lambda adapter converts to API Gateway response
/// return APIGatewayResponse(
///     statusCode: .ok,
///     body: response.data.base64EncodedString()
/// )
/// ```
public struct TransportResponse {
    /// Serialized MCP response data (JSON-RPC 2.0 formatted)
    public let data: JSONValue

    public init(data: JSONValue) {
        self.data = data
    }
}

/// MCP request context shared across all handler types
///
/// Provides core request information that is available to all MCP handlers (tools, resources, prompts).
/// This context is created once per request and passed through the entire request lifecycle.
///
/// ## Properties
///
/// - **requestId**: Unique identifier for the MCP request (JSON-RPC 2.0 request ID)
/// - **method**: MCP method being invoked (e.g., "tools/call", "resources/read", "prompts/get")
/// - **logger**: Request-scoped logger instance for this specific request
/// - **metadata**: Transport-specific metadata from the envelope (auth, headers, tracing, etc.)
///
/// ## Usage in Handlers
///
/// All handler types receive MCPContext through their request objects:
///
/// ```swift
/// // Tool handler
/// server.addTool("process_data", inputType: DataInput.self) { request in
///     request.context.logger.info("Processing tool request")
///     let userId = request.context.metadata["userId"] as? String
///     // ...
/// }
///
/// // Resource handler
/// server.addResource("file://{path}", ...) { request in
///     request.context.logger.info("Reading resource")
///     let traceId = request.context.metadata["traceId"] as? String
///     // ...
/// }
///
/// // Prompt handler
/// server.addPrompt("review", ...) { request in
///     request.context.logger.info("Generating prompt")
///     let tenantId = request.context.metadata["tenantId"] as? String
///     // ...
/// }
/// ```
///
/// ## Metadata Keys
///
/// The metadata dictionary contains transport-specific information passed from the adapter.
/// Common metadata keys include:
///
/// ### Authentication & Authorization
/// - `userId` (String) - Authenticated user identifier
/// - `tenantId` (String) - Multi-tenant organization identifier
/// - `roles` ([String]) - User roles/permissions
///
/// ### Distributed Tracing
/// - `requestId` (String) - Transport-level request ID (may differ from MCP requestId)
/// - `traceId` (String) - Distributed trace identifier
/// - `spanId` (String) - Trace span identifier
///
/// ### HTTP Transport (Lambda/Hummingbird)
/// - `sourceIP` (String) - Client IP address
/// - `userAgent` (String) - HTTP User-Agent header
/// - `headers` ([String: String]) - All HTTP headers
///
/// ### Lambda-specific
/// - `requestContext` ([String: Any]) - API Gateway request context
/// - `stageVariables` ([String: String]) - Lambda stage variables
///
/// ## Request ID
///
/// The `requestId` field contains the JSON-RPC 2.0 request identifier from the MCP protocol.
/// This can be either a string or number, and is used for correlating requests with responses:
///
/// ```swift
/// switch context.requestId {
/// case .string(let id):
///     logger.info("Processing request: \(id)")
/// case .number(let id):
///     logger.info("Processing request: \(id)")
/// }
/// ```
///
/// ## Thread Safety
///
/// MCPContext is a struct and is passed by value, making it inherently thread-safe.
/// The metadata dictionary is immutable once created.
/// `@unchecked Sendable` because `metadata: [String: Any]` can technically
/// hold non-Sendable values, but the struct itself is immutable
/// (`let` everywhere) and the documented use is for Sendable-friendly
/// values like userId / tenantId / traceId / sourceIP. Adopters who put
/// non-Sendable things into metadata get undefined behavior across actors —
/// which they were already opting into the moment they typed `Any`.
public struct MCPContext: @unchecked Sendable {

    /// JSON-RPC 2.0 request identifier
    ///
    /// Used to correlate MCP requests with responses. Can be either a string or number
    /// as specified by the JSON-RPC 2.0 protocol.
    public let requestId: RequestId

    /// MCP method being invoked
    ///
    /// Examples: "tools/call", "tools/list", "resources/read", "resources/list",
    /// "resources/templates/list", "prompts/get", "prompts/list", "initialize"
    public let method: String

    /// Request-scoped logger instance
    ///
    /// Pre-configured with request metadata (requestId, method) for correlation.
    /// Use this logger instead of creating your own to ensure consistent logging.
    public let logger: Logger

    /// Transport-specific metadata
    ///
    /// Contains information from the transport layer (HTTP headers, authentication,
    /// tracing context, etc.). The exact keys depend on the adapter being used
    /// (Lambda, Hummingbird, Stdio).
    ///
    /// Common keys: userId, tenantId, roles, traceId, sourceIP, headers.
    /// Stored as `[String: Any]` for backwards compatibility — see the
    /// `@unchecked Sendable` note on the type.
    public let metadata: [String: Any]

    public init(requestId: RequestId, method: String, logger: Logger, metadata: [String: Any]) {
        self.requestId = requestId
        self.method = method
        self.logger = logger
        self.metadata = metadata
    }
}


