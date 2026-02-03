import Foundation
import MCP
import LambdaApp
import AWSLambdaEvents
import HTTPTypes
import Logging

// MARK: - Lambda Context for Middleware

/// Lambda-specific context for middleware
///
/// Provides middleware with access to both the Lambda execution context and
/// the API Gateway request that triggered the invocation. This enables middleware
/// to make decisions based on Lambda metadata, API Gateway headers, or request properties.
///
/// ## Available Information
///
/// - **Lambda context**: Request ID, remaining time, function ARN, memory limit
/// - **API Gateway request**: HTTP headers, path, query parameters, stage variables
/// - **Cognito auth**: User identity from API Gateway authorizer (if configured)
///
/// ## Example Usage
///
/// ```swift
/// struct AuthMiddleware: Middleware {
///     typealias Context = LambdaMCPContext
///
///     func handle(context: Context, envelope: TransportEnvelope) async throws -> MiddlewareResponse {
///         // Access Lambda request ID for tracing
///         let requestId = context.lambdaContext.requestId
///
///         // Extract auth token from API Gateway headers
///         guard let token = context.apiGatewayRequest.headers["Authorization"] else {
///             return .reject(MCPError(code: .invalidRequest, message: "Missing auth"))
///         }
///
///         // Access Cognito user identity
///         if let userId = context.apiGatewayRequest.requestContext.authorizer?.claims?["sub"] {
///             return .accept(metadata: ["userId": userId, "requestId": requestId])
///         }
///
///         return .passthrough
///     }
/// }
/// ```
public struct LambdaMCPContext {

    /// Lambda execution context with request ID, logger, and metadata
    public let lambdaContext: LambdaContext

    /// API Gateway request with headers, path, and query parameters
    public let apiGatewayRequest: APIGatewayRequest

    public init(lambdaContext: LambdaContext, apiGatewayRequest: APIGatewayRequest) {
        self.lambdaContext = lambdaContext
        self.apiGatewayRequest = apiGatewayRequest
    }
}

// MARK: - MCP to LambdaApp Bridge

/// Bridges MCP servers/routers to AWS Lambda via API Gateway
///
/// LambdaAdapter connects the MCP protocol layer to AWS Lambda's execution environment,
/// handling the translation between API Gateway requests/responses and MCP messages.
/// It provides middleware support for authentication, logging, tracing, and other
/// cross-cutting concerns.
///
/// ## Architecture
///
/// ```
/// API Gateway → Lambda → LambdaAdapter → Middleware Chain → MCP Router → Server → Handler
/// ```
///
/// The adapter:
/// 1. Parses API Gateway request body as JSON-RPC 2.0 MCP request
/// 2. Builds TransportEnvelope with route path and metadata
/// 3. Executes middleware chain (auth, logging, etc.)
/// 4. Routes to appropriate MCP server
/// 5. Converts MCP response to API Gateway response with CORS headers
///
/// ## Basic Usage (No Middleware)
///
/// ```swift
/// // Create MCP server
/// let server = Server()
///     .addTool("read_file", inputType: FileArgs.self) { request in
///         // Tool implementation
///         return .text("File contents")
///     }
///
/// // Create adapter and bridge to Lambda
/// let adapter = LambdaAdapter()
/// let app = LambdaApp()
///     .addAPIGateway(key: "mcp", handler: adapter.bridge(server))
///
/// app.run(handlerKey: "mcp")
/// ```
///
/// ## Advanced Usage (With Middleware)
///
/// ```swift
/// // Create authentication middleware
/// let authMiddleware = MiddlewareHelpers.from { (context: LambdaMCPContext, envelope) in
///     guard let token = context.apiGatewayRequest.headers["Authorization"] else {
///         return .reject(MCPError(code: .invalidRequest, message: "Unauthorized"))
///     }
///     let userId = try await verifyToken(token)
///     return .accept(metadata: ["userId": userId])
/// }
///
/// // Create logging middleware
/// let loggingMiddleware = MiddlewareHelpers.from { (context: LambdaMCPContext, envelope) in
///     context.lambdaContext.logger.info("MCP \(envelope.mcpRequest.method)")
///     return .passthrough
/// }
///
/// // Build adapter with middleware chain
/// let adapter = LambdaAdapter()
///     .addMiddleware(authMiddleware)
///     .addMiddleware(loggingMiddleware)
///
/// // Create router with multiple servers
/// let router = Router()
///     .addServer(path: "/mcp/{customerId}/files", server: fileServer)
///     .addServer(path: "/mcp/{customerId}/db", server: dbServer)
///
/// // Bridge to Lambda
/// let app = LambdaApp()
///     .addAPIGateway(key: "mcp", handler: adapter.bridge(router))
/// ```
///
/// ## Metadata Flow
///
/// Middleware adds metadata to the envelope:
/// ```swift
/// // Middleware adds userId
/// return .accept(metadata: ["userId": "user-123"])
///
/// // Available in tool handlers via context.metadata
/// server.addTool("get_data") { request in
///     let userId = request.context.metadata["userId"] as? String
///     // Use userId to filter data
/// }
/// ```
///
/// ## CORS Support
///
/// The adapter automatically adds CORS headers to all responses:
/// - `Access-Control-Allow-Origin: *`
/// - `Access-Control-Allow-Methods: POST, OPTIONS`
/// - `Access-Control-Allow-Headers: Content-Type`
public class LambdaAdapter {

