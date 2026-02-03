import Foundation
import MCP
import Logging

// MARK: - Stdio Context for Middleware

/// Stdio-specific context for middleware
///
/// Provides middleware with access to process information and environment variables
/// when running in stdio mode. Unlike Lambda or HTTP contexts, stdio middleware has
/// access to the local process environment.
///
/// ## Available Information
///
/// - **environment**: Full process environment variables (PATH, HOME, custom vars, etc.)
/// - **processId**: Current process identifier for logging/debugging
/// - **routePath**: Resolved MCP route path for this session
///
/// ## Example Usage
///
/// ```swift
/// struct EnvValidationMiddleware: Middleware {
///     typealias Context = StdioMCPContext
///
///     func handle(context: Context, envelope: TransportEnvelope) async throws -> MiddlewareResponse {
///         // Validate required environment variables
///         guard let apiKey = context.environment["API_KEY"] else {
///             return .reject(MCPError(code: .invalidRequest, message: "Missing API_KEY"))
///         }
///
///         // Add to metadata for tool handlers
///         return .accept(metadata: [
///             "apiKey": apiKey,
///             "processId": "\(context.processId)"
///         ])
///     }
/// }
/// ```
public struct StdioMCPContext {

    /// Process environment variables (e.g., PATH, HOME, MCP_PATH, etc.)
    public let environment: [String: String]

    /// Current process identifier
    public let processId: Int

    /// Resolved MCP route path for this session
    public let routePath: String

    public init(environment: [String: String], processId: Int, routePath: String) {
        self.environment = environment
        self.processId = processId
        self.routePath = routePath
    }
}

// MARK: - MCP Stdio Adapter

/// Bridges MCP servers/routers to stdio transport (standard input/output)
///
/// StdioAdapter enables MCP servers to communicate via stdin/stdout using JSON-RPC 2.0,
/// making them compatible with MCP clients like Claude Desktop, IDEs, and command-line tools.
/// It provides middleware support and path-based routing for multi-tenant scenarios.
///
/// ## Architecture
///
/// ```
/// Claude Desktop → stdin → StdioAdapter → Middleware Chain → MCP Router → Server → Handler
///                         ← stdout ←
/// ```
///
/// The adapter:
/// 1. Reads JSON-RPC 2.0 MCP requests line-by-line from stdin
/// 2. Builds TransportEnvelope with route path from MCP_PATH environment variable
/// 3. Executes middleware chain (environment validation, logging, etc.)
/// 4. Routes to appropriate MCP server based on path
/// 5. Writes JSON-RPC responses to stdout
///
/// ## Basic Usage (Single Server)
///
/// ```swift
/// // Create MCP server with tools
/// let server = Server()
///     .addTool("read_file", inputType: FileArgs.self) { request in
///         let contents = try String(contentsOfFile: request.input.path)
///         return .text(contents)
///     }
///
/// // Run in stdio mode (default path: "/")
/// let adapter = StdioAdapter(server: server)
/// try await adapter.run()
/// ```
///
/// ## Multi-Server Routing
///
/// ```swift
/// // Create multiple servers for different domains
/// let fileServer = Server()
///     .addTool("read_file", ...) { ... }
///
/// let dbServer = Server()
///     .addTool("query", ...) { ... }
///
/// // Create router with path patterns
/// let router = Router()
///     .addServer(path: "/files/{userId}", server: fileServer)
///     .addServer(path: "/db/{tenant}", server: dbServer)
///
/// // Run with explicit path (overrides MCP_PATH)
/// let adapter = StdioAdapter(router: router)
/// try await adapter.run(mcpPath: "/files/user-123")
///
/// // Or use environment variable:
/// // export MCP_PATH="/db/acme-corp"
/// try await adapter.run()
/// ```
///
/// ## Path Parameter Extraction
///
/// Path parameters from the route are available to all handlers:
///
/// ```swift
/// // Router path: "/files/{userId}"
/// // MCP_PATH: "/files/user-123"
///
/// server.addTool("read_file", ...) { request in
///     let userId = request.pathParams?.string("userId")  // "user-123"
///     // Load file specific to user
/// }
/// ```
///
/// ## Middleware Support
///
/// ```swift
/// // Validate environment variables
/// let envMiddleware = MiddlewareHelpers.from { (context: StdioMCPContext, envelope) in
///     guard let apiKey = context.environment["API_KEY"] else {
///         return .reject(MCPError(code: .invalidRequest, message: "Missing API_KEY"))
///     }
///     return .accept(metadata: ["apiKey": apiKey])
/// }
///
/// // Add logging
/// let logMiddleware = MiddlewareHelpers.from { (context: StdioMCPContext, envelope) in
///     print("[\(context.processId)] \(envelope.mcpRequest.method)", to: &stderr)
///     return .passthrough
/// }
///
/// // Build adapter with middleware
/// let adapter = StdioAdapter(server: server)
///     .addMiddleware(envMiddleware)
///     .addMiddleware(logMiddleware)
/// ```
///
/// ## Claude Desktop Integration
///
/// Configure in Claude Desktop settings:
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
/// ## Error Handling
///
/// Parse errors and exceptions are automatically caught and converted to
/// JSON-RPC error responses written to stdout. The server continues running
/// after errors, maintaining the connection.
public class StdioAdapter {

