import Foundation
import SotoDynamoDB

public struct Verify: Codable {
    
    public let verifyKey: String
    public let value: String
    public let ttl: Int
    
    public init(verifyKey: String, value: String, ttl: Int) {
        self.verifyKey = verifyKey
        self.value = value
        self.ttl = ttl
    }
    
}


public class RemoteVerify {
    
    public let dynamoDB: DynamoDB
    public let testRunKey: String
    public let tableName: String
    
    public init(dynamoDB: DynamoDB, testRunKey: String, tableName: String) {
        self.dynamoDB = dynamoDB
        self.testRunKey = testRunKey
        self.tableName = tableName
    }
    
    private func dynamoKey(_ key: String) -> String {
        return "\(testRunKey):\(key)"
    }
    
    public func save(key: String, value: String, ttlOffset: Int = 3600) async throws {
        let vKey = dynamoKey(key)
        let ttl = Int((Date().timeIntervalSince1970)) + ttlOffset
        let v = Verify(verifyKey: vKey, value: value, ttl: ttl)
        _ = try await dynamoDB.putItem(.init(item: v, tableName: tableName))
    }
    
    public func fetch(key: String, numAttempts: Int = 20) async throws -> String? {
        let oneSecond: UInt64 = 1_000_000_000
        let vKey = dynamoKey(key)
        let result = try await dynamoDB.getItem(
            .init(key: ["verifyKey" : .s(vKey)], tableName: tableName),
            type: Verify.self
        )
        if let item = result.item, TimeInterval(item.ttl) >= Date().timeIntervalSince1970 {
            return item.value
        }
        else if numAttempts <= 1 {
            return nil
        }
        else {
            try await Task.sleep(nanoseconds: oneSecond)
            return try await fetch(key: key, numAttempts: numAttempts - 1)
        }
    }
    
}
