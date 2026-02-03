/// Fluent builder for MCP servers running on standard I/O (stdio)
///
/// `App` provides a consistent closure-based API for configuring MCP servers to run
/// via stdin/stdout, making them compatible with MCP clients like Claude Desktop,
/// IDEs, and command-line tools. It encapsulates the adapter and router configuration
/// into a single, easy-to-use interface that matches the patterns used in MCPLambda
/// and MCPHummingbird.
///
/// ## Architecture
///
/// ```
/// Claude Desktop → stdin → MCPStdio.App → StdioAdapter → Middleware → Router → Server → stdout
/// ```
///
/// The App class:
/// 1. Creates a `StdioAdapter` for middleware configuration
/// 2. Creates a `StdioRouter` for path-based routing
/// 3. Provides them to your configure closure
/// 4. Runs the stdio server loop via `run()`
///
/// ## Basic Usage
///
/// ```swift
/// // Create MCP server
/// let server = Server()
///     .addTool("read_file", inputType: FileArgs.self) { request in
///         let contents = try String(contentsOfFile: request.input.path)
///         return .text(contents)
///     }
///
/// // Configure MCP app with closure-based pattern
/// let app = MCPStdio.App { adapter, router in
///     router.addServer(path: "/", server: server)
/// }
///
/// // Run stdio server
/// try await app.run()
/// ```
///
/// ## With Middleware
///
/// ```swift
/// let app = MCPStdio.App { adapter, router in
///     // Add global middleware (runs before routing)
///     adapter.usePreRequestMiddleware(envValidationMiddleware)
///     adapter.usePreRequestMiddleware(loggingMiddleware)
///
///     // Add servers with route-specific middleware
///     router.addServer(path: "/files/{userId}", server: fileServer) { route in
///         route.usePreRequestMiddleware(userAuthMiddleware)
///     }
/// }
///
/// try await app.run(path: "/files/default")
/// ```
///
/// ## Multi-Server Routing
///
/// ```swift
/// let app = MCPStdio.App { adapter, router in
///     router.addServer(path: "/files/{userId}", server: fileServer)
///     router.addServer(path: "/db/{tenant}", server: dbServer)
/// }
///
/// // Path can be set via:
/// // 1. Parameter: try await app.run(path: "/files/user-123")
/// // 2. Environment variable: export MCP_PATH="/db/acme-corp"
/// // 3. Default: "/" (root)
/// try await app.run()
/// ```
///
/// ## Path Parameters
///
/// Path parameters from the router pattern are available in all handlers:
///
/// ```swift
/// router.addServer(path: "/files/{userId}", server: server)
///
/// // In tool handler:
/// server.addTool("read_file", ...) { request in
///     let userId = request.pathParams?.string("userId")
///     // Load file specific to user
/// }
/// ```
///
/// ## Claude Desktop Integration
///
/// Configure in Claude Desktop settings (`claude_desktop_config.json`):
///
/// ```json
/// {
///   "mcpServers": {
///     "myserver": {
///       "command": "/path/to/MCPExample",
///       "args": ["stdio"],
///       "env": {
///         "MCP_PATH": "/files/default"
///       }
///     }
///   }
/// }
/// ```
///
/// ## Design Pattern
///
/// This class enforces a closure-based configuration pattern to reduce cognitive load:
/// - Consistent with `MCPLambda.App` and `MCPHummingbird.App`
/// - Adapter and router configured in single closure
/// - Simple `run()` method to start the server
public class App {

    public let adapter: StdioAdapter

    /// Create a new MCP stdio app with closure-based configuration
    ///
    /// The configure closure receives both the adapter and router, allowing you to:
    /// - Add middleware to the adapter (environment validation, logging, etc.)
    /// - Add servers to the router with path patterns
    /// - Configure route-specific middleware
    ///
    /// ## Example
    ///
    /// ```swift
    /// let app = MCPStdio.App { adapter, router in
    ///     // Configure adapter with middleware
    ///     adapter.usePreRequestMiddleware(envMiddleware)
    ///
    ///     // Configure router with servers
    ///     router.addServer(path: "/files/{userId}", server: fileServer) { route in
    ///         route.usePreRequestMiddleware(userCheckMiddleware)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter configure: Optional closure to configure adapter and router
    public init(configure: ((StdioAdapter, StdioRouter) -> Void)? = nil) {
        let router = StdioRouter()
        self.adapter = StdioAdapter(router: router)
        configure?(adapter, router)
    }

    /// Start the stdio server loop
    ///
    /// Begins reading JSON-RPC 2.0 requests from stdin and writing responses to stdout.
    /// This function blocks until stdin is closed (end of input).
    ///
    /// ## Path Resolution
    ///
    /// The route path is determined by:
    /// 1. `path` parameter (if provided)
    /// 2. `MCP_PATH` environment variable (if set)
    /// 3. Root path "/" (default)
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Use explicit path
    /// try await app.run(path: "/files/user-123")
    ///
    /// // Use environment variable
    /// // export MCP_PATH="/db/tenant-456"
    /// try await app.run()
    ///
    /// // Use default path "/"
    /// try await app.run()
    /// ```
    ///
    /// - Parameter path: Optional route path (overrides MCP_PATH environment variable)
    /// - Throws: Errors from middleware or server initialization
    public func run(path: String? = nil) async throws {
        try await adapter.run(mcpPath: path)
    }
}