    private let preRequestMiddlewareChain = PreRequestMiddlewareChain<TransportEnvelope, LambdaMCPContext>()
    private let postResponseMiddlewareChain = PostResponseMiddlewareChain<AWSLambdaEvents.APIGatewayResponse, LambdaMCPContext>()
    private let jsonEncoder = JSONEncoder()

    public init() {
        jsonEncoder.outputFormatting = .sortedKeys
    }

    /// Add pre-request middleware to the execution chain
    ///
    /// Middleware executes in the order added, before the MCP server processes requests.
    /// Each middleware can inspect/modify the request or reject it with an error.
    ///
    /// - Parameter middleware: Middleware to add (must use LambdaMCPContext)
    /// - Returns: Self for method chaining
    @discardableResult public func usePrequestMiddleware<M: PreRequestMiddleware>(_ middleware: M) -> LambdaAdapter where M.Context == LambdaMCPContext, M.MiddlewareEnvelope == TransportEnvelope {
        preRequestMiddlewareChain.use(middleware.eraseToAnyPreRequestMiddleware())
        return self
    }

    /// Add post-response middleware to the execution chain
    ///
    /// Middleware executes in the order added, after the MCP server generates a response
    /// but before it's sent to the client. Each middleware can observe/transform the response.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let adapter = LambdaAdapter()
    ///     .usePostResponseMiddleware(PostResponseMiddlewareHelpers.from {
    ///         (context: LambdaMCPContext, envelope: TransportEnvelope,
    ///          response: APIGatewayResponse, timing: RequestTiming) in
    ///
    ///         var modified = response
    ///         modified.headers["X-Request-ID"] = context.lambdaContext.requestID
    ///         modified.headers["X-Duration-Ms"] = "\(timing.duration * 1000)"
    ///         return .accept(modified)
    ///     })
    /// ```
    ///
    /// - Parameter middleware: Post-response middleware to add
    /// - Returns: Self for method chaining
    @discardableResult public func usePostResponseMiddleware<M: PostResponseMiddleware>(_ middleware: M) -> LambdaAdapter
    where M.Context == LambdaMCPContext,
          M.Response == AWSLambdaEvents.APIGatewayResponse {
        postResponseMiddlewareChain.use(middleware.eraseToAnyPostResponseMiddleware())
        return self
    }
    
