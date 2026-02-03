import Foundation
import Logging
import JSONValueCoding

// MARK: - MCP Router

/// Routes MCP requests to different servers based on path pattern matching
///
/// `Router` enables multiple MCP servers to handle different URL paths within
/// a single Lambda function. Each server can be specialized for different domains
/// (files, database, AI, etc.) while sharing the same infrastructure.
///
/// ## Route Matching Order
///
/// **IMPORTANT**: Routes are matched in **registration order** (first match wins).
/// Once a path matches a route pattern, that server handles the request.
///
/// ```swift
/// let router = Router<LambdaMCPContext>()
///
/// // ✅ Good: Specific routes before wildcards
/// router.addServer(path: "/users/admin", server: adminServer)    // Matches first
/// router.addServer(path: "/users/{id}", server: userServer)      // Matches other /users/*
///
/// // ❌ Bad: Wildcard before specific routes
/// router.addServer(path: "/users/{id}", server: userServer)      // Matches ALL /users/*
/// router.addServer(path: "/users/admin", server: adminServer)    // Never reached!
/// ```
///
/// ## Path Pattern Syntax
///
/// Routes use `PathPattern` syntax:
/// - **Literal segments**: Match exactly (e.g., `/users`, `/api/v1`)
/// - **Parameters**: `{paramName}` matches any segment value
/// - **Case-sensitive**: `/Users` does not match `/users`
/// - **Exact match**: Path must match all segments (no partial matches)
///
/// ## Multi-Tenant Routing
///
/// Extract tenant/customer IDs from path for isolation:
///
/// ```swift
/// router.addServer(path: "/{tenantId}/files", server: fileServer) { route in
///     route.usePreRequestMiddleware(authMiddleware)
/// }
///
/// // In middleware or server handler:
/// let tenantId = envelope.pathParams?.string("tenantId")
/// ```
///
/// ## Generic Context Support
///
/// Generic over `Context` type to support different transports (Lambda, Hummingbird, Stdio)
/// while maintaining type safety for route-specific middleware.
///
/// ## Complete Example
///
/// ```swift
/// let router = LambdaRouter()
///     // Specific admin route (matched first)
///     .addServer(path: "/admin/tools", server: adminServer) { route in
///         route.usePreRequestMiddleware(adminAuthMiddleware)
///     }
///     // Customer-specific routes with tenant isolation
///     .addServer(path: "/{customerId}/files", server: fileServer) { route in
///         route.usePreRequestMiddleware(authMiddleware)
///         route.usePreRequestMiddleware(tenantCheckMiddleware)
///     }
///     // Public routes (no middleware)
///     .addServer(path: "/public/health", server: healthServer)
///
/// let app = LambdaApp()
///     .addAPIGateway(key: "mcp", handler: adapter.bridge(router))
/// ```
///
/// ## Error Handling
///
/// If no route matches, returns an MCP error response:
/// ```json
/// {
///   "error": {
///     "code": -32601,
///     "message": "No MCP server found for path: /unknown/path"
///   }
/// }
/// ```
public final class Router<Context>: @unchecked Sendable {

    private var routes: [RouteDefinition] = []
    private let jsonValueEncoder = JSONValueEncoder()

    public init() {}

    /// Add a server for a path pattern with optional route-specific middleware
    ///
    /// The configure closure allows chaining `.usePreRequestMiddleware()` calls
    /// to add middleware that runs only for this specific route.
    ///
    /// ## Route Order Matters
    ///
    /// Routes are matched in **registration order** (first match wins).
    /// Register specific routes before wildcard routes:
    ///
    /// ```swift
    /// // ✅ Good: Specific before wildcard
    /// router.addServer(path: "/users/admin", server: adminServer)
    /// router.addServer(path: "/users/{id}", server: userServer)
    ///
    /// // ❌ Bad: Wildcard before specific (specific route never reached)
    /// router.addServer(path: "/users/{id}", server: userServer)
    /// router.addServer(path: "/users/admin", server: adminServer)  // Never matched!
    /// ```
    ///
    /// ## Middleware Execution
    ///
    /// Route middleware executes AFTER path matching (pathParams available) and
    /// AFTER global adapter middleware.
    ///
    /// Example:
    /// ```swift
    /// router.addServer(path: "/admin/{tenant}/tools", server: adminServer) { route in
    ///     route.usePreRequestMiddleware(authMiddleware)
    ///     route.usePreRequestMiddleware(adminCheckMiddleware)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - path: String path pattern (e.g., "/files/{customerId}")
    ///   - server: MCP server to handle requests matching this path
    ///   - configure: Optional closure to configure route middleware
    /// - Returns: Self for method chaining
    @discardableResult
    public func addServer(
        path: String,
        server: Server,
        configure: ((RouteBuilder) -> Void)? = nil
    ) -> Router<Context> {
        let builder = RouteBuilder(router: self, path: path, server: server)
        configure?(builder)
        return builder.completeRegistration()
    }

