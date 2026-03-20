import Foundation
import MCPWebSocketShared
import MCP
import Logging

// MARK: - WebSocket Relay Handler

/// Handles WebSocket API Gateway events ($connect, $disconnect, $default)
///
/// This handler runs in the WebSocket Lambda and manages:
/// - `$connect`: Validates JWT via `WebSocketAuthenticator`, stores connection + sessionId
/// - `$disconnect`: Removes connection from DynamoDB
/// - `$default`: Parses `RelayResponse` from iOS app, writes response to DynamoDB
public struct WebSocketRelayHandler: Sendable {

    private let store: RelayStore
    private let authenticator: WebSocketAuthenticator
    private let logger: Logger

    public init(
        store: RelayStore,
        authenticator: WebSocketAuthenticator,
        logger: Logger = Logger(label: "ws-relay")
    ) {
        self.store = store
        self.authenticator = authenticator
        self.logger = logger
    }

    /// Result of handling a WebSocket event
    public struct WebSocketHandlerResult: Sendable {
        public let statusCode: Int
        public let body: String?

        public init(statusCode: Int, body: String? = nil) {
            self.statusCode = statusCode
            self.body = body
        }

        public static let ok = WebSocketHandlerResult(statusCode: 200)
        public static func unauthorized(_ message: String = "Unauthorized") -> WebSocketHandlerResult {
            WebSocketHandlerResult(statusCode: 401, body: message)
        }
        public static func error(_ message: String) -> WebSocketHandlerResult {
            WebSocketHandlerResult(statusCode: 500, body: message)
        }
    }

    /// Handle a $connect event
    ///
    /// Validates the JWT from the Authorization header and stores the connection.
    ///
    /// - Parameters:
    ///   - connectionId: API Gateway WebSocket connection ID
    ///   - headers: Request headers (expects "Authorization: Bearer <token>")
    ///   - queryParams: Query parameters (expects "sessionId")
    /// - Returns: Handler result (200 = accept, 401 = reject)
    public func handleConnect(
        connectionId: String,
        headers: [String: String],
        queryParams: [String: String]
    ) async throws -> WebSocketHandlerResult {
        // Extract JWT from Authorization header
        guard let authHeader = headers["Authorization"] ?? headers["authorization"],
              authHeader.hasPrefix("Bearer ") else {
            logger.warning("Missing or invalid Authorization header", metadata: ["connectionId": "\(connectionId)"])
            return .unauthorized("Missing Authorization header")
        }
        let token = String(authHeader.dropFirst("Bearer ".count))

        // Extract sessionId from query parameters
        guard let sessionId = queryParams["sessionId"], !sessionId.isEmpty else {
            logger.warning("Missing sessionId query parameter", metadata: ["connectionId": "\(connectionId)"])
            return .unauthorized("Missing sessionId")
        }

        // Validate JWT
        let authResult: AuthResult
        do {
            authResult = try await authenticator.validate(token: token)
        } catch {
            logger.error("Auth validation error", metadata: ["error": "\(error)"])
            return .unauthorized("Authentication failed")
        }

        guard authResult.isValid else {
            logger.warning("Invalid JWT", metadata: ["connectionId": "\(connectionId)"])
            return .unauthorized("Invalid token")
        }

        // Store connection
        try await store.storeConnection(
            connectionId: connectionId,
            sessionId: sessionId,
            principalId: authResult.principalId
        )

        logger.info("WebSocket connected", metadata: [
            "connectionId": "\(connectionId)",
            "sessionId": "\(sessionId)",
            "principalId": "\(authResult.principalId ?? "unknown")"
        ])

        return .ok
    }

    /// Handle a $disconnect event
    ///
    /// Removes the connection record from DynamoDB.
    ///
    /// - Parameter connectionId: API Gateway WebSocket connection ID
    public func handleDisconnect(connectionId: String) async throws -> WebSocketHandlerResult {
        try await store.removeConnection(connectionId: connectionId)
        logger.info("WebSocket disconnected", metadata: ["connectionId": "\(connectionId)"])
        return .ok
    }

    /// Handle a $default event (message from iOS app)
    ///
    /// Parses the message as a `RelayMessage` and processes it.
    /// For `.response` messages, writes the response to DynamoDB
    /// so the HTTP Lambda can pick it up.
    ///
    /// - Parameters:
    ///   - connectionId: API Gateway WebSocket connection ID
    ///   - body: Raw message body from WebSocket
    public func handleDefault(connectionId: String, body: String) async throws -> WebSocketHandlerResult {
        guard let data = body.data(using: .utf8) else {
            return .error("Invalid message encoding")
        }

        let relayMessage: RelayMessage
        do {
            relayMessage = try JSONDecoder().decode(RelayMessage.self, from: data)
        } catch {
            logger.warning("Failed to decode relay message", metadata: [
                "connectionId": "\(connectionId)",
                "error": "\(error)"
            ])
            return .error("Invalid message format")
        }

        switch relayMessage {
        case .response(let response):
            try await store.storeResponse(
                connectionId: connectionId,
                correlationId: response.correlationId,
                body: response.body
            )
            logger.debug("Response stored", metadata: [
                "connectionId": "\(connectionId)",
                "correlationId": "\(response.correlationId)"
            ])

        case .control(let control):
            switch control {
            case .ping:
                // iOS app is pinging — no action needed, API Gateway handles keep-alive
                break
            case .pong, .sessionEstablished, .error:
                break
            }

        case .request:
            // Unexpected — iOS app shouldn't send requests through relay
            logger.warning("Unexpected request from iOS app", metadata: ["connectionId": "\(connectionId)"])
        }

        return .ok
    }
}