    /// Bridge MCP Router to Lambda API Gateway handler
    ///
    /// Creates a Lambda handler function that:
    /// 1. Parses the API Gateway request body as MCP JSON-RPC request
    /// 2. Runs global adapter middleware (Params not yet available)
    /// 3. Routes through router which:
    ///    - Matches path pattern and extracts Params
    ///    - Runs route-specific middleware (Params available)
    ///    - Invokes MCP server handler
    /// 4. Converts MCP response to API Gateway format with CORS headers
    ///
    /// The returned handler is compatible with `LambdaApp.addAPIGateway()`.
    ///
    /// - Parameter router: MCP router with one or more servers
    /// - Returns: Async Lambda handler function
    public func bridge(_ router: LambdaRouter) -> (LambdaContext, AWSLambdaEvents.APIGatewayRequest) async throws -> AWSLambdaEvents.APIGatewayResponse {
        return bridge(router, pathOverride: nil)
    }

    /// Bridge MCP Router to Lambda API Gateway handler with optional path override
    ///
    /// When `pathOverride` is provided, uses that path for MCP routing instead of
    /// the API Gateway request path. This enables mounting MCP under a prefix
    /// via APIGatewayRouter.
    ///
    /// - Parameters:
    ///   - router: MCP router with one or more servers
    ///   - pathOverride: Path to use for routing (nil = use request.path)
    /// - Returns: Async Lambda handler function
    public func bridge(_ router: LambdaRouter, pathOverride: String?) -> (LambdaContext, AWSLambdaEvents.APIGatewayRequest) async throws -> AWSLambdaEvents.APIGatewayResponse {
        return { [self] lambdaContext, apiGwRequest in
            let routePath = pathOverride ?? apiGwRequest.path

            // Log API Gateway request details at debug level
            lambdaContext.logger.debug("Received API Gateway request", metadata: [
                "path": .string(apiGwRequest.path),
                "routePath": .string(routePath),
                "httpMethod": .string(apiGwRequest.httpMethod.rawValue),
                "isBase64Encoded": .stringConvertible(apiGwRequest.isBase64Encoded)
            ])
            
            // Capture start time for post-response middleware
            let startTime = Date()

            // Parse MCP request from API Gateway body
            guard let body = apiGwRequest.body else {
                throw MCPError(code: .invalidRequest, message: "Missing request body")
            }
            
            // Decode body based on encoding type
            let bodyData: Data
            if apiGwRequest.isBase64Encoded {
                guard let decoded = Data(base64Encoded: body) else {
                    throw MCPError(code: .invalidRequest, message: "Failed to decode base64 request body")
                }
                bodyData = decoded
            } else {
                guard let utf8Data = body.data(using: .utf8) else {
                    throw MCPError(code: .invalidRequest, message: "Failed to decode UTF-8 request body")
                }
                bodyData = utf8Data
            }

            let mcpRequest = try JSONDecoder().decode(Request.self, from: bodyData)

            // Build transport envelope (Params nil for global middleware)
            var envelope = TransportEnvelope(
                mcpRequest: mcpRequest,
                routePath: routePath
            )

            // Build Lambda context for middleware
            let mcpContext = LambdaMCPContext(
                lambdaContext: lambdaContext,
                apiGatewayRequest: apiGwRequest
            )

            // Run global pre-request middleware chain (before routing)
            let middlewareResult = try await self.preRequestMiddlewareChain.execute(
                context: mcpContext,
                envelope: envelope
            )

            // Handle global middleware rejection
            switch middlewareResult {
            case .reject(let error):
                // Global middleware rejected - return error immediately
                let errorResponse = Response<String>.fromError(
                    id: mcpRequest.id,
                    error: error
                )
                let errorData = try JSONEncoder().encode(errorResponse)
                let errorBody = errorData.base64EncodedString()
                return AWSLambdaEvents.APIGatewayResponse(
                    statusCode: .ok,
                    headers: [
                        "Content-Type": "application/json",
                        "Access-Control-Allow-Origin": "*"
                    ],
                    body: errorBody,
                    isBase64Encoded: true
                )

            case .accept(let updatedEnvelope), .passthrough(let updatedEnvelope):
                envelope = updatedEnvelope
            }

            // Route through MCP router (runs route middleware with Params)
            let response = try await router.route(
                envelope,
                context: mcpContext,
                logger: lambdaContext.logger
            )

            // Convert to API Gateway response with base64 encoding
            let responseAsRawData = try jsonEncoder.encode(response.data)
            let responseBody = responseAsRawData.base64EncodedString()

            var apiGatewayResponse = AWSLambdaEvents.APIGatewayResponse(
                statusCode: .ok,
                headers: [
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "POST, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type"
                ],
                body: responseBody,
                isBase64Encoded: true
            )

            // Run post-response middleware chain
            let endTime = Date()
            let timing = RequestTiming(startTime: startTime, endTime: endTime)

            let responseEnvelope = ResponseEnvelope(
                request: envelope,
                response: apiGatewayResponse,
                timing: timing
            )

            apiGatewayResponse = try await self.postResponseMiddlewareChain.execute(
                context: mcpContext,
                envelope: responseEnvelope
            )

            return apiGatewayResponse
        }
    }

