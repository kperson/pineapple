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
                expressionAttributeValues: [":namespaceKey" : .s(namespaceKey)],
                filterExpression: "attribute_not_exists(response)",
                keyConditionExpression: "namespaceKey = :namespaceKey",
                limit: 1,
                scanIndexForward: false,
                tableName: table
            ),
            type: LambdaRemoteEvent.self
        ).items?.first
    }
    
    func save(event: LambdaRemoteEvent) async throws {
        _ = try await dynamoDB.putItem(DynamoDB.PutItemCodableInput(item: event, tableName: table))
    }
    
}
