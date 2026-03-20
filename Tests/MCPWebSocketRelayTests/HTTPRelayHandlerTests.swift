import Testing
import Foundation
@testable import MCPWebSocketRelay
@testable import MCPWebSocketShared

@Suite("HTTP Relay Handler Tests")
struct HTTPRelayHandlerTests {

    func makeConfig() -> RelayConfig {
        RelayConfig(
            tableName: "test-table",
            wsManagementEndpoint: "https://test.example.com",
            timeoutSeconds: 2,
            pollIntervalSeconds: 0.1
        )
    }

    // MARK: - Auth Tests

    @Test("Missing API key returns 401")
    func testMissingAPIKey() async throws {
        let store = MockRelayStore()
        let mgmt = MockWebSocketManagementAPI()
        let handler = HTTPRelayHandler(
            store: store,
            authenticator: MockHTTPAuthenticator(),
            managementAPI: mgmt,
            config: makeConfig()
        )

        let result = try await handler.handleRequest(
            sessionId: "session-1",
            apiKey: nil,
            body: Data("{}".utf8)
        )

        #expect(result.statusCode == 401)
    }

    @Test("Invalid API key returns 401")
    func testInvalidAPIKey() async throws {
        let store = MockRelayStore()
        let mgmt = MockWebSocketManagementAPI()
        let handler = HTTPRelayHandler(
            store: store,
            authenticator: MockHTTPAuthenticator(),
            managementAPI: mgmt,
            config: makeConfig()
        )

        let result = try await handler.handleRequest(
            sessionId: "session-1",
            apiKey: "bad-key",
            body: Data("{}".utf8)
        )

        #expect(result.statusCode == 401)
    }

    // MARK: - Session Lookup Tests

    @Test("No connected session returns 404")
    func testNoSession() async throws {
        let store = MockRelayStore()
        let mgmt = MockWebSocketManagementAPI()
        let handler = HTTPRelayHandler(
            store: store,
            authenticator: MockHTTPAuthenticator(),
            managementAPI: mgmt,
            config: makeConfig()
        )

        let result = try await handler.handleRequest(
            sessionId: "nonexistent",
            apiKey: "valid-api-key",
            body: Data("{}".utf8)
        )

        #expect(result.statusCode == 404)
    }

    // MARK: - Request Forwarding Tests

    @Test("Forwards request to iOS app and returns response")
    func testForwardRequest() async throws {
        let store = MockRelayStore()
        let mgmt = MockWebSocketManagementAPI()
        let config = makeConfig()

        // Simulate iOS app connected
        try await store.storeConnection(
            connectionId: "conn-ios",
            sessionId: "session-1",
            principalId: "user-1"
        )

        let handler = HTTPRelayHandler(
            store: store,
            authenticator: MockHTTPAuthenticator(),
            managementAPI: mgmt,
            config: config
        )

        let requestBody = #"{"jsonrpc":"2.0","id":"1","method":"tools/list"}"#.data(using: .utf8)!

        // Simulate iOS app responding (in a background task)
        // We need to store a response before the handler times out
        let responseTask = Task {
            // Wait a bit for the request to be stored
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms

            // Find the stored request and provide a response
            let requests = await store.storedRequests
            if let (_, record) = requests.first(where: { $0.value.connectionId == "conn-ios" }) {
                let responseBody = #"{"jsonrpc":"2.0","id":"1","result":{"tools":[]}}"#.data(using: .utf8)!
                try await store.storeResponse(
                    connectionId: "conn-ios",
                    correlationId: record.correlationId,
                    body: responseBody
                )
            }
        }

        let result = try await handler.handleRequest(
            sessionId: "session-1",
            apiKey: "valid-api-key",
            body: requestBody
        )

        _ = try await responseTask.value

        #expect(result.statusCode == 200)

        // Verify the response body contains the MCP response
        let responseJson = try JSONSerialization.jsonObject(with: result.body!) as! [String: Any]
        #expect(responseJson["result"] != nil)

        // Verify request was forwarded via management API
        let posted = await mgmt.postedMessages
        #expect(posted.count == 1)
        #expect(posted[0].connectionId == "conn-ios")
    }

    @Test("Times out when iOS app doesn't respond")
    func testTimeout() async throws {
        let store = MockRelayStore()
        let mgmt = MockWebSocketManagementAPI()
        let config = RelayConfig(
            tableName: "test-table",
            wsManagementEndpoint: "https://test.example.com",
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.2
        )

        // Connect iOS app but don't respond
        try await store.storeConnection(
            connectionId: "conn-ios",
            sessionId: "session-1",
            principalId: "user-1"
        )

        let handler = HTTPRelayHandler(
            store: store,
            authenticator: MockHTTPAuthenticator(),
            managementAPI: mgmt,
            config: config
        )

        let result = try await handler.handleRequest(
            sessionId: "session-1",
            apiKey: "valid-api-key",
            body: Data("{}".utf8)
        )

        #expect(result.statusCode == 504)
    }

    @Test("Returns error when PostToConnection fails")
    func testPostToConnectionFails() async throws {
        let store = MockRelayStore()
        let mgmt = MockWebSocketManagementAPI()
        await mgmt.setShouldFail(true)

        try await store.storeConnection(
            connectionId: "conn-ios",
            sessionId: "session-1",
            principalId: "user-1"
        )

        let handler = HTTPRelayHandler(
            store: store,
            authenticator: MockHTTPAuthenticator(),
            managementAPI: mgmt,
            config: makeConfig()
        )

        let result = try await handler.handleRequest(
            sessionId: "session-1",
            apiKey: "valid-api-key",
            body: Data("{}".utf8)
        )

        #expect(result.statusCode == 500)
    }
}