    /// Bridge MCP Server to Lambda API Gateway handler
    ///
    /// Convenience method for single-server deployments. Automatically creates
    /// a router with the server at the root path ("/").
    ///
    /// Equivalent to:
    /// ```swift
    /// let router = LambdaRouter().addServer(server: server)
    /// adapter.bridge(router)
    /// ```
    ///
    /// - Parameter server: MCP server to bridge
    /// - Returns: Async Lambda handler function
    public func bridge(_ server: Server) -> (LambdaContext, AWSLambdaEvents.APIGatewayRequest) async throws -> AWSLambdaEvents.APIGatewayResponse {
        // Create a simple root path for single server
        let router = LambdaRouter().addServer(server: server)
        return bridge(router)
    }

}

// MARK: - Simple Bridge (No Middleware)

/// Convenience bridge for MCP servers without middleware
///
/// Provides static methods to quickly bridge MCP servers/routers to Lambda
/// without setting up middleware. Use this for simple deployments where you
/// don't need authentication, logging, or other middleware features.
///
/// ## When to Use
///
/// - **Development/testing**: Quick prototyping without auth
/// - **Internal tools**: Lambda behind VPC, no public access
/// - **Simple APIs**: No authentication or logging requirements
///
/// ## When to Use LambdaAdapter Instead
///
/// - **Production APIs**: Need authentication, rate limiting, etc.
/// - **Multi-tenant**: Need to inject customer/tenant context
/// - **Observability**: Need request logging, tracing, metrics
///
/// ## Example
///
/// ```swift
/// // Quick setup without middleware
/// let app = LambdaApp()
///     .addMCP(key: "mcp", server: myServer)  // Uses MCPLambdaSimpleBridge
///
/// // vs. Full setup with middleware
/// let adapter = LambdaAdapter()
///     .addMiddleware(authMiddleware)
///     .addMiddleware(loggingMiddleware)
///
/// let app = LambdaApp()
///     .addAPIGateway(key: "mcp", handler: adapter.bridge(myServer))
/// ```
public class MCPLambdaSimpleBridge {

    public init() {}

    /// Bridge MCP Router to Lambda without middleware
    ///
    /// Creates a Lambda handler with no middleware chain.
    ///
    /// - Parameter router: MCP router to bridge
    /// - Returns: Async Lambda handler function
    public static func bridge(_ router: LambdaRouter) -> (LambdaContext, AWSLambdaEvents.APIGatewayRequest) async throws -> AWSLambdaEvents.APIGatewayResponse {
        let bridge = LambdaAdapter()
        return bridge.bridge(router)
    }