    private let router: StdioRouter
    private let logger: Logger
    private let inputReader: InputReader
    private let outputWriter: OutputWriter
    private let preRequestMiddlewareChain = PreRequestMiddlewareChain<TransportEnvelope, StdioMCPContext>()
    private let postResponseMiddlewareChain = PostResponseMiddlewareChain<TransportResponse, StdioMCPContext>()
    private let jsonEncoder = JSONEncoder()

    /// Create stdio adapter with dependency injection (for testing)
    ///
    /// This initializer allows full control over input/output, making the adapter
    /// testable without relying on actual stdin/stdout.
    ///
    /// - Parameters:
    ///   - router: MCP router with one or more servers
    ///   - inputReader: Input source (stdin in production, mock in tests)
    ///   - outputWriter: Output destination (stdout in production, mock in tests)
    public init(
        router: StdioRouter,
        inputReader: InputReader,
        outputWriter: OutputWriter
    ) {
        self.router = router
        self.logger = Logger(label: "mcp-stdio")
        self.inputReader = inputReader
        self.outputWriter = outputWriter
        jsonEncoder.outputFormatting = .sortedKeys
    }
    
    /// Create stdio adapter with MCP router
    ///
    /// Use this initializer for multi-server scenarios where you need
    /// path-based routing to different servers.
    ///
    /// - Parameter router: MCP router with one or more servers
    public convenience init(router: StdioRouter) {
        self.init(
            router: router,
            inputReader: StandardInputReader(),
            outputWriter: StandardOutputWriter()
        )
    }

    /// Create stdio adapter with single server
    ///
    /// Convenience initializer for single-server scenarios. Automatically
    /// creates a router with the server at the root path ("/").
    ///
    /// - Parameter server: MCP server to expose via stdio
    public convenience init(server: Server) {
        let router = StdioRouter().addServer(server: server)
        self.init(
            router: router,
            inputReader: StandardInputReader(),
            outputWriter: StandardOutputWriter()
        )
    }

    /// Add pre-request middleware to the execution chain
    ///
    /// Middleware executes in the order added, before the MCP server processes requests.
    /// Each middleware can inspect/modify the request or reject it with an error.
    ///
    /// - Parameter middleware: Middleware to add (must use StdioMCPContext)
    /// - Returns: Self for method chaining
    @discardableResult public func usePreRequestMiddleware<M: PreRequestMiddleware>(_ middleware: M) -> StdioAdapter
        where M.Context == StdioMCPContext, M.MiddlewareEnvelope == TransportEnvelope {
        preRequestMiddlewareChain.use(middleware)
        return self
    }

    /// Add post-response middleware to the execution chain
    ///
    /// Middleware executes in the order added, after the MCP server generates a response
    /// but before it's written to stdout. Each middleware can observe/transform the response.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let adapter = StdioAdapter(server: server)
    ///     .usePostResponseMiddleware(PostResponseMiddlewareHelpers.from {
    ///         (context: StdioMCPContext, envelope: ResponseEnvelope<TransportResponse>) in
    ///
    ///         // Log response timing
    ///         print("Request completed in \(envelope.timing.duration)s", to: &stderr)
    ///         return .passthrough
    ///     })
    /// ```
    ///
    /// - Parameter middleware: Post-response middleware to add
    /// - Returns: Self for method chaining
    @discardableResult public func usePostResponseMiddleware<M: PostResponseMiddleware>(_ middleware: M) -> StdioAdapter
    where M.Context == StdioMCPContext,
          M.Response == TransportResponse {
        postResponseMiddlewareChain.use(middleware.eraseToAnyPostResponseMiddleware())
        return self
    }

