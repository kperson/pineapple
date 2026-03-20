import Foundation
import MCP

// MARK: - WebSocket Context for Middleware

/// WebSocket-specific context for middleware
///
/// Provides middleware with access to WebSocket relay information
/// when running as an iOS MCP client connected via WebSocket relay.
///
/// ## Available Information
///
/// - **sessionId**: The session identifier for this relay connection
/// - **routePath**: Resolved MCP route path
/// - **relayURL**: The WebSocket relay URL this adapter is connected to
/// - **connectionId**: The API Gateway WebSocket connection ID (if known)
///
/// ## Example Usage
///
/// ```swift
/// let middleware = PreRequestMiddlewareHelpers.from {
///     (context: WebSocketMCPContext, envelope: TransportEnvelope) in
///     return .accept(metadata: [
///         "sessionId": context.sessionId,
///         "relayURL": context.relayURL.absoluteString
///     ])
/// }
/// ```
public struct WebSocketMCPContext: Sendable {

    /// Session identifier for this relay connection
    public let sessionId: String

    /// Resolved MCP route path
    public let routePath: String

    /// The WebSocket relay URL
    public let relayURL: URL

    /// API Gateway WebSocket connection ID (populated after connection)
    public let connectionId: String?

    public init(sessionId: String, routePath: String, relayURL: URL, connectionId: String? = nil) {
        self.sessionId = sessionId
        self.routePath = routePath
        self.relayURL = relayURL
        self.connectionId = connectionId
    }
}