    /// Register an MCP server for the root path (handles all requests)
    ///
    /// - Parameter server: MCP server to handle all requests
    /// - Returns: Self for method chaining
    @discardableResult
    public func addServer(server: Server) -> Router<Context> {
        return addServerDirect(
            path: "/",
            server: server,
            preRequestMiddlewareChain: PreRequestMiddlewareChain()
        )
    }

    /// Internal method to add a fully constructed route
    @discardableResult
    internal func addServerDirect(
        path: String,
        server: Server,
        preRequestMiddlewareChain: PreRequestMiddlewareChain<TransportEnvelope, Context>
    ) -> Router<Context> {
        // Parse pattern once and cache it in the route
        let pathPattern = PathPattern(path)
        let route = RouteDefinition(
            pattern: path,
            pathPattern: pathPattern,
            server: server,
            preRequestMiddlewareChain: preRequestMiddlewareChain
        )
        routes.append(route)
        return self
    }

    /// Route a request through middleware chain to appropriate server
    ///
    /// Routes are matched in **registration order** - the first matching route handles the request.
    ///
    /// ## Routing Process
    ///
    /// 1. **Find matching route** by path pattern (first match wins)
    /// 2. **Extract parameters** from URL path (e.g., `{customerId}` → `"acme-corp"`)
    /// 3. **Add parameters** to envelope for middleware/server access
    /// 4. **Execute route-specific middleware** chain (can reject request)
    /// 5. **Route to server** or return error response
    ///
    /// ## Path Matching
    ///
    /// ```swift
    /// // Router with multiple routes
    /// router.addServer(path: "/users/{id}", server: userServer)
    /// router.addServer(path: "/posts/{id}", server: postServer)
    ///
    /// // Match: /users/123 → userServer (id="123")
    /// // Match: /posts/456 → postServer (id="456")
    /// // No match: /admin → Error response
    /// ```
    ///
    /// ## Error Responses
    ///
    /// Returns MCP error if:
    /// - No route matches the path
    /// - Path has wrong number of segments
    /// - Middleware rejects the request
    ///
    /// - Parameters:
    ///   - envelope: Transport envelope with MCP request (pathParams nil initially)
    ///   - context: Transport-specific context (Lambda, Hummingbird, Stdio)
    ///   - logger: Optional logger (defaults to "mcp" label)
    /// - Returns: Transport response (JSON-encoded MCP response or error)
    public func route(
        _ envelope: TransportEnvelope,
        context: Context,
        logger: Logger? = nil
    ) async throws -> TransportResponse {
        // Find matching route
        for route in routes {
            if let pathParams = route.match(envelope.routePath) {
                // Add Params to envelope for route middleware
                var envelopeWithParams = envelope
                envelopeWithParams.pathParams = pathParams

                // Execute route-specific pre-request middleware chain
                let middlewareResult = try await route.preRequestMiddlewareChain.execute(
                    context: context,
                    envelope: envelopeWithParams
                )

                // Handle middleware rejection
                switch middlewareResult {
                case .reject(let error):
                    let errorResponse = Response<String>.fromError(
                        id: envelope.mcpRequest.id,
                        error: error
                    )
                    let errorData = try jsonValueEncoder.encode(errorResponse)
                    return TransportResponse(data: errorData)

                case .accept(let updatedEnvelope), .passthrough(let updatedEnvelope):
                    // Route to server with enriched envelope
                    let responseData: JSONValue = try await route.server.handleRequest(
                        updatedEnvelope,
                        pathParams: pathParams,
                        logger: logger ?? Logger(label: "mcp")
                    )
                    return TransportResponse(data: responseData)
                }
            }
        }

        // No matching route found
        let error = MCPError(
            code: .methodNotFound,
            message: "No MCP server found for path: \(envelope.routePath)"
        )
        let errorResponse = Response<String>.fromError(
            id: envelope.mcpRequest.id,
            error: error
        )
        let errorData = try jsonValueEncoder.encode(errorResponse)
        return TransportResponse(data: errorData)
    }

    // MARK: - Fluent Builder