    /// Start stdio server loop
    ///
    /// Begins reading JSON-RPC 2.0 requests from stdin and writing responses to stdout.
    /// This function blocks until stdin is closed (end of input).
    ///
    /// ## Path Resolution
    ///
    /// The route path is determined by:
    /// 1. `mcpPath` parameter (if provided)
    /// 2. `MCP_PATH` environment variable (if set)
    /// 3. Root path "/" (default)
    ///
    /// ## Request Processing
    ///
    /// For each line from stdin:
    /// 1. Parse as JSON-RPC 2.0 request
    /// 2. Run middleware chain
    /// 3. Route to appropriate server
    /// 4. Write response to stdout
    /// 5. Flush stdout buffer
    ///
    /// ## Error Handling
    ///
    /// Parse errors are caught and converted to JSON-RPC error responses.
    /// The server continues running after errors.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Use explicit path
    /// try await adapter.run(mcpPath: "/files/user-123")
    ///
    /// // Use environment variable
    /// // export MCP_PATH="/db/tenant-456"
    /// try await adapter.run()
    /// ```
    ///
    /// - Parameter mcpPath: Optional route path (overrides MCP_PATH environment variable)
    /// - Throws: Errors from middleware or server initialization
    public func run(mcpPath: String? = nil) async throws {
        let routePath = mcpPath ?? ProcessInfo.processInfo.environment["MCP_PATH"] ?? "/"

        while let line = try await inputReader.readLine() {
            do {
                let responseString = try await processRequest(line: line, routePath: routePath)
                try await outputWriter.writeLine(responseString)
                try await outputWriter.flush()
            } catch {
                let errorString = try formatError(error, requestId: nil)
                try await outputWriter.writeLine(errorString)
                try await outputWriter.flush()
            }
        }
    }
    
    /// Process a single request line and return the response as a JSON string
    ///
    /// This method contains the core request processing logic, extracted from run()
    /// to make it testable. It handles:
    /// 1. Parsing the JSON-RPC request
    /// 2. Running middleware chains
    /// 3. Routing to the appropriate server
    /// 4. Encoding the response
    ///
    /// - Parameters:
    ///   - line: JSON-RPC request as a string
    ///   - routePath: MCP route path for routing
    /// - Returns: JSON-RPC response as a string
    /// - Throws: Errors from parsing, middleware, or server processing
    func processRequest(line: String, routePath: String) async throws -> String {
        // Capture start time for post-response middleware
        let startTime = Date()

        let requestData = line.data(using: .utf8) ?? Data()
        let mcpRequest = try JSONDecoder().decode(Request.self, from: requestData)

        // Build transport envelope with stdio metadata (Params nil for global middleware)
        var envelope = TransportEnvelope(
            mcpRequest: mcpRequest,
            routePath: routePath,
            metadata: [:]
        )

        // Build stdio context for middleware
        let stdioContext = StdioMCPContext(
            environment: ProcessInfo.processInfo.environment,
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            routePath: routePath
        )

        // Run global pre-request middleware chain (before routing)
        let middlewareResult = try await preRequestMiddlewareChain.execute(
            context: stdioContext,
            envelope: envelope
        )

        // Handle global middleware rejection
        switch middlewareResult {
        case .reject(let error):
            // Global middleware rejected - return error immediately
            return try formatError(error, requestId: mcpRequest.id)

        case .accept(let updatedEnvelope), .passthrough(let updatedEnvelope):
            envelope = updatedEnvelope
        }

        // Route through MCP router (runs route middleware with Params)
        var response = try await router.route(
            envelope,
            context: stdioContext,
            logger: logger
        )

        // Run post-response middleware chain
        let endTime = Date()
        let timing = RequestTiming(startTime: startTime, endTime: endTime)

        let responseEnvelope = ResponseEnvelope(request: envelope, response: response, timing: timing)
        response = try await postResponseMiddlewareChain.execute(
            context: stdioContext,
            envelope: responseEnvelope
        )

        // Encode response to JSON string
        let responseAsRawData = try jsonEncoder.encode(response.data)
        guard let responseString = String(data: responseAsRawData, encoding: .utf8) else {
            throw MCPError(code: .internalError, message: "Failed to encode response as UTF-8")
        }
        
        return responseString
    }
    
