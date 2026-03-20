import Foundation
import MCP
import MCPWebSocketShared
import Logging

// MARK: - WebSocket Adapter Errors

/// Errors specific to the WebSocket adapter
public enum WebSocketAdapterError: Error, Sendable {
    case connectionFailed(String)
    case unsupportedMessageType
    case encodingFailed
    case decodingFailed(String)
    case disconnected
    case cancelled
}

// MARK: - WebSocket MCP Adapter

/// Bridges MCP servers/routers to a WebSocket relay transport for iOS apps
///
/// `WebSocketAdapter` connects an iOS app's MCP server to an AWS WebSocket relay,
/// enabling MCP clients (like Claude) to communicate with tools running on an iOS device.
///
/// ## Architecture
///
/// ```
/// MCP Client → HTTP → AWS Relay → WebSocket → WebSocketAdapter → MCP Router → Server
///                                  ← WebSocket ←
/// ```
///
/// The adapter:
/// 1. Connects outbound to the relay via WebSocket (iOS can't run HTTP servers)
/// 2. Receives `RelayRequest` messages containing JSON-RPC MCP requests
/// 3. Routes through the MCP middleware chain and server
/// 4. Sends `RelayResponse` messages back through the WebSocket
/// 5. Maintains connection with ping keep-alive (5 min interval)
/// 6. Reconnects automatically with exponential backoff on disconnect
///
/// ## Basic Usage
///
/// ```swift
/// let server = Server()
///     .addTool("get_location", inputType: Empty.self) { _ in
///         return .text("San Francisco, CA")
///     }
///
/// let adapter = WebSocketAdapter(server: server, url: relayURL)
/// try await adapter.run(sessionId: UUID().uuidString, token: jwtToken)
/// ```
///
/// ## Multi-Server Routing
///
/// ```swift
/// let router = WebSocketRouter()
///     .addServer(path: "/tools", server: toolServer)
///     .addServer(path: "/data", server: dataServer)
///
/// let adapter = WebSocketAdapter(router: router, url: relayURL)
/// try await adapter.run(sessionId: sessionId, token: jwtToken)
/// ```
public class WebSocketAdapter: @unchecked Sendable {

    private let router: WebSocketRouter
    private let url: URL
    private let connectionFactory: WebSocketConnectionFactory
    private let logger: Logger
    private let preRequestMiddlewareChain = PreRequestMiddlewareChain<TransportEnvelope, WebSocketMCPContext>()
    private let postResponseMiddlewareChain = PostResponseMiddlewareChain<TransportResponse, WebSocketMCPContext>()
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    /// Keep-alive ping interval (5 minutes, under API Gateway's 10-min idle timeout)
    public var pingInterval: TimeInterval = 300

    /// Maximum reconnection backoff delay in seconds
    public var maxReconnectDelay: TimeInterval = 30

    /// Base reconnection delay in seconds (doubles each attempt)
    public var baseReconnectDelay: TimeInterval = 1

    /// Maximum number of reconnection attempts (0 = unlimited)
    public var maxReconnectAttempts: Int = 0

    /// Create adapter with MCP router and relay URL
    ///
    /// - Parameters:
    ///   - router: MCP router with one or more servers
    ///   - url: WebSocket relay URL (e.g., wss://relay.example.com)
    ///   - connectionFactory: Factory for creating WebSocket connections (default: URLSession-based)
    public init(
        router: WebSocketRouter,
        url: URL,
        connectionFactory: WebSocketConnectionFactory = DefaultWebSocketConnectionFactory()
    ) {
        self.router = router
        self.url = url
        self.connectionFactory = connectionFactory
        self.logger = Logger(label: "mcp-websocket")
        jsonEncoder.outputFormatting = .sortedKeys
    }

    /// Create adapter with single server and relay URL
    ///
    /// - Parameters:
    ///   - server: MCP server to expose via WebSocket relay
    ///   - url: WebSocket relay URL
    ///   - connectionFactory: Factory for creating WebSocket connections
    public convenience init(
        server: Server,
        url: URL,
        connectionFactory: WebSocketConnectionFactory = DefaultWebSocketConnectionFactory()
    ) {
        let router = WebSocketRouter().addServer(server: server)
        self.init(router: router, url: url, connectionFactory: connectionFactory)
    }

