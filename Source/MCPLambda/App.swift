import LambdaApp

/// Fluent builder for MCP servers deployed to AWS Lambda
///
/// `App` provides a consistent closure-based API for configuring MCP servers to run
/// on AWS Lambda via API Gateway. It encapsulates the adapter and router configuration
/// into a single, easy-to-use interface that matches the patterns used in MCPStdio
/// and MCPHummingbird.
///
/// ## Architecture
///
/// ```
/// API Gateway → Lambda → MCPLambda.App → LambdaAdapter → Middleware → Router → Server
/// ```
///
/// The App class:
/// 1. Creates a `LambdaAdapter` for middleware configuration
/// 2. Creates a `LambdaRouter` for path-based routing
/// 3. Provides them to your configure closure
/// 4. Generates a Lambda handler via `createHandler()`
/// 5. Integrates with `LambdaApp` for multi-handler deployments
///
/// ## Basic Usage
///
/// ```swift
/// // Create MCP server
/// let server = Server()
///     .addTool("query_data", inputType: QueryArgs.self) { request in
///         return QueryResults(data: [...])
///     }
///
/// // Configure MCP app with closure-based pattern
/// let mcpApp = MCPLambda.App { adapter, router in
///     router.addServer(path: "/api", server: server)
/// }
///
/// // Integrate with LambdaApp
/// let lambdaApp = LambdaApp()
///     .addMCP(key: "mcp", mcpApp: mcpApp)
///
/// lambdaApp.run(handlerKey: "mcp")
/// ```
///
/// ## With Middleware
///
/// ```swift
/// let mcpApp = MCPLambda.App { adapter, router in
///     // Add global middleware (runs before routing)
///     adapter.usePrequestMiddleware(authMiddleware)
///     adapter.usePrequestMiddleware(loggingMiddleware)
///
///     // Add servers with route-specific middleware
///     router.addServer(path: "/api/{customerId}", server: apiServer) { route in
///         route.usePreRequestMiddleware(customerAuthMiddleware)
///     }
/// }
/// ```
///
/// ## Multi-Handler Lambda
///
/// ```swift
/// let mcpApp = MCPLambda.App { adapter, router in
///     router.addServer(path: "/files/{userId}", server: fileServer)
///     router.addServer(path: "/db/{tenant}", server: dbServer)
/// }
///
/// let lambdaApp = LambdaApp()
///     .addSQS(key: "queue", handler: queueHandler)
///     .addMCP(key: "mcp", mcpApp: mcpApp)
///     .addS3(key: "files", handler: fileHandler)
///
/// // Set MY_HANDLER environment variable to: "queue", "mcp", or "files"
/// lambdaApp.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
/// ```
///
/// ## Path Parameters
///
/// Path parameters from the router pattern are available in all handlers:
///
/// ```swift
/// router.addServer(path: "/api/{customerId}/tools", server: server)
///
/// // In tool handler:
/// server.addTool("get_customer_data", ...) { request in
///     let customerId = request.pathParams?.string("customerId")
///     // Use customerId to filter data
/// }
/// ```
///
/// ## Deployment
///
/// Deploy the built executable to Lambda and configure API Gateway:
///
/// 1. Build for Lambda: `./docker-build.sh pineapple`
/// 2. Deploy to Lambda from `.lambda-build/`
/// 3. Set environment: `MY_HANDLER=mcp`
/// 4. Configure API Gateway to proxy all requests to Lambda
///
/// ## Design Pattern
///
/// This class enforces a closure-based configuration pattern to reduce cognitive load:
/// - Adapter and router are private (only configurable in closure)
/// - Single integration method via `LambdaApp.addMCP()`
/// - Consistent with `MCPStdio.App` and `MCPHummingbird.App`
public class App {

    private let adapter: LambdaAdapter
    private let router: LambdaRouter

    /// Create a new MCP Lambda app with closure-based configuration
    ///
    /// The configure closure receives both the adapter and router, allowing you to:
    /// - Add middleware to the adapter (auth, logging, etc.)
    /// - Add servers to the router with path patterns
    /// - Configure route-specific middleware
    ///
    /// ## Example
    ///
    /// ```swift
    /// let mcpApp = MCPLambda.App { adapter, router in
    ///     // Configure adapter with middleware
    ///     adapter.usePrequestMiddleware(authMiddleware)
    ///
    ///     // Configure router with servers
    ///     router.addServer(path: "/api/{customerId}", server: apiServer) { route in
    ///         route.usePreRequestMiddleware(tenantCheckMiddleware)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter configure: Optional closure to configure adapter and router
    public init(
        configure: ((LambdaAdapter, LambdaRouter) -> Void)? = nil
    ) {
        self.adapter = LambdaAdapter()
        self.router = LambdaRouter()
        configure?(adapter, router)
    }

    /// Creates the Lambda API Gateway handler function
    ///
    /// This method is called by the `LambdaApp.addMCP()` extension to
    /// generate the handler function that bridges API Gateway requests to MCP responses.
    ///
    /// - Returns: Lambda handler function
    func createHandler() -> (LambdaContext, APIGatewayRequest) async throws -> APIGatewayResponse {
        adapter.bridge(router)
    }
}

/// LambdaApp extensions for integrating MCP apps
public extension LambdaApp {

    /// Add MCP app to LambdaApp's multi-handler registry
    ///
    /// Registers the MCP app as a Lambda handler with the specified key. The key is used
    /// to route Lambda invocations when multiple handlers are registered (via `MY_HANDLER`
    /// environment variable).
    ///
    /// ## Example
    ///
    /// ```swift
    /// let mcpApp = MCPLambda.App { adapter, router in
    ///     router.addServer(path: "/api", server: apiServer)
    /// }
    ///
    /// let lambdaApp = LambdaApp()
    ///     .addSQS(key: "queue", handler: queueHandler)
    ///     .addMCP(key: "mcp", mcpApp: mcpApp)
    ///
    /// // Set MY_HANDLER=mcp to route to the MCP handler
    /// lambdaApp.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
    /// ```
    ///
    /// - Parameters:
    ///   - key: Handler key for routing (matches `MY_HANDLER` environment variable)
    ///   - app: Configured MCP app
    /// - Returns: Self for method chaining
    @discardableResult func addMCP(key: String, mcpApp app: App) -> LambdaApp {
        addAPIGateway(key: key, handler: app.createHandler())
    }
}

// MARK: - V2 App

/// Fluent builder for MCP servers deployed to AWS Lambda via API Gateway HTTP API (V2)
///
/// Mirrors `App` but uses V2 types for lower latency and lower cost HTTP API.
public class V2App {

    private let adapter: LambdaV2Adapter
    private let router: LambdaV2Router

    /// Create a new MCP Lambda V2 app with closure-based configuration
    public init(
        configure: ((LambdaV2Adapter, LambdaV2Router) -> Void)? = nil
    ) {
        self.adapter = LambdaV2Adapter()
        self.router = LambdaV2Router()
        configure?(adapter, router)
    }

    /// Creates the Lambda API Gateway V2 handler function
    func createHandler() -> (LambdaContext, APIGatewayV2Request) async throws -> APIGatewayV2Response {
        adapter.bridge(router)
    }
}

/// LambdaApp extension for integrating MCP V2 apps
public extension LambdaApp {

    @discardableResult func addMCPV2(key: String, mcpApp app: V2App) -> LambdaApp {
        addAPIGatewayV2(key: key, handler: app.createHandler())
    }
}
