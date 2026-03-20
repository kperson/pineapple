import Foundation
import MCPWebSocketShared
import MCP
import Logging

// MARK: - WebSocket Management API Protocol

/// Protocol for sending messages to WebSocket connections via API Gateway Management API
///
/// Abstracts the `PostToConnection` API call for testability.
public protocol WebSocketManagementAPI: Sendable {
    /// Send a message to a connected WebSocket client
    ///
    /// - Parameters:
    ///   - connectionId: The target WebSocket connection ID
    ///   - data: Message payload to send
    func postToConnection(connectionId: String, data: Data) async throws
}

// MARK: - HTTP Relay Handler

/// Handles HTTP POST requests from MCP clients
///
/// This handler runs in the HTTP Lambda and:
/// 1. Validates the API key via `HTTPClientAuthenticator`
/// 2. Looks up the iOS app's WebSocket connection by sessionId
/// 3. Stores the request in DynamoDB
/// 4. Forwards the MCP request to the iOS app via API Gateway Management API
/// 5. Polls DynamoDB for the response (up to timeout)
/// 6. Returns the response to the MCP client
public struct HTTPRelayHandler: Sendable {

    private let store: RelayStore
    private let authenticator: HTTPClientAuthenticator
    private let managementAPI: WebSocketManagementAPI
    private let config: RelayConfig
    private let logger: Logger

    public init(
        store: RelayStore,
        authenticator: HTTPClientAuthenticator,
        managementAPI: WebSocketManagementAPI,
        config: RelayConfig,
        logger: Logger = Logger(label: "http-relay")
    ) {
        self.store = store
        self.authenticator = authenticator
        self.managementAPI = managementAPI
        self.config = config
        self.logger = logger
    }

    /// Result of handling an HTTP relay request
    public struct HTTPHandlerResult: Sendable {
        public let statusCode: Int
        public let body: Data?
        public let contentType: String

        public init(statusCode: Int, body: Data? = nil, contentType: String = "application/json") {
            self.statusCode = statusCode
            self.body = body
            self.contentType = contentType
        }

        public static func unauthorized(_ message: String = "Unauthorized") -> HTTPHandlerResult {
            let body = #"{"error":{"code":-32600,"message":"\#(message)"}}"#.data(using: .utf8)
            return HTTPHandlerResult(statusCode: 401, body: body)
        }

        public static func notFound(_ message: String = "Session not found") -> HTTPHandlerResult {
            let body = #"{"error":{"code":-32600,"message":"\#(message)"}}"#.data(using: .utf8)
            return HTTPHandlerResult(statusCode: 404, body: body)
        }

        public static func timeout() -> HTTPHandlerResult {
            let body = #"{"error":{"code":-32603,"message":"Request timed out waiting for response"}}"#.data(using: .utf8)
            return HTTPHandlerResult(statusCode: 504, body: body)
        }

        public static func serverError(_ message: String) -> HTTPHandlerResult {
            let body = #"{"error":{"code":-32603,"message":"\#(message)"}}"#.data(using: .utf8)
            return HTTPHandlerResult(statusCode: 500, body: body)
        }
    }

    /// Handle an MCP client HTTP POST request
    ///
    /// - Parameters:
    ///   - sessionId: Target session ID (from URL path)
    ///   - apiKey: API key from X-API-Key header
    ///   - body: Raw MCP JSON-RPC request body
    /// - Returns: HTTP handler result with MCP response
    public func handleRequest(
        sessionId: String,
        apiKey: String?,
        body: Data
    ) async throws -> HTTPHandlerResult {
        // Validate API key
        guard let apiKey = apiKey else {
            return .unauthorized("Missing X-API-Key header")
        }

        let isValid: Bool
        do {
            isValid = try await authenticator.validate(apiKey: apiKey)
        } catch {
            logger.error("API key validation error", metadata: ["error": "\(error)"])
            return .unauthorized("Authentication failed")
        }

        guard isValid else {
            return .unauthorized("Invalid API key")
        }

        // Find the WebSocket connection for this session
        guard let connectionId = try await store.findConnectionBySession(sessionId: sessionId) else {
            logger.warning("No connection found for session", metadata: ["sessionId": "\(sessionId)"])
            return .notFound("No iOS app connected for session: \(sessionId)")
        }

        // Generate correlation ID
        let correlationId = UUID().uuidString

        // Store the pending request
        try await store.storeRequest(
            connectionId: connectionId,
            correlationId: correlationId,
            body: body
        )

        // Forward to iOS app via WebSocket
        let relayRequest = RelayRequest(correlationId: correlationId, body: body)
        let relayMessage = RelayMessage.request(relayRequest)
        let messageData = try JSONEncoder().encode(relayMessage)

        do {
            try await managementAPI.postToConnection(connectionId: connectionId, data: messageData)
        } catch {
            logger.error("Failed to send to iOS app", metadata: [
                "connectionId": "\(connectionId)",
                "error": "\(error)"
            ])
            return .serverError("iOS app is not reachable")
        }

        // Poll for response
        let deadline = Date().addingTimeInterval(config.timeoutSeconds)
        while Date() < deadline {
            try Task.checkCancellation()

            if let responseBody = try await store.getResponse(
                connectionId: connectionId,
                correlationId: correlationId
            ) {
                logger.debug("Response received", metadata: ["correlationId": "\(correlationId)"])
                return HTTPHandlerResult(statusCode: 200, body: responseBody)
            }

            try await Task.sleep(nanoseconds: UInt64(config.pollIntervalSeconds * 1_000_000_000))
        }

        logger.warning("Request timed out", metadata: [
            "correlationId": "\(correlationId)",
            "sessionId": "\(sessionId)"
        ])
        return .timeout()
    }
}