    /// Add pre-request middleware
    @discardableResult
    public func usePreRequestMiddleware<M: PreRequestMiddleware>(_ middleware: M) -> WebSocketAdapter
        where M.Context == WebSocketMCPContext, M.MiddlewareEnvelope == TransportEnvelope {
        preRequestMiddlewareChain.use(middleware)
        return self
    }

    /// Add post-response middleware
    @discardableResult
    public func usePostResponseMiddleware<M: PostResponseMiddleware>(_ middleware: M) -> WebSocketAdapter
        where M.Context == WebSocketMCPContext, M.Response == TransportResponse {
        postResponseMiddlewareChain.use(middleware.eraseToAnyPostResponseMiddleware())
        return self
    }

    /// Start the WebSocket adapter
    ///
    /// Connects to the relay and begins processing MCP requests. Automatically
    /// reconnects with exponential backoff if the connection drops.
    ///
    /// - Parameters:
    ///   - sessionId: Session identifier (shared with MCP client out-of-band)
    ///   - token: JWT authentication token for the relay
    ///   - mcpPath: Optional MCP route path (default: "/")
    /// - Throws: If connection fails after all retry attempts
    public func run(sessionId: String, token: String, mcpPath: String = "/") async throws {
        var attempt = 0

        while true {
            do {
                try Task.checkCancellation()
                let connection = try makeConnection(sessionId: sessionId, token: token)
                attempt = 0  // Reset on successful connect
                logger.info("Connected to relay", metadata: ["sessionId": "\(sessionId)"])

                try await runSession(
                    connection: connection,
                    sessionId: sessionId,
                    mcpPath: mcpPath
                )
            } catch is CancellationError {
                logger.info("Adapter cancelled")
                throw CancellationError()
            } catch {
                attempt += 1
                if maxReconnectAttempts > 0 && attempt >= maxReconnectAttempts {
                    logger.error("Max reconnection attempts reached", metadata: ["attempts": "\(attempt)"])
                    throw error
                }

                let delay = min(baseReconnectDelay * pow(2, Double(attempt - 1)), maxReconnectDelay)
                logger.warning("Connection lost, reconnecting", metadata: [
                    "attempt": "\(attempt)",
                    "delay": "\(delay)s",
                    "error": "\(error)"
                ])
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Run a single connected session until disconnection
    func runSession(
        connection: WebSocketConnection,
        sessionId: String,
        mcpPath: String
    ) async throws {
        let context = WebSocketMCPContext(
            sessionId: sessionId,
            routePath: mcpPath,
            relayURL: url
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Ping keep-alive task
            group.addTask { [pingInterval] in
                while true {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: UInt64(pingInterval * 1_000_000_000))
                    try await connection.sendPing()
                }
            }

            // Receive loop
            group.addTask { [self] in
                try await self.receiveLoop(connection: connection, context: context, mcpPath: mcpPath)
            }

            // Wait for either task to finish (which means disconnect)
            try await group.next()
            group.cancelAll()
        }
    }

    /// Main receive loop — reads messages from WebSocket and processes them
    private func receiveLoop(
        connection: WebSocketConnection,
        context: WebSocketMCPContext,
        mcpPath: String
    ) async throws {
        while true {
            try Task.checkCancellation()

            let wsMessage = try await connection.receive()
            let messageData: Data
            switch wsMessage {
            case .text(let string):
                guard let data = string.data(using: .utf8) else { continue }
                messageData = data
            case .data(let data):
                messageData = data
            }

            let relayMessage: RelayMessage
            do {
                relayMessage = try jsonDecoder.decode(RelayMessage.self, from: messageData)
            } catch {
                logger.warning("Failed to decode relay message", metadata: ["error": "\(error)"])
                continue
            }

            switch relayMessage {
            case .request(let relayRequest):
                // Process MCP request and send response
                do {
                    let responseData = try await processRequest(
                        relayRequest: relayRequest,
                        context: context,
                        mcpPath: mcpPath
                    )

                    let relayResponse = RelayResponse(
                        correlationId: relayRequest.correlationId,
                        body: responseData
                    )
                    let responseMessage = RelayMessage.response(relayResponse)
                    let encoded = try jsonEncoder.encode(responseMessage)
                    guard let responseString = String(data: encoded, encoding: .utf8) else {
                        throw WebSocketAdapterError.encodingFailed
                    }
                    try await connection.send(.text(responseString))
                } catch {
                    logger.error("Failed to process request", metadata: [
                        "correlationId": "\(relayRequest.correlationId)",
                        "error": "\(error)"
                    ])
                    // Send error response back
                    let errorResponse = try makeErrorResponse(
                        correlationId: relayRequest.correlationId,
                        error: error
                    )
                    let encoded = try jsonEncoder.encode(errorResponse)
                    if let errorString = String(data: encoded, encoding: .utf8) {
                        try await connection.send(.text(errorString))
                    }
                }

            case .control(let control):
                switch control {
                case .ping:
                    // Respond with pong
                    let pong = RelayMessage.control(.pong)
                    let encoded = try jsonEncoder.encode(pong)
                    if let pongString = String(data: encoded, encoding: .utf8) {
                        try await connection.send(.text(pongString))
                    }
                case .pong:
                    break // Expected response to our pings
                case .sessionEstablished(let sessionId):
                    logger.info("Session established", metadata: ["sessionId": "\(sessionId)"])
                case .error(let message):
                    logger.error("Relay error", metadata: ["message": "\(message)"])
                }

            case .response:
                // iOS app shouldn't receive responses — log and ignore
                logger.warning("Unexpected response message received")
            }
        }
    }

    /// Process a single MCP request from the relay
    func processRequest(
        relayRequest: RelayRequest,
        context: WebSocketMCPContext,
        mcpPath: String
    ) async throws -> Data {
        let startTime = Date()

        // Decode the MCP request from the relay body
        let mcpRequest = try jsonDecoder.decode(Request.self, from: relayRequest.body)

        // Build transport envelope
        var envelope = TransportEnvelope(
            mcpRequest: mcpRequest,
            routePath: mcpPath,
            metadata: [
                "sessionId": context.sessionId,
                "correlationId": relayRequest.correlationId
            ]
        )

        // Run global pre-request middleware
        let middlewareResult = try await preRequestMiddlewareChain.execute(
            context: context,
            envelope: envelope
        )

        switch middlewareResult {
        case .reject(let error):
            return try formatError(error, requestId: mcpRequest.id)

        case .accept(let updatedEnvelope), .passthrough(let updatedEnvelope):
            envelope = updatedEnvelope
        }

        // Route through MCP router
        var response = try await router.route(
            envelope,
            context: context,
            logger: logger
        )

        // Run post-response middleware
        let endTime = Date()
        let timing = RequestTiming(startTime: startTime, endTime: endTime)
        let responseEnvelope = ResponseEnvelope(request: envelope, response: response, timing: timing)
        response = try await postResponseMiddlewareChain.execute(
            context: context,
            envelope: responseEnvelope
        )

        // Encode the MCP response
        return try jsonEncoder.encode(response.data)
    }

    // MARK: - Private Helpers

    private func makeConnection(sessionId: String, token: String) throws -> WebSocketConnection {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "sessionId", value: sessionId))
        components?.queryItems = queryItems

        guard let wsURL = components?.url else {
            throw WebSocketAdapterError.connectionFailed("Invalid relay URL")
        }

        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return connectionFactory.makeConnection(request: request)
    }

    private func formatError(_ error: Error, requestId: RequestId?) throws -> Data {
        let mcpError: MCPError
        if let existingError = error as? MCPError {
            mcpError = existingError
        } else {
            mcpError = MCPError(code: .internalError, message: error.localizedDescription)
        }

        let errorResponse = Response<String>.fromError(id: requestId, error: mcpError)
        return try jsonEncoder.encode(errorResponse)
    }

    private func makeErrorResponse(correlationId: String, error: Error) throws -> RelayMessage {
        let errorData = try formatError(error, requestId: nil)
        let relayResponse = RelayResponse(correlationId: correlationId, body: errorData)
        return .response(relayResponse)
    }
}

// MARK: - Type Alias

/// Router for WebSocket transport with WebSocketMCPContext
public typealias WebSocketRouter = Router<WebSocketMCPContext>
