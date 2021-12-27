import Foundation
import SotoDynamoDB
import LambdaRuntimeAPI

class LambdaEventRepo {
    
    let dynamoDB: DynamoDB
    let table: String
    
    init(dynamoDB: DynamoDB, table: String) {
        self.dynamoDB = dynamoDB
        self.table = table
    }
    
    func getByRequestId(requestId: String) async throws -> LambdaRemoteEvent? {
        return try await dynamoDB.query(
            .init(
                expressionAttributeValues: [":requestId" : .s(requestId)],
                indexName: "requestIdIndex",
                keyConditionExpression: "requestId = :requestId",
                limit: 1,
                tableName: table
            ),
            type: LambdaRemoteEvent.self
        ).items?.first
    }
    
    func getNext(namespaceKey: String) async throws -> LambdaRemoteEvent? {
        return try await dynamoDB.query(
            .init(
                expressionAttributeNames: ["#response" : "response"],
                expressionAttributeValues: [":namespaceKey" : .s(namespaceKey)],
                filterExpression: "attribute_not_exists(#response)",
                keyConditionExpression: "namespaceKey = :namespaceKey",
                limit: 1,
                scanIndexForward: true,
                tableName: table
            ),
            type: LambdaRemoteEvent.self
        ).items?.first
    }
    
    func save(event: LambdaRemoteEvent) async throws {
        _ = try await dynamoDB.putItem(DynamoDB.PutItemCodableInput(item: event, tableName: table))
    }
    
    func delete(requestId: String) async throws -> Bool {
        guard let event = try await getByRequestId(requestId: requestId) else { return false }
        let key: [String : DynamoDB.AttributeValue] = [
            "namespaceKey" : .s(event.namespaceKey),
            "payloadCreatedAt" : .n(String(event.payloadCreatedAt))
        ]
        _ = try await dynamoDB.deleteItem(.init(key: key, tableName: table))
        return true
    }
    
}