    /// Bridge MCP Server to Lambda without middleware
    ///
    /// Creates a Lambda handler with no middleware chain.
    ///
    /// - Parameter server: MCP server to bridge
    /// - Returns: Async Lambda handler function
    public static func bridge(_ server: Server) -> (LambdaContext, AWSLambdaEvents.APIGatewayRequest) async throws -> AWSLambdaEvents.APIGatewayResponse {
        let bridge = LambdaAdapter()
        return bridge.bridge(server)
    }
}

// MARK: - LambdaApp Extensions

/// Convenience extensions for adding MCP servers to LambdaApp
///
/// These extensions provide fluent methods to integrate MCP servers/routers
/// with LambdaApp's multi-handler routing system.
public extension LambdaApp {

    /// Add MCP Server with middleware adapter
    ///
    /// Registers an MCP server as a Lambda API Gateway handler with middleware support.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let adapter = LambdaAdapter()
    ///     .addMiddleware(authMiddleware)
    ///
    /// let app = LambdaApp()
    ///     .addMCP(key: "mcp", adapter: adapter, server: myServer)
    ///     .addSQS(key: "queue", handler: queueHandler)
    ///
    /// app.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
    /// ```
    ///
    /// - Parameters:
    ///   - key: Handler key for routing (matches MY_HANDLER env var)
    ///   - adapter: LambdaAdapter with configured middleware
    ///   - server: MCP server to register
    func addMCP(key: String, adapter: LambdaAdapter, server: Server) {
        addAPIGateway(key: key, handler: adapter.bridge(server))
    }

    /// Add MCP Router with middleware adapter
    ///
    /// Registers an MCP router as a Lambda API Gateway handler with middleware support.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let router = LambdaRouter()
    ///     .addServer(path: "/mcp/{customerId}/files", server: fileServer)
    ///     .addServer(path: "/mcp/{customerId}/db", server: dbServer)
    ///
    /// let adapter = LambdaAdapter()
    ///     .addMiddleware(authMiddleware)
    ///
    /// let app = LambdaApp()
    ///     .addMCP(key: "mcp", adapter: adapter, router: router)
    /// ```
    ///
    /// - Parameters:
    ///   - key: Handler key for routing
    ///   - adapter: LambdaAdapter with configured middleware
    ///   - router: MCP router with multiple servers
    func addMCP(key: String, adapter: LambdaAdapter, router: LambdaRouter) {
        addAPIGateway(key: key, handler: adapter.bridge(router))
    }

    /// Add MCP Router without middleware
    ///
    /// Quick registration of an MCP router without middleware support.
    /// Uses `MCPLambdaSimpleBridge` internally.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let app = LambdaApp()
    ///     .addMCP(key: "mcp", router: myRouter)
    ///
    /// app.run(handlerKey: "mcp")
    /// ```
    ///
    /// - Parameters:
    ///   - key: Handler key for LambdaApp routing
    ///   - router: MCP router to bridge
    /// - Returns: Self for method chaining
    @discardableResult
    func addMCP(key: String, router: LambdaRouter) -> LambdaApp {
        return addAPIGateway(key: key, handler: MCPLambdaSimpleBridge.bridge(router))
    }

    /// Add MCP Server without middleware
    ///
    /// Quick registration of an MCP server without middleware support.
    /// Uses `MCPLambdaSimpleBridge` internally.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let app = LambdaApp()
    ///     .addMCP(key: "mcp", server: myServer)
    ///
    /// app.run(handlerKey: "mcp")
    /// ```
    ///
    /// - Parameters:
    ///   - key: Handler key for LambdaApp routing
    ///   - server: MCP server to bridge
    /// - Returns: Self for method chaining
    @discardableResult
    func addMCP(key: String, server: Server) -> LambdaApp {
        return addAPIGateway(key: key, handler: MCPLambdaSimpleBridge.bridge(server))
    }
}

// MARK: - Convenience Builder Extensions

