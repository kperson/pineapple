import Testing
import Foundation
import MCPWebSocketShared

/// Check if WebSocket relay environment variables are present
private let relayTestsEnabled: Bool = {
    ProcessInfo.processInfo.environment["TEST_WS_RELAY_ENDPOINT"] != nil &&
    ProcessInfo.processInfo.environment["TEST_HTTP_RELAY_ENDPOINT"] != nil
}()

// Hardcoded test credentials (must match LambdaHandler)
private let testJWTToken = "pineapple-test-jwt-token-2024"
private let testAPIKey = "pineapple-test-api-key-2024"

/// End-to-end tests for the WebSocket relay.
///
/// These tests verify the full round-trip:
/// 1. Connect to WebSocket relay as "fake iOS app"
/// 2. POST MCP request to HTTP relay as "MCP client"
/// 3. Receive forwarded request on WebSocket
/// 4. Send response back through WebSocket
/// 5. Verify HTTP POST returns the response
///
/// Required environment variables:
/// - `TEST_WS_RELAY_ENDPOINT`: WebSocket relay endpoint (wss://...)
/// - `TEST_HTTP_RELAY_ENDPOINT`: HTTP relay endpoint
@Suite("WebSocket Relay E2E Tests", .enabled(if: relayTestsEnabled))
struct WebSocketRelayTests {

    let wsEndpoint: String
    let httpEndpoint: String

    init() {
        wsEndpoint = ProcessInfo.processInfo.environment["TEST_WS_RELAY_ENDPOINT"]!
        httpEndpoint = ProcessInfo.processInfo.environment["TEST_HTTP_RELAY_ENDPOINT"]!
    }

    // MARK: - E2E Round-trip Test

    @Test("Full MCP request round-trip through relay")
    func testFullRoundTrip() async throws {
        let sessionId = UUID().uuidString

        // 1. Connect to WebSocket as fake iOS app
        let wsURL = URL(string: wsEndpoint)!
        var wsRequest = URLRequest(url: wsURL)
        wsRequest.setValue("Bearer \(testJWTToken)", forHTTPHeaderField: "Authorization")
        wsRequest.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")

        let session = URLSession(configuration: .default)
        let wsTask = session.webSocketTask(with: wsRequest)
        wsTask.resume()

        // Give the connection a moment to establish
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s

        // 2. Start listening for relay messages on the WebSocket (in background)
        let responseReceived = ResponseTracker()
        let listenTask = Task {
            while !Task.isCancelled {
                let message = try await wsTask.receive()
                let data: Data
                switch message {
                case .string(let str):
                    data = str.data(using: .utf8) ?? Data()
                case .data(let d):
                    data = d
                @unknown default:
                    continue
                }

                let relayMessage = try JSONDecoder().decode(RelayMessage.self, from: data)
                if case .request(let relayRequest) = relayMessage {
                    // 3. Process the request — return a simple MCP response
                    let mcpResponse: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": "1",
                        "result": [
                            "tools": [
                                ["name": "test_tool", "description": "A test tool"]
                            ]
                        ]
                    ]
                    let responseBody = try JSONSerialization.data(withJSONObject: mcpResponse)

                    // 4. Send response back through WebSocket
                    let relayResponse = RelayResponse(
                        correlationId: relayRequest.correlationId,
                        body: responseBody
                    )
                    let responseMessage = RelayMessage.response(relayResponse)
                    let encoded = try JSONEncoder().encode(responseMessage)
                    let responseString = String(data: encoded, encoding: .utf8)!
                    try await wsTask.send(.string(responseString))

                    await responseReceived.markSent()
                }
            }
        }

        // 5. POST MCP request to HTTP relay as MCP client
        let mcpRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "1",
            "method": "tools/list"
        ]
        let mcpRequestData = try JSONSerialization.data(withJSONObject: mcpRequest)

        let httpURL = URL(string: "\(httpEndpoint)/mcp/\(sessionId)")!
        var httpRequest = URLRequest(url: httpURL)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue(testAPIKey, forHTTPHeaderField: "x-api-key")
        httpRequest.httpBody = mcpRequestData
        httpRequest.timeoutInterval = 30

        let (responseData, httpResponse) = try await session.data(for: httpRequest)
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0

        // Cancel the listener
        listenTask.cancel()
        wsTask.cancel(with: .normalClosure, reason: nil)

        // 6. Verify the HTTP response
        #expect(statusCode == 200, "Expected 200, got \(statusCode)")

        let json = try JSONSerialization.jsonObject(with: responseData) as! [String: Any]
        let result = json["result"] as? [String: Any]
        #expect(result != nil, "Response should have a result")

        let tools = result?["tools"] as? [[String: Any]]
        #expect(tools?.first?["name"] as? String == "test_tool")

        let wasSent = await responseReceived.sent
        #expect(wasSent, "Should have received and responded to the relay request")
    }

    // MARK: - Auth Rejection Tests

    @Test("WebSocket connect with invalid JWT is rejected")
    func testWSInvalidJWT() async throws {
        let wsURL = URL(string: wsEndpoint)!
        var wsRequest = URLRequest(url: wsURL)
        wsRequest.setValue("Bearer invalid-token", forHTTPHeaderField: "Authorization")
        wsRequest.setValue(UUID().uuidString, forHTTPHeaderField: "X-Session-Id")

        let session = URLSession(configuration: .default)
        let wsTask = session.webSocketTask(with: wsRequest)
        wsTask.resume()

        // Try to receive — should fail because connection was rejected
        do {
            _ = try await wsTask.receive()
            Issue.record("Expected WebSocket connection to be rejected")
        } catch {
            // Expected — connection rejected with 401
        }

        wsTask.cancel(with: .normalClosure, reason: nil)
    }

    @Test("HTTP request with invalid API key returns 401")
    func testHTTPInvalidAPIKey() async throws {
        let httpURL = URL(string: "\(httpEndpoint)/mcp/\(UUID().uuidString)")!
        var httpRequest = URLRequest(url: httpURL)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue("bad-api-key", forHTTPHeaderField: "x-api-key")
        httpRequest.httpBody = #"{"jsonrpc":"2.0","id":"1","method":"tools/list"}"#.data(using: .utf8)

        let session = URLSession(configuration: .default)
        let (_, response) = try await session.data(for: httpRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        #expect(statusCode == 401, "Expected 401, got \(statusCode)")
    }

    @Test("HTTP request for nonexistent session returns 404")
    func testHTTPNoSession() async throws {
        let httpURL = URL(string: "\(httpEndpoint)/mcp/nonexistent-session")!
        var httpRequest = URLRequest(url: httpURL)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue(testAPIKey, forHTTPHeaderField: "x-api-key")
        httpRequest.httpBody = #"{"jsonrpc":"2.0","id":"1","method":"tools/list"}"#.data(using: .utf8)

        let session = URLSession(configuration: .default)
        let (_, response) = try await session.data(for: httpRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        #expect(statusCode == 404, "Expected 404, got \(statusCode)")
    }
}

/// Thread-safe tracker for whether the WebSocket response was sent
actor ResponseTracker {
    var sent = false

    func markSent() {
        sent = true
    }
}
