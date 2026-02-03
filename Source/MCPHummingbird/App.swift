import Hummingbird

/// Fluent builder for MCP servers running on HTTP via Hummingbird
///
/// `App` provides a consistent closure-based API for configuring MCP servers to run
/// as HTTP services using the Hummingbird web framework. This is ideal for local
/// development, testing, and HTTP-based MCP integrations. It encapsulates the adapter
/// and router configuration into a single, easy-to-use interface that matches the
/// patterns used in MCPLambda and MCPStdio.
///
/// ## Architecture
///
/// ```
/// HTTP Client → Hummingbird → MCPHummingbird.App → HummingbirdAdapter → Middleware → Router → Server
/// ```
///
/// The App class:
/// 1. Creates a `HummingbirdAdapter` for middleware configuration
/// 2. Creates a `HummingbirdRouter` for path-based routing
/// 3. Provides them to your configure closure
/// 4. Creates the Hummingbird application
/// 5. Runs the HTTP server via `run()`
///
/// ## Basic Usage
///
/// ```swift
/// // Create MCP server
/// let server = Server()
///     .addTool("get_data", inputType: QueryArgs.self) { request in
///         return QueryResults(data: [...])
///     }
///
/// // Configure MCP app with closure-based pattern (default: localhost:8080)
/// let app = MCPHummingbird.App { adapter, router in
///     router.addServer(path: "/api", server: server)
/// }
///
/// // Run HTTP server
/// try await app.run()
/// ```
///
/// ## Custom Server Configuration
///
/// ```swift
/// // Configure custom host and port
/// let config = ApplicationConfiguration(
///     address: .hostname("0.0.0.0", port: 3000)
/// )
///
/// let app = MCPHummingbird.App(config) { adapter, router in
///     router.addServer(path: "/api", server: server)
/// }
///
/// try await app.run()
/// ```
///
/// ## With Middleware
///
/// ```swift
/// let app = MCPHummingbird.App { adapter, router in
///     // Add global middleware (runs before routing)
///     adapter.usePreRequestMiddleware(loggingMiddleware)
///     adapter.usePreRequestMiddleware(corsMiddleware)
///
///     // Add servers with route-specific middleware
///     router.addServer(path: "/api/{customerId}", server: apiServer) { route in
///         route.usePreRequestMiddleware(authMiddleware)
///     }
/// }
///
/// try await app.run()
/// ```
///
/// ## Multi-Server Routing
///
/// ```swift
/// let app = MCPHummingbird.App { adapter, router in
///     router.addServer(path: "/files/{userId}", server: fileServer)
///     router.addServer(path: "/db/{tenant}", server: dbServer)
///     router.addServer(path: "/public/health", server: healthServer)
/// }
///
/// try await app.run()
/// // Access via:
/// // POST http://localhost:8080/files/user-123
/// // POST http://localhost:8080/db/acme-corp
/// // POST http://localhost:8080/public/health
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
/// server.addTool("get_data", ...) { request in
///     let customerId = request.pathParams?.string("customerId")
///     // Use customerId to filter data
/// }
/// ```
///
/// ## Testing MCP Requests
///
/// ```bash
/// # Test with curl
/// curl -X POST http://localhost:8080/api \\
///   -H "Content-Type: application/json" \\
///   -d '{
///     "jsonrpc": "2.0",
///     "method": "tools/list",
///     "id": 1
///   }'
/// ```
///
/// ## Use Cases
///
/// - **Local development**: Test MCP servers with HTTP clients before deploying
/// - **Integration testing**: Automated tests against HTTP endpoints
/// - **Web-based MCP**: Serve MCP protocol over HTTP for browser/web integrations
/// - **Debugging**: Use HTTP tools (Postman, curl) to inspect requests/responses
///
/// ## Design Pattern
///
/// This class enforces a closure-based configuration pattern to reduce cognitive load:
/// - Consistent with `MCPLambda.App` and `MCPStdio.App`
/// - Adapter and router configured in single closure
/// - Simple `run()` method to start the server
/// - Sensible defaults (localhost:8080) for quick setup
public class App {

    public let hummingbird: Application<RouterResponder<BasicRequestContext>>

    /// Create a new MCP HTTP app with closure-based configuration
    ///
    /// The configure closure receives both the adapter and router, allowing you to:
    /// - Add middleware to the adapter (logging, CORS, auth, etc.)
    /// - Add servers to the router with path patterns
    /// - Configure route-specific middleware
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Default configuration (localhost:8080)
    /// let app = MCPHummingbird.App { adapter, router in
    ///     adapter.usePreRequestMiddleware(loggingMiddleware)
    ///     router.addServer(path: "/api", server: apiServer)
    /// }
    ///
    /// // Custom configuration
    /// let config = ApplicationConfiguration(
    ///     address: .hostname("0.0.0.0", port: 3000)
    /// )
    /// let app = MCPHummingbird.App(config) { adapter, router in
    ///     router.addServer(path: "/api/{customerId}", server: apiServer) { route in
    ///         route.usePreRequestMiddleware(authMiddleware)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - configuration: Hummingbird server configuration (default: localhost:8080)
    ///   - configure: Optional closure to configure adapter and router
    public init(
        _ configuration: ApplicationConfiguration = .init(address: .hostname("localhost", port: 8080)),
        configure: ((HummingbirdAdapter, HummingbirdRouter) -> Void)? = nil
    ) {
        let adapter = HummingbirdAdapter()
        let httpRouter = HummingbirdRouter()
        if let configure {
            configure(adapter, httpRouter)
        }
        hummingbird = adapter.createApp(
            router: httpRouter,
            configuration: configuration
        )
    }

    /// Start the HTTP server
    ///
    /// Starts the Hummingbird HTTP server and blocks until the server is shut down.
    /// The server listens on the address and port specified in the configuration.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let app = MCPHummingbird.App { adapter, router in
    ///     router.addServer(path: "/api", server: server)
    /// }
    ///
    /// print("Starting MCP HTTP server on http://localhost:8080")
    /// try await app.run()
    /// ```
    ///
    /// - Throws: Errors from server startup or runtime
    public func run() async throws {
        try await hummingbird.runService()
    }
}