    /// Builder for fluent route middleware configuration
    ///
    /// Allows chaining multiple `.usePreRequestMiddleware()` calls within
    /// the `addServer(path:server:configure:)` closure.
    ///
    /// Example:
    /// ```swift
    /// router.addServer(path: "/admin/{tenant}", server: server) { route in
    ///     route.usePreRequestMiddleware(authMiddleware)
    ///     route.usePreRequestMiddleware(tenantCheckMiddleware)
    /// }
    /// ```
    public final class RouteBuilder {
        private unowned let router: Router<Context>
        private let path: String
        private let server: Server
        private let preRequestMiddlewareChain = PreRequestMiddlewareChain<TransportEnvelope, Context>()

        internal init(router: Router<Context>, path: String, server: Server) {
            self.router = router
            self.path = path
            self.server = server
        }

        /// Add middleware to execute before the server handler
        ///
        /// Pre-request middleware runs after path matching (Params available)
        /// and after global adapter middleware, but before the MCP server processes
        /// the request.
        ///
        /// Route middleware has access to `envelope.pathParams` which is populated
        /// from the route pattern. This enables tenant-specific authentication,
        /// authorization, and data filtering.
        ///
        /// Example:
        /// ```swift
        /// route.usePreRequestMiddleware(MiddlewareHelpers.from { (context: LambdaMCPContext, envelope: TransportEnvelope) in
        ///     // Params available here!
        ///     guard let customerId = envelope.pathParams?.string("customerId") else {
        ///         return .reject(MCPError(code: .invalidRequest, message: "Missing customerId"))
        ///     }
        ///
        ///     // Verify user has access to this customer
        ///     let userId = try await authenticateUser(context)
        ///     guard try await hasAccess(userId: userId, customerId: customerId) else {
        ///         return .reject(MCPError(code: .invalidRequest, message: "Access denied"))
        ///     }
        ///
        ///     return .accept(metadata: ["userId": userId, "customerId": customerId])
        /// })
        /// ```
        ///
        /// - Parameter middleware: Middleware to add
        /// - Returns: Self for method chaining
        @discardableResult
        public func usePreRequestMiddleware<M: PreRequestMiddleware>(_ middleware: M) -> RouteBuilder
        where M.MiddlewareEnvelope == TransportEnvelope, M.Context == Context {
            preRequestMiddlewareChain.use(middleware.eraseToAnyPreRequestMiddleware())
            return self
        }

        /// Complete route registration and return to router
        ///
        /// This method is called automatically when the configure closure completes.
        /// You don't need to call it explicitly.
        ///
        /// - Returns: The router for continued fluent configuration
        internal func completeRegistration() -> Router<Context> {
            return router.addServerDirect(
                path: path,
                server: server,
                preRequestMiddlewareChain: preRequestMiddlewareChain
            )
        }
    }

    // MARK: - Internal Types
    
    /// Internal route definition containing pattern, server, and middleware
    ///
    /// Stores a compiled `PathPattern` for efficient matching across multiple requests.
    /// The pattern is compiled once during route registration and cached here.
    ///
    /// ## Performance
    ///
    /// Pattern compilation happens once in `addServerDirect()`. The compiled pattern
    /// is reused for all subsequent route matching, avoiding wasteful re-parsing.
    ///
    /// ## Components
    ///
    /// - `pattern`: Original pattern string (for debugging/logging)
    /// - `pathPattern`: Compiled pattern matcher (cached for performance)
    /// - `server`: MCP server to handle matching requests
    /// - `preRequestMiddlewareChain`: Route-specific middleware
    private struct RouteDefinition {
        /// Original pattern string (e.g., "/users/{id}")
        let pattern: String
        
        /// Compiled path pattern matcher (cached for performance)
        let pathPattern: PathPattern
        
        /// MCP server to handle requests matching this route
        let server: Server
        
        /// Route-specific middleware chain (executes after path matching)
        let preRequestMiddlewareChain: PreRequestMiddlewareChain<TransportEnvelope, Context>
        
        /// Match a URL path against this route's pattern
        ///
        /// Uses the cached `pathPattern` for efficient matching.
        ///
        /// - Parameter urlPath: URL path to match (e.g., "/users/123")
        /// - Returns: Extracted path parameters if matched, nil otherwise
        ///
        /// Example:
        /// ```swift
        /// // Route with pattern "/users/{id}"
        /// route.match("/users/123")  // → Params(id: "123")
        /// route.match("/posts/123")  // → nil
        /// ```
        func match(_ urlPath: String) -> Params? {
            return pathPattern.match(urlPath)
        }
    }
}
