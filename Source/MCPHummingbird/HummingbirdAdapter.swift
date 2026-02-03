import Foundation
import Hummingbird
import NIOCore
import MCP
import Logging

/// HTTP context for Hummingbird middleware
///


public struct HummingbirdMCPContext: @unchecked Sendable {
    
    public let request: Hummingbird.Request
    public let context: BasicRequestContext
    public let logger: Logger
    
    public init(request: Hummingbird.Request, context: BasicRequestContext, logger: Logger) {
        self.request = request
        self.context = context
        self.logger = logger
    }
}

public class HummingbirdAdapter: @unchecked Sendable {

    private let preRequestMiddlewareChain = PreRequestMiddlewareChain<TransportEnvelope, HummingbirdMCPContext>()
    private let postResponseMiddlewareChain = PostResponseMiddlewareChain<Response, HummingbirdMCPContext>()
    private let jsonEncoder = JSONEncoder()

    public init() {
        jsonEncoder.outputFormatting = .sortedKeys
    }

    @discardableResult public func usePreRequestMiddleware<M: PreRequestMiddleware>(
        _ middleware: M
    ) -> HummingbirdAdapter where M.Context == HummingbirdMCPContext, M.MiddlewareEnvelope == TransportEnvelope {
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
    /// let adapter = HummingbirdAdapter()
    ///     .usePostResponseMiddleware(PostResponseMiddlewareHelpers.from {
    ///         (context: HummingbirdMCPContext, envelope: ResponseEnvelope<Response>) in
    ///
    ///         var modified = envelope.response
    ///         modified.headers[.init("X-Duration-Ms")!] = "\(envelope.timing.duration * 1000)"
    ///         return .accept(modified)
    ///     })
    /// ```
    ///
    /// - Parameter middleware: Post-response middleware to add
    /// - Returns: Self for method chaining
    @discardableResult public func usePostResponseMiddleware<M: PostResponseMiddleware>(_ middleware: M) -> HummingbirdAdapter
    where M.Context == HummingbirdMCPContext,
          M.Response == Response {
        postResponseMiddlewareChain.use(middleware.eraseToAnyPostResponseMiddleware())
        return self
    }

    /// Creates a Hummingbird application with MCP router and middleware
    /// - Parameter router: Configured MCP router
    /// - Returns: Configured Hummingbird application
    public func createApp(
        router mcpRouter: HummingbirdRouter,
        configuration: ApplicationConfiguration
    ) -> Application<RouterResponder<BasicRequestContext>> {
        // Add MCP route handler

        let hbRouter = Hummingbird.Router()
        hbRouter.post("/**") { [self] (request: Request, context: BasicRequestContext) async throws -> Response in
            return try await handleMCPRequest(
                request: request,
                context: context,
                mcpRouter: mcpRouter
            )
        }
        let app = Application(router: hbRouter, configuration: configuration)
        return app
    }
    
    /// Creates a Hummingbird application with MCP server (convenience method)
    /// - Parameter server: MCP server instance
    /// - Returns: Configured Hummingbird application
    public func createApp(
        server: Server,
        configuration: ApplicationConfiguration
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = HummingbirdRouter().addServer(path: "/", server: server)
        return self.createApp(router: router, configuration: configuration)
    }

    private func handleMCPRequest(
        request: Request,
        context: BasicRequestContext,
        mcpRouter: HummingbirdRouter
    ) async throws -> Response {
        // Capture start time for post-response middleware
        let startTime = Date()

        // Extract route path
        let routePath = request.uri.path

        // Read the request body
        var bodyData = Data()
        for try await buffer in request.body.buffer(policy: .unbounded) {
            bodyData.append(contentsOf: buffer.readableBytesView)
        }

        // Parse MCP request from body
        let mcpRequest = try JSONDecoder().decode(MCP.Request.self, from: bodyData)

        // Build transport envelope with Hummingbird metadata (Params nil for global middleware)
        var envelope = TransportEnvelope(
            mcpRequest: mcpRequest,
            routePath: routePath,
            metadata: [:]
        )

        // Build Hummingbird context for middleware
        let logger = Logger(label: "mcp-hummingbird")
        let mcpContext = HummingbirdMCPContext(request: request, context: context, logger: logger)

        // Run global pre-request middleware chain (before routing)
        let middlewareResult = try await preRequestMiddlewareChain.execute(
            context: mcpContext,
            envelope: envelope
        )

        // Handle global middleware rejection
        switch middlewareResult {
        case .reject(let error):
            // Global middleware rejected - return error response
            let errorResponse = MCP.Response<String>.fromError(
                id: mcpRequest.id,
                error: error
            )
            let errorData = try jsonEncoder.encode(errorResponse)

            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            headers[.init("Access-Control-Allow-Origin")!] = "*"

            return Response(
                status: .ok,
                headers: headers,
                body: .init { writer in
                    let buffer = ByteBuffer(bytes: errorData)
                    try await writer.write(buffer)
                    try await writer.finish(nil)
                }
            )

        case .accept(let updatedEnvelope), .passthrough(let updatedEnvelope):
            envelope = updatedEnvelope
        }

        // Route through MCP router (runs route middleware with Params)
        let mcpResponse = try await mcpRouter.route(
            envelope,
            context: mcpContext,
            logger: logger
        )
        let responseAsRawData = try jsonEncoder.encode(mcpResponse.data)

        // Build Hummingbird Response
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        headers[.init("Access-Control-Allow-Origin")!] = "*"
        headers[.init("Access-Control-Allow-Methods")!] = "POST, OPTIONS"
        headers[.init("Access-Control-Allow-Headers")!] = "Content-Type"

        var hummingbirdResponse = Response(
            status: .ok,
            headers: headers,
            body: .init { writer in
                let buffer = ByteBuffer(bytes: responseAsRawData)
                try await writer.write(buffer)
                try await writer.finish(nil)
            }
        )

        // Run post-response middleware chain
        let endTime = Date()
        let timing = RequestTiming(startTime: startTime, endTime: endTime)

        let responseEnvelope = ResponseEnvelope(request: envelope, response: hummingbirdResponse, timing: timing)
        hummingbirdResponse = try await postResponseMiddlewareChain.execute(
            context: mcpContext,
            envelope: responseEnvelope
        )

        return hummingbirdResponse
    }
}

// MARK: - Convenience non-generic adapter for no middleware

public class MCPHummingbirdSimpleAdapter {

    public init() {}

    /// Creates a Hummingbird application with MCP router (no middleware)
    public static func createApp(
        router mcpRouter: HummingbirdRouter,
        configuration: ApplicationConfiguration
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let adapter = HummingbirdAdapter()
        return adapter.createApp(router: mcpRouter, configuration: configuration)
    }

    /// Creates a Hummingbird application with MCP server (no middleware)
    public static func createApp(
        server: Server,
        configuration: ApplicationConfiguration
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let adapter = HummingbirdAdapter()
        return adapter.createApp(server: server, configuration: configuration)
    }
}

// MARK: - Type Alias

/// Router for Hummingbird HTTP server with HummingbirdMCPContext
///
/// Use this type alias when building MCP routers for Hummingbird HTTP servers.
///
/// Example:
/// ```swift
/// let router = HummingbirdRouter()
///     .addServer(path: "/api/tools", server: toolServer) { route in
///         route.usePreRequestMiddleware(authMiddleware)
///     }
///     .addServer(path: "/api/files", server: fileServer)
/// ```
public typealias HummingbirdRouter = MCP.Router<HummingbirdMCPContext>
