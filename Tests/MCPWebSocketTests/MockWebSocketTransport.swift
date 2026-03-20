import Foundation
@testable import MCPWebSocket
import MCPWebSocketShared

/// Mock WebSocket connection for testing
///
/// Simulates a WebSocket by queuing incoming messages and capturing outgoing ones.
actor MockWebSocketConnection: WebSocketConnection {
    private var incomingMessages: [WebSocketMessageType] = []
    private var _sentMessages: [WebSocketMessageType] = []
    private var _pingCount: Int = 0
    private var _isClosed: Bool = false
    private var receiveError: Error?

    /// Messages sent by the adapter
    var sentMessages: [WebSocketMessageType] {
        _sentMessages
    }

    /// Number of pings sent
    var pingCount: Int {
        _pingCount
    }

    var isClosed: Bool {
        _isClosed
    }

    init(incomingMessages: [WebSocketMessageType] = []) {
        self.incomingMessages = incomingMessages
    }

    /// Queue a message to be received by the adapter
    func queueIncoming(_ message: WebSocketMessageType) {
        incomingMessages.append(message)
    }

    /// Set an error to be thrown on next receive
    func setReceiveError(_ error: Error) {
        self.receiveError = error
    }

    // MARK: - WebSocketConnection conformance

    nonisolated func send(_ message: WebSocketMessageType) async throws {
        await _send(message)
    }

    private func _send(_ message: WebSocketMessageType) {
        _sentMessages.append(message)
    }

    nonisolated func receive() async throws -> WebSocketMessageType {
        return try await _receive()
    }

    private func _receive() throws -> WebSocketMessageType {
        if let error = receiveError {
            receiveError = nil
            throw error
        }
        guard !incomingMessages.isEmpty else {
            // Simulate disconnect
            throw WebSocketAdapterError.disconnected
        }
        return incomingMessages.removeFirst()
    }

    nonisolated func sendPing() async throws {
        await _sendPing()
    }

    private func _sendPing() {
        _pingCount += 1
    }

    nonisolated func close(code: URLSessionWebSocketTask.CloseCode, reason: Data?) async {
        await _close()
    }

    private func _close() {
        _isClosed = true
    }
}

/// Mock connection factory that returns pre-configured mock connections
struct MockWebSocketConnectionFactory: WebSocketConnectionFactory {
    let connection: MockWebSocketConnection

    func makeConnection(request: URLRequest) -> WebSocketConnection {
        return connection
    }
}
