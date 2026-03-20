import Testing
import Foundation
@testable import MCPWebSocketRelay
@testable import MCPWebSocketShared

@Suite("WebSocket Relay Handler Tests")
struct WebSocketRelayHandlerTests {

    // MARK: - $connect Tests

    @Test("Connect with valid JWT stores connection")
    func testConnectValidJWT() async throws {
        let store = MockRelayStore()
        let handler = WebSocketRelayHandler(
            store: store,
            authenticator: MockWebSocketAuthenticator()
        )

        let result = try await handler.handleConnect(
            connectionId: "conn-123",
            headers: ["Authorization": "Bearer valid-jwt"],
            queryParams: ["sessionId": "session-abc"]
        )

        #expect(result.statusCode == 200)

        // Verify connection was stored
        let connections = await store.storedConnections
        #expect(connections["conn-123"] != nil)
        #expect(connections["conn-123"]?.sessionId == "session-abc")
        #expect(connections["conn-123"]?.principalId == "test-user")
    }

    @Test("Connect with invalid JWT returns 401")
    func testConnectInvalidJWT() async throws {
        let store = MockRelayStore()
        let handler = WebSocketRelayHandler(
            store: store,
            authenticator: MockWebSocketAuthenticator()
        )

        let result = try await handler.handleConnect(
            connectionId: "conn-123",
            headers: ["Authorization": "Bearer bad-token"],
            queryParams: ["sessionId": "session-abc"]
        )

        #expect(result.statusCode == 401)

        // Verify no connection was stored
        let connections = await store.storedConnections
        #expect(connections.isEmpty)
    }

    @Test("Connect without Authorization header returns 401")
    func testConnectMissingAuth() async throws {
        let store = MockRelayStore()
        let handler = WebSocketRelayHandler(
            store: store,
            authenticator: MockWebSocketAuthenticator()
        )

        let result = try await handler.handleConnect(
            connectionId: "conn-123",
            headers: [:],
            queryParams: ["sessionId": "session-abc"]
        )

        #expect(result.statusCode == 401)
    }

    @Test("Connect without sessionId returns 401")
    func testConnectMissingSessionId() async throws {
        let store = MockRelayStore()
        let handler = WebSocketRelayHandler(
            store: store,
            authenticator: MockWebSocketAuthenticator()
        )

        let result = try await handler.handleConnect(
            connectionId: "conn-123",
            headers: ["Authorization": "Bearer valid-jwt"],
            queryParams: [:]
        )

        #expect(result.statusCode == 401)
    }

    // MARK: - $disconnect Tests

    @Test("Disconnect removes connection")
    func testDisconnect() async throws {
        let store = MockRelayStore()
        let handler = WebSocketRelayHandler(
            store: store,
            authenticator: MockWebSocketAuthenticator()
        )

        // First connect
        _ = try await handler.handleConnect(
            connectionId: "conn-123",
            headers: ["Authorization": "Bearer valid-jwt"],
            queryParams: ["sessionId": "session-abc"]
        )

        // Verify connected
        var connections = await store.storedConnections
        #expect(connections.count == 1)

        // Disconnect
        let result = try await handler.handleDisconnect(connectionId: "conn-123")
        #expect(result.statusCode == 200)

        // Verify removed
        connections = await store.storedConnections
        #expect(connections.isEmpty)
    }

    // MARK: - $default Tests

    @Test("Default handler stores relay response")
    func testDefaultStoresResponse() async throws {
        let store = MockRelayStore()
        let handler = WebSocketRelayHandler(
            store: store,
            authenticator: MockWebSocketAuthenticator()
        )

        // First store a pending request
        try await store.storeRequest(
            connectionId: "conn-123",
            correlationId: "corr-1",
            body: Data("request".utf8)
        )

        // Create a relay response message
        let relayResponse = RelayResponse(correlationId: "corr-1", body: Data("response-body".utf8))
        let message = RelayMessage.response(relayResponse)
        let messageData = try JSONEncoder().encode(message)
        let messageString = String(data: messageData, encoding: .utf8)!

        let result = try await handler.handleDefault(
            connectionId: "conn-123",
            body: messageString
        )

        #expect(result.statusCode == 200)

        // Verify response was stored
        let responseData = try await store.getResponse(
            connectionId: "conn-123",
            correlationId: "corr-1"
        )
        #expect(responseData != nil)
        #expect(String(data: responseData!, encoding: .utf8) == "response-body")
    }

    @Test("Default handler handles invalid message gracefully")
    func testDefaultInvalidMessage() async throws {
        let store = MockRelayStore()
        let handler = WebSocketRelayHandler(
            store: store,
            authenticator: MockWebSocketAuthenticator()
        )

        let result = try await handler.handleDefault(
            connectionId: "conn-123",
            body: "{ invalid json }"
        )

        #expect(result.statusCode == 500)
    }
}
