import Foundation
import SotoDynamoDB
import Logging

// MARK: - DynamoDB Store Protocol

/// Protocol for relay storage operations (enables mock injection for tests)
///
/// The relay uses DynamoDB to:
/// 1. Track active WebSocket connections (PK=connectionId, SK="CONNECTION")
/// 2. Store pending requests and responses (PK=connectionId, SK="REQ#correlationId")
/// 3. Look up connections by sessionId (via GSI)
public protocol RelayStore: Sendable {
    /// Store a new WebSocket connection
    func storeConnection(connectionId: String, sessionId: String, principalId: String?) async throws

    /// Remove a WebSocket connection
    func removeConnection(connectionId: String) async throws

    /// Find the connection ID for a given session
    func findConnectionBySession(sessionId: String) async throws -> String?

    /// Store a pending request (waiting for iOS response)
    func storeRequest(connectionId: String, correlationId: String, body: Data) async throws

    /// Store a response from the iOS app
    func storeResponse(connectionId: String, correlationId: String, body: Data) async throws

    /// Poll for a response to a given request
    func getResponse(connectionId: String, correlationId: String) async throws -> Data?
}

// MARK: - DynamoDB Implementation

/// DynamoDB-backed relay store
///
/// ## Table Schema
///
/// - **PK**: `connectionId` (String)
/// - **SK**: `CONNECTION` or `REQ#<correlationId>` (String)
/// - **GSI**: `sessionId-index` on `sessionId` attribute
/// - **TTL**: `ttl` attribute (epoch seconds)
///
/// ## Item Types
///
/// **Connection record** (SK = "CONNECTION"):
/// - `connectionId`, `sessionId`, `principalId`, `connectedAt`, `ttl`
///
/// **Request/Response record** (SK = "REQ#<correlationId>"):
/// - `connectionId`, `correlationId`, `requestBody`, `responseBody`, `status`, `ttl`
public struct DynamoDBRelayStore: RelayStore {

    private let dynamoDB: DynamoDB
    private let config: RelayConfig
    private let logger: Logger

    public init(dynamoDB: DynamoDB, config: RelayConfig, logger: Logger = Logger(label: "relay-store")) {
        self.dynamoDB = dynamoDB
        self.config = config
        self.logger = logger
    }

    public func storeConnection(connectionId: String, sessionId: String, principalId: String?) async throws {
        let ttl = Int(Date().timeIntervalSince1970) + config.ttlSeconds

        var item: [String: DynamoDB.AttributeValue] = [
            "connectionId": .s(connectionId),
            "sk": .s("CONNECTION"),
            "sessionId": .s(sessionId),
            "connectedAt": .s(ISO8601DateFormatter().string(from: Date())),
            "ttl": .n(String(ttl))
        ]

        if let principalId = principalId {
            item["principalId"] = .s(principalId)
        }

        let input = DynamoDB.PutItemInput(
            item: item,
            tableName: config.tableName
        )
        _ = try await dynamoDB.putItem(input)
    }

    public func removeConnection(connectionId: String) async throws {
        let input = DynamoDB.DeleteItemInput(
            key: [
                "connectionId": .s(connectionId),
                "sk": .s("CONNECTION")
            ],
            tableName: config.tableName
        )
        _ = try await dynamoDB.deleteItem(input)
    }

    public func findConnectionBySession(sessionId: String) async throws -> String? {
        let input = DynamoDB.QueryInput(
            expressionAttributeNames: ["#sid": "sessionId"],
            expressionAttributeValues: [":sid": .s(sessionId)],
            indexName: "sessionId-index",
            keyConditionExpression: "#sid = :sid",
            limit: 1,
            tableName: config.tableName
        )

        let result = try await dynamoDB.query(input)
        guard let attr = result.items?.first?["connectionId"],
              case .s(let connectionId) = attr else {
            return nil
        }
        return connectionId
    }

    public func storeRequest(connectionId: String, correlationId: String, body: Data) async throws {
        let ttl = Int(Date().timeIntervalSince1970) + config.ttlSeconds

        let item: [String: DynamoDB.AttributeValue] = [
            "connectionId": .s(connectionId),
            "sk": .s("REQ#\(correlationId)"),
            "correlationId": .s(correlationId),
            "requestBody": .s(body.base64EncodedString()),
            "status": .s("PENDING"),
            "ttl": .n(String(ttl))
        ]

        let input = DynamoDB.PutItemInput(
            item: item,
            tableName: config.tableName
        )
        _ = try await dynamoDB.putItem(input)
    }

    public func storeResponse(connectionId: String, correlationId: String, body: Data) async throws {
        let input = DynamoDB.UpdateItemInput(
            expressionAttributeNames: ["#s": "status"],
            expressionAttributeValues: [
                ":body": .s(body.base64EncodedString()),
                ":status": .s("COMPLETED")
            ],
            key: [
                "connectionId": .s(connectionId),
                "sk": .s("REQ#\(correlationId)")
            ],
            tableName: config.tableName,
            updateExpression: "SET responseBody = :body, #s = :status"
        )
        _ = try await dynamoDB.updateItem(input)
    }

    public func getResponse(connectionId: String, correlationId: String) async throws -> Data? {
        let input = DynamoDB.GetItemInput(
            key: [
                "connectionId": .s(connectionId),
                "sk": .s("REQ#\(correlationId)")
            ],
            tableName: config.tableName
        )

        let result = try await dynamoDB.getItem(input)
        guard let item = result.item,
              let statusAttr = item["status"], case .s(let status) = statusAttr,
              status == "COMPLETED",
              let bodyAttr = item["responseBody"], case .s(let base64Body) = bodyAttr,
              let body = Data(base64Encoded: base64Body) else {
            return nil
        }

        return body
    }
}