/// Lambda integration helpers for MCP Router
///
/// Provides convenient methods to convert Lambda routers to Lambda handlers
/// without explicitly creating a LambdaAdapter.
public extension Router where Context == LambdaMCPContext {

    /// Convert router to Lambda handler without middleware
    ///
    /// Convenience method for direct Lambda integration. Returns a handler
    /// function compatible with `LambdaApp.addAPIGateway()`.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let router = LambdaRouter()
    ///     .addServer(path: "/files", server: fileServer)
    ///
    /// let app = LambdaApp()
    ///     .addAPIGateway(key: "mcp", handler: router.buildForLambda())
    ///
    /// app.run(handlerKey: "mcp")
    /// ```
    ///
    /// - Returns: Async Lambda API Gateway handler function
    func buildForLambda() -> (LambdaContext, AWSLambdaEvents.APIGatewayRequest) async throws -> AWSLambdaEvents.APIGatewayResponse {
        return MCPLambdaSimpleBridge.bridge(self)
    }
}

/// Lambda integration helpers for MCP Server
///
/// Provides convenient methods to convert servers to Lambda handlers
/// without explicitly creating a LambdaAdapter or Router.
public extension Server {

    /// Convert server to Lambda handler without middleware
    ///
    /// Convenience method for direct Lambda integration. Automatically creates
    /// a router with the server at the root path.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let server = Server()
    ///     .addTool("read_file", inputType: FileArgs.self) { request in
    ///         return .text("File contents")
    ///     }
    ///
    /// let app = LambdaApp()
    ///     .addAPIGateway(key: "mcp", handler: server.buildForLambda())
    ///
    /// app.run(handlerKey: "mcp")
    /// ```
    ///
    /// - Returns: Async Lambda API Gateway handler function
    func buildForLambda() -> (LambdaContext, AWSLambdaEvents.APIGatewayRequest) async throws -> AWSLambdaEvents.APIGatewayResponse {
        return MCPLambdaSimpleBridge.bridge(self)
    }
}

// MARK: - Type Alias

/// Router for AWS Lambda with LambdaMCPContext
///
/// Use this type alias when building MCP routers for AWS Lambda deployments.
///
/// Example:
/// ```swift
/// let router = LambdaRouter()
///     .addServer(path: "/customers/{id}/files", server: fileServer) { route in
///         route.usePreRequestMiddleware(authMiddleware)
///     }
/// ```
public typealias LambdaRouter = Router<LambdaMCPContext>

// MARK: - APIGatewayRouter MCP Integration

/// Extension to mount MCP servers/routers within an APIGatewayRouter
///
/// This enables mixing standard HTTP handlers with MCP servers under different
/// path prefixes within a single Lambda function.
///
/// ## Path Rewriting
///
/// When MCP is mounted at a prefix, the prefix is stripped before routing:
///
/// ```
/// Mount: "/mcp"
/// Request: "/mcp/tenant/files"
/// MCP Router sees: "/tenant/files"
/// ```
///
/// ## Example
///
/// ```swift
/// let mcpRouter = LambdaRouter()
///     .addServer(path: "/{tenant}/files", server: fileServer)
///
/// let apiRouter = APIGatewayRouter()
///     .mount("/health") { ctx, req, path in
///         return APIGatewayResponse(statusCode: .ok, body: "OK")
///     }
///     .mountMCP("/mcp", adapter: LambdaAdapter(), router: mcpRouter)
///
/// let app = LambdaApp()
///     .addAPIGateway(key: "api", router: apiRouter)
/// ```
public extension APIGatewayRouter {

    /// Mount an MCP router at the root with middleware support
    ///
    /// Use this when MCP handles all requests for this Lambda.
    ///
    /// - Parameters:
    ///   - adapter: LambdaAdapter with configured middleware
    ///   - router: MCP router with servers
    /// - Returns: Self for method chaining
    @discardableResult
    func mountMCP(
        adapter: LambdaAdapter,
        router: LambdaRouter
    ) -> APIGatewayRouter {
        return mountMCP("/", adapter: adapter, router: router)
    }

