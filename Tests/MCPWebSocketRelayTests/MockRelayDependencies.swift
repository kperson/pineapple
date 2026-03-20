import Foundation
@testable import MCPWebSocketRelay
@testable import MCPWebSocketShared

// MARK: - Mock Relay Store

/// In-memory mock implementation of RelayStore for testing
actor MockRelayStore: RelayStore {
    struct ConnectionRecord {
        let connectionId: String
        let sessionId: String
        let principalId: String?
    }

    struct RequestRecord {
        let connectionId: String
        let correlationId: String
        let requestBody: Data
        var responseBody: Data?
        var status: String
    }

    private var connections: [String: ConnectionRecord] = [:]
    private var requests: [String: RequestRecord] = [:]

    // For test verification
    var storedConnections: [String: ConnectionRecord] { connections }
    var storedRequests: [String: RequestRecord] { requests }

    nonisolated func storeConnection(connectionId: String, sessionId: String, principalId: String?) async throws {
        await _storeConnection(connectionId: connectionId, sessionId: sessionId, principalId: principalId)
    }

    private func _storeConnection(connectionId: String, sessionId: String, principalId: String?) {
        connections[connectionId] = ConnectionRecord(
            connectionId: connectionId,
            sessionId: sessionId,
            principalId: principalId
        )
    }

    nonisolated func removeConnection(connectionId: String) async throws {
        await _removeConnection(connectionId: connectionId)
    }

    private func _removeConnection(connectionId: String) {
        connections.removeValue(forKey: connectionId)
    }

    nonisolated func findConnectionBySession(sessionId: String) async throws -> String? {
        return await _findConnectionBySession(sessionId: sessionId)
    }

    private func _findConnectionBySession(sessionId: String) -> String? {
        connections.values.first { $0.sessionId == sessionId }?.connectionId
    }

    nonisolated func storeRequest(connectionId: String, correlationId: String, body: Data) async throws {
        await _storeRequest(connectionId: connectionId, correlationId: correlationId, body: body)
    }

    private func _storeRequest(connectionId: String, correlationId: String, body: Data) {
        let key = "\(connectionId)#\(correlationId)"
        requests[key] = RequestRecord(
            connectionId: connectionId,
            correlationId: correlationId,
            requestBody: body,
            status: "PENDING"
        )
    }

    nonisolated func storeResponse(connectionId: String, correlationId: String, body: Data) async throws {
        await _storeResponse(connectionId: connectionId, correlationId: correlationId, body: body)
    }

    private func _storeResponse(connectionId: String, correlationId: String, body: Data) {
        let key = "\(connectionId)#\(correlationId)"
        requests[key]?.responseBody = body
        requests[key]?.status = "COMPLETED"
    }

    nonisolated func getResponse(connectionId: String, correlationId: String) async throws -> Data? {
        return await _getResponse(connectionId: connectionId, correlationId: correlationId)
    }

    private func _getResponse(connectionId: String, correlationId: String) -> Data? {
        let key = "\(connectionId)#\(correlationId)"
        guard let record = requests[key], record.status == "COMPLETED" else {
            return nil
        }
        return record.responseBody
    }
}

// MARK: - Mock Authenticators

/// Mock WebSocket authenticator that accepts/rejects based on token value
struct MockWebSocketAuthenticator: WebSocketAuthenticator {
    let validTokens: Set<String>

    init(validTokens: Set<String> = ["valid-jwt"]) {
        self.validTokens = validTokens
    }

    func validate(token: String) async throws -> AuthResult {
        if validTokens.contains(token) {
            return .valid(principalId: "test-user", claims: ["role": "admin"])
        }
        return .invalid
    }
}

/// Mock HTTP client authenticator
struct MockHTTPAuthenticator: HTTPClientAuthenticator {
    let validKeys: Set<String>

    init(validKeys: Set<String> = ["valid-api-key"]) {
        self.validKeys = validKeys
    }

    func validate(apiKey: String) async throws -> Bool {
        return validKeys.contains(apiKey)
    }
}

// MARK: - Mock WebSocket Management API

/// Mock that captures PostToConnection calls
actor MockWebSocketManagementAPI: WebSocketManagementAPI {
    struct PostedMessage {
        let connectionId: String
        let data: Data
    }

    private var _postedMessages: [PostedMessage] = []
    private var _shouldFail = false

    var postedMessages: [PostedMessage] { _postedMessages }

    func setShouldFail(_ fail: Bool) {
        _shouldFail = fail
    }

    nonisolated func postToConnection(connectionId: String, data: Data) async throws {
        try await _postToConnection(connectionId: connectionId, data: data)
    }

    private func _postToConnection(connectionId: String, data: Data) throws {
        if _shouldFail {
            throw NSError(domain: "MockError", code: 410, userInfo: [NSLocalizedDescriptionKey: "Gone"])
        }
        _postedMessages.append(PostedMessage(connectionId: connectionId, data: data))
    }
}
