import Testing
import Foundation
@testable import MCP
@testable import MCPWebSocket
@testable import MCPWebSocketShared

@Suite("WebSocket Adapter Tests")
struct WebSocketAdapterTests {

    // MARK: - Helpers

    /// Create a RelayMessage containing a JSON-RPC MCP request
    func makeRelayRequestMessage(method: String, id: String = "1", params: [String: Any]? = nil) throws -> String {
        var request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "id": id
        ]
        if let params = params {
            request["params"] = params
        }
        let requestData = try JSONSerialization.data(withJSONObject: request)

        let relayRequest = RelayRequest(correlationId: "corr-\(id)", body: requestData)
        let message = RelayMessage.request(relayRequest)
        let encoded = try JSONEncoder().encode(message)
        return String(data: encoded, encoding: .utf8)!
    }

    /// Parse a sent WebSocket message as a RelayMessage
    func parseRelayMessage(_ message: WebSocketMessageType) throws -> RelayMessage {
        let data: Data
        switch message {
        case .text(let string):
            data = string.data(using: .utf8)!
        case .data(let d):
            data = d
        }
        return try JSONDecoder().decode(RelayMessage.self, from: data)
    }

    // MARK: - Tests

    @Test("Processes MCP initialize request and sends response")
    func testProcessesRequest() async throws {
        let server = Server()

        // Create mock connection with an initialize request
        let initMessage = try makeRelayRequestMessage(method: "initialize", id: "1")

        let mockConnection = MockWebSocketConnection(incomingMessages: [
            .text(initMessage)
        ])

        let factory = MockWebSocketConnectionFactory(connection: mockConnection)
        let url = URL(string: "wss://relay.example.com")!

        let adapter = WebSocketAdapter(server: server, url: url, connectionFactory: factory)
        adapter.maxReconnectAttempts = 1

        // Run the adapter (will disconnect after processing messages)
        do {
            try await adapter.run(sessionId: "test-session", token: "test-token")
        } catch {
            // Expected — will disconnect after messages are consumed
        }

        // Verify response was sent
        let sent = await mockConnection.sentMessages
        #expect(sent.count >= 1, "Should have sent at least 1 response")

        // Check response is for initialize
        let firstRelay = try parseRelayMessage(sent[0])
        if case .response(let response) = firstRelay {
            #expect(response.correlationId == "corr-1")
            // Parse the MCP response body
            let json = try JSONSerialization.jsonObject(with: response.body) as! [String: Any]
            #expect(json["result"] != nil, "Initialize should return a result")
        } else {
            Issue.record("Expected response message")
        }
    }

    @Test("Responds to control ping with pong")
    func testPingPong() async throws {
        let server = Server()

        // Queue a ping control message
        let pingMessage = RelayMessage.control(.ping)
        let encoded = try JSONEncoder().encode(pingMessage)
        let pingString = String(data: encoded, encoding: .utf8)!

        let mockConnection = MockWebSocketConnection(incomingMessages: [
            .text(pingString)
        ])

        let factory = MockWebSocketConnectionFactory(connection: mockConnection)
        let url = URL(string: "wss://relay.example.com")!

        let adapter = WebSocketAdapter(server: server, url: url, connectionFactory: factory)
        adapter.maxReconnectAttempts = 1

        do {
            try await adapter.run(sessionId: "test-session", token: "test-token")
        } catch {
            // Expected disconnect
        }

        // Verify pong was sent
        let sent = await mockConnection.sentMessages
        #expect(sent.count >= 1, "Should have sent pong")

        let relayMsg = try parseRelayMessage(sent[0])
        if case .control(.pong) = relayMsg {
            // Good
        } else {
            Issue.record("Expected pong control message, got \(relayMsg)")
        }
    }

    @Test("Includes sessionId in connection URL")
    func testConnectionURL() async throws {
        let capturedRequest = CapturedRequest()

        struct CapturingFactory: WebSocketConnectionFactory {
            let connection: MockWebSocketConnection
            let captured: CapturedRequest

            func makeConnection(request: URLRequest) -> WebSocketConnection {
                Task { await captured.set(request) }
                return connection
            }
        }

        let mockConnection = MockWebSocketConnection()
        let factory = CapturingFactory(connection: mockConnection, captured: capturedRequest)

        let url = URL(string: "wss://relay.example.com/ws")!
        let adapter = WebSocketAdapter(
            server: Server(),
            url: url,
            connectionFactory: factory
        )
        adapter.maxReconnectAttempts = 1

        do {
            try await adapter.run(sessionId: "my-session-123", token: "jwt-token-abc")
        } catch {
            // Expected
        }

        // Verify URL contains sessionId
        let req = await capturedRequest.value
        let requestURL = req?.url?.absoluteString ?? ""
        #expect(requestURL.contains("sessionId=my-session-123"))

        // Verify Authorization header
        let authHeader = req?.value(forHTTPHeaderField: "Authorization")
        #expect(authHeader == "Bearer jwt-token-abc")
    }

    @Test("Handles malformed relay messages gracefully")
    func testMalformedMessage() async throws {
        let server = Server()

        // Queue a malformed message followed by a valid one
        let initMessage = try makeRelayRequestMessage(method: "initialize", id: "1")
        let mockConnection = MockWebSocketConnection(incomingMessages: [
            .text("{ not valid relay message }"),
            .text(initMessage)
        ])

        let factory = MockWebSocketConnectionFactory(connection: mockConnection)
        let url = URL(string: "wss://relay.example.com")!

        let adapter = WebSocketAdapter(server: server, url: url, connectionFactory: factory)
        adapter.maxReconnectAttempts = 1

        do {
            try await adapter.run(sessionId: "test", token: "token")
        } catch {
            // Expected disconnect
        }

        // Should still process the valid message
        let sent = await mockConnection.sentMessages
        #expect(sent.count >= 1, "Should have processed the valid message after skipping malformed one")
    }

    @Test("Middleware rejection returns error response")
    func testMiddlewareRejection() async throws {
        let server = Server()

        let initMessage = try makeRelayRequestMessage(method: "initialize", id: "1")
        let mockConnection = MockWebSocketConnection(incomingMessages: [
            .text(initMessage)
        ])

        let factory = MockWebSocketConnectionFactory(connection: mockConnection)
        let url = URL(string: "wss://relay.example.com")!

        let adapter = WebSocketAdapter(server: server, url: url, connectionFactory: factory)
        adapter.maxReconnectAttempts = 1

        // Add rejecting middleware
        let rejectMiddleware = PreRequestMiddlewareHelpers.from {
            (context: WebSocketMCPContext, envelope: TransportEnvelope) in
            return .reject(MCPError(code: .invalidRequest, message: "Rejected by middleware"))
        }
        adapter.usePreRequestMiddleware(rejectMiddleware)

        do {
            try await adapter.run(sessionId: "test", token: "token")
        } catch {
            // Expected disconnect
        }

        // Verify error response was sent
        let sent = await mockConnection.sentMessages
        #expect(sent.count >= 1)

        let relayMsg = try parseRelayMessage(sent[0])
        if case .response(let response) = relayMsg {
            let json = try JSONSerialization.jsonObject(with: response.body) as! [String: Any]
            let error = json["error"] as? [String: Any]
            let message = error?["message"] as? String
            #expect(message == "Rejected by middleware")
        } else {
            Issue.record("Expected response with error")
        }
    }
}

// MARK: - Helper Types

/// Thread-safe captured URL request for testing
actor CapturedRequest {
    var value: URLRequest?

    func set(_ request: URLRequest) {
        value = request
    }
}