    /// Format an error as a JSON-RPC error response
    ///
    /// - Parameters:
    ///   - error: The error to format
    ///   - requestId: Optional request ID to include in the error response
    /// - Returns: JSON-RPC error response as a string
    /// - Throws: If encoding the error response fails
    private func formatError(_ error: Error, requestId: RequestId?) throws -> String {
        let mcpError: MCPError
        if let existingError = error as? MCPError {
            mcpError = existingError
        } else {
            mcpError = MCPError(code: .parseError, message: "Parse error: \(error.localizedDescription)")
        }
        
        let errorResponse = Response<String>.fromError(
            id: requestId,
            error: mcpError
        )
        
        let errorData = try jsonEncoder.encode(errorResponse)
        guard let errorString = String(data: errorData, encoding: .utf8) else {
            throw MCPError(code: .internalError, message: "Failed to encode error response as UTF-8")
        }
        
        return errorString
    }
}

// MARK: - Simple Adapter (No Middleware)

/// Convenience adapter for stdio without middleware
///
/// Provides a simplified interface for running MCP servers over stdio without
/// setting up middleware. Use this for basic scenarios where you don't need
/// environment validation, logging, or other middleware features.
///
/// ## When to Use
///
/// - **Quick prototyping**: Simple tool development without middleware
/// - **Basic servers**: No need for environment validation or logging
/// - **Learning**: Getting started with MCP stdio integration
///
/// ## When to Use StdioAdapter Instead
///
/// - **Production tools**: Need environment validation, logging
/// - **Multi-user**: Need to validate user context
/// - **Observability**: Need request logging, metrics, debugging
///
/// ## Example
///
/// ```swift
/// // Quick setup without middleware
/// let server = Server()
///     .addTool("hello", inputType: Empty.self) { _ in
///         return .text("Hello, world!")
///     }
///
/// let adapter = MCPStdioSimpleAdapter(server: server)
/// try await adapter.run()
///
/// // vs. Full setup with middleware
/// let adapter = StdioAdapter(server: server)
///     .addMiddleware(envValidationMiddleware)
///     .addMiddleware(loggingMiddleware)
/// try await adapter.run()
/// ```
public class MCPStdioSimpleAdapter {

    private let adapter: StdioAdapter

    /// Create simple adapter with router (no middleware)
    ///
    /// - Parameter router: MCP router with one or more servers
    public init(router: StdioRouter) {
        self.adapter = StdioAdapter(router: router)
    }

    /// Create simple adapter with server (no middleware)
    ///
    /// - Parameter server: MCP server to expose via stdio
    public init(server: Server) {
        self.adapter = StdioAdapter(server: server)
    }

    /// Create simple adapter with empty server (no middleware)
    ///
    /// Creates a new empty MCP server. Tools/resources can be added later
    /// using the server instance.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let adapter = MCPStdioSimpleAdapter()
    /// // Server is created internally, tools added via server property
    /// ```
    ///
    /// - Parameter logger: Logger to use (defaults to "mcp-stdio" label)
    public init(logger: Logger = Logger(label: "mcp-stdio")) {
        let server = Server(logger: logger)
        self.adapter = StdioAdapter(server: server)
    }

    /// Start stdio server loop
    ///
    /// Begins reading JSON-RPC 2.0 requests from stdin and writing responses
    /// to stdout. Blocks until stdin is closed.
    ///
    /// - Parameter mcpPath: Optional route path (overrides MCP_PATH environment variable)
    /// - Throws: Errors from server initialization
    public func run(mcpPath: String? = nil) async throws {
        try await adapter.run(mcpPath: mcpPath)
    }
}

// MARK: - Type Alias

/// Router for standard I/O with StdioMCPContext
///
/// Use this type alias when building MCP routers for stdio transport (Claude Desktop, etc.).
///
/// Example:
/// ```swift
/// let router = StdioRouter()
///     .addServer(path: "/files/{userId}", server: fileServer) { route in
///         route.usePreRequestMiddleware(envValidationMiddleware)
///     }
///     .addServer(path: "/db/{tenant}", server: dbServer)
/// ```
public typealias StdioRouter = Router<StdioMCPContext>
