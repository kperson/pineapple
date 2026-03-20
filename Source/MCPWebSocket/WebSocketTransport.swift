import Foundation

// MARK: - WebSocket Transport Abstraction

/// Represents a WebSocket message type
public enum WebSocketMessageType: Sendable {
    case text(String)
    case data(Data)
}

/// Protocol abstracting a WebSocket connection for testability
///
/// Production code uses `URLSessionWebSocketConnection` backed by `URLSessionWebSocketTask`.
/// Tests inject a mock implementation to simulate relay communication without a network.
public protocol WebSocketConnection: Sendable {
    /// Send a text message over the WebSocket
    func send(_ message: WebSocketMessageType) async throws

    /// Receive the next message from the WebSocket
    func receive() async throws -> WebSocketMessageType

    /// Send a ping to keep the connection alive
    func sendPing() async throws

    /// Close the WebSocket connection
    func close(code: URLSessionWebSocketTask.CloseCode, reason: Data?) async
}

/// Production WebSocket connection using URLSessionWebSocketTask
///
/// Wraps Apple's `URLSessionWebSocketTask` to conform to `WebSocketConnection`.
/// Used by `WebSocketAdapter` to connect to the relay WebSocket endpoint.
///
/// ## Example
///
/// ```swift
/// let url = URL(string: "wss://relay.example.com?sessionId=abc-123")!
/// var request = URLRequest(url: url)
/// request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
///
/// let connection = URLSessionWebSocketConnection(request: request)
/// try await connection.send(.text("hello"))
/// ```
public final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {

    private let task: URLSessionWebSocketTask

    /// Create a WebSocket connection from a URL request
    ///
    /// The connection is started immediately. The request should include
    /// any required headers (e.g., Authorization).
    ///
    /// - Parameter request: URL request with WebSocket URL and headers
    public init(request: URLRequest) {
        let session = URLSession(configuration: .default)
        self.task = session.webSocketTask(with: request)
        task.resume()
    }

    public func send(_ message: WebSocketMessageType) async throws {
        let wsMessage: URLSessionWebSocketTask.Message
        switch message {
        case .text(let string):
            wsMessage = .string(string)
        case .data(let data):
            wsMessage = .data(data)
        }
        try await task.send(wsMessage)
    }

    public func receive() async throws -> WebSocketMessageType {
        let message = try await task.receive()
        switch message {
        case .string(let string):
            return .text(string)
        case .data(let data):
            return .data(data)
        @unknown default:
            throw WebSocketAdapterError.unsupportedMessageType
        }
    }

    public func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func close(code: URLSessionWebSocketTask.CloseCode, reason: Data?) async {
        task.cancel(with: code, reason: reason)
    }
}

/// Factory for creating WebSocket connections (enables dependency injection)
public protocol WebSocketConnectionFactory: Sendable {
    func makeConnection(request: URLRequest) -> WebSocketConnection
}

/// Default factory using URLSessionWebSocketConnection
public struct DefaultWebSocketConnectionFactory: WebSocketConnectionFactory {
    public init() {}

    public func makeConnection(request: URLRequest) -> WebSocketConnection {
        URLSessionWebSocketConnection(request: request)
    }
}