    /// Mount an MCP router at the root without middleware
    ///
    /// Use this when MCP handles all requests for this Lambda.
    ///
    /// - Parameter router: MCP router with servers
    /// - Returns: Self for method chaining
    @discardableResult
    func mountMCP(
        router: LambdaRouter
    ) -> APIGatewayRouter {
        return mountMCP("/", router: router)
    }

    /// Mount an MCP server at the root with middleware support
    ///
    /// Use this for single-server deployments where MCP handles all requests.
    ///
    /// - Parameters:
    ///   - adapter: LambdaAdapter with configured middleware
    ///   - server: MCP server to mount
    /// - Returns: Self for method chaining
    @discardableResult
    func mountMCP(
        adapter: LambdaAdapter,
        server: Server
    ) -> APIGatewayRouter {
        return mountMCP("/", adapter: adapter, server: server)
    }

    /// Mount an MCP server at the root without middleware
    ///
    /// Use this for simple single-server deployments.
    ///
    /// - Parameter server: MCP server to mount
    /// - Returns: Self for method chaining
    @discardableResult
    func mountMCP(
        server: Server
    ) -> APIGatewayRouter {
        return mountMCP("/", server: server)
    }

    /// Mount an MCP router at a path prefix with middleware support
    ///
    /// The MCP router receives requests with the prefix stripped, allowing
    /// MCP servers to be mounted at any path without knowing their mount point.
    ///
    /// - Parameters:
    ///   - prefix: Path prefix for MCP routes (e.g., "/mcp")
    ///   - adapter: LambdaAdapter with configured middleware
    ///   - router: MCP router with servers
    /// - Returns: Self for method chaining
    @discardableResult
    func mountMCP(
        _ prefix: String,
        adapter: LambdaAdapter,
        router: LambdaRouter
    ) -> APIGatewayRouter {
        return mount(prefix, handler: { lambdaContext, apiGwRequest, strippedPath in
            let mcpHandler = adapter.bridge(router, pathOverride: strippedPath)
            return try await mcpHandler(lambdaContext, apiGwRequest)
        })
    }

    /// Mount an MCP router at a path prefix without middleware
    ///
    /// Convenience method for simple MCP deployments without authentication
    /// or other middleware requirements.
    ///
    /// - Parameters:
    ///   - prefix: Path prefix for MCP routes
    ///   - router: MCP router with servers
    /// - Returns: Self for method chaining
    @discardableResult
    func mountMCP(
        _ prefix: String,
        router: LambdaRouter
    ) -> APIGatewayRouter {
        return mountMCP(prefix, adapter: LambdaAdapter(), router: router)
    }

    /// Mount an MCP server at a path prefix with middleware support
    ///
    /// Convenience method for mounting a single MCP server.
    ///
    /// - Parameters:
    ///   - prefix: Path prefix for MCP routes
    ///   - adapter: LambdaAdapter with configured middleware
    ///   - server: MCP server to mount
    /// - Returns: Self for method chaining
    @discardableResult
    func mountMCP(
        _ prefix: String,
        adapter: LambdaAdapter,
        server: Server
    ) -> APIGatewayRouter {
        let router = LambdaRouter().addServer(server: server)
        return mountMCP(prefix, adapter: adapter, router: router)
    }

    /// Mount an MCP server at a path prefix without middleware
    ///
    /// Convenience method for simple single-server MCP deployments.
    ///
    /// - Parameters:
    ///   - prefix: Path prefix for MCP routes
    ///   - server: MCP server to mount
    /// - Returns: Self for method chaining
    @discardableResult
    func mountMCP(
        _ prefix: String,
        server: Server
    ) -> APIGatewayRouter {
        return mountMCP(prefix, adapter: LambdaAdapter(), router: LambdaRouter().addServer(server: server))
    }
}
