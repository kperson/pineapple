import Foundation
import SotoDynamoDB

/// A verification record stored in DynamoDB with TTL for automatic cleanup
public struct Verify: Codable {
    
    public let verifyKey: String
    public let ttl: Int
    
    public init(verifyKey: String, ttl: Int) {
        self.verifyKey = verifyKey
        self.ttl = ttl
    }
    
}

/// RemoteVerify provides a mechanism for distributed verification between Lambda functions and tests.
/// 
/// Lambda functions use `save()` to store verification data in DynamoDB when they process events.
/// Tests use `check()` and `checkWithValue()` to verify that Lambda functions processed events correctly.
/// 
/// The verification data is automatically cleaned up using DynamoDB TTL to prevent accumulation.
public final class RemoteVerify: Sendable {
    
    public let dynamoDB: DynamoDB
    public let namespace: String
    public let tableName: String
    
    public init(dynamoDB: DynamoDB, namespace: String, tableName: String) {
        self.dynamoDB = dynamoDB
        self.namespace = namespace
        self.tableName = tableName
    }
    
    /// Verifies that a Lambda function processed an event with a specific value.
    /// 
    /// This method generates a unique value, executes the provided action with that value,
    /// then waits for verification data to appear in DynamoDB that matches the value.
    /// 
    /// - Parameters:
    ///   - test: The test identifier (e.g., "sqs", "eventbridge")
    ///   - action: A closure that should trigger the Lambda function with the generated value
    /// - Returns: `true` if verification data was found and matched, `false` if timeout occurred
    public func checkWithValue(
        test: String,
        numAttempts: Int = 30,
        _ action: (String) async throws -> Void
    ) async throws -> Bool {
        let value = UUID().uuidString
        try await action(value)
        return try await fetchIsMatching(test: test, value: value, numAttempts: numAttempts)
    }
    
    /// Verifies that a Lambda function processed an event for the given test.
    /// 
    /// This method waits for verification data to appear in DynamoDB for the specified test.
    /// Used when the exact value processed is not important, only that processing occurred.
    /// 
    /// - Parameter test: The test identifier (e.g., "sqs", "eventbridge")
    /// - Returns: `true` if verification data was found, `false` if timeout occurred
    public func check(test: String, numAttempts: Int = 30) async throws -> Bool {
        return try await fetchIsMatching(test: test, numAttempts: numAttempts)
    }
    
    /// Saves verification data to DynamoDB indicating that an event was processed.
    /// 
    /// This method is called by Lambda functions to record that they successfully processed an event.
    /// The data includes an optional value and TTL for automatic cleanup.
    /// 
    /// - Parameters:
    ///   - test: The test identifier (e.g., "sqs", "eventbridge")
    ///   - value: Optional specific value that was processed
    ///   - ttlOffset: TTL offset in seconds from current time (default: 3600 = 1 hour)
    public func save(
        test: String,
        value: String? = nil,
        ttlOffset: TimeInterval = 3600
    ) async throws {
        let vKey = dynamoKey(test: test, value: value)
        let ttl = Int(Date().addingTimeInterval(ttlOffset).timeIntervalSince1970)
        let verify = Verify(verifyKey: vKey, ttl: ttl)
        _ = try await dynamoDB.deleteItem(.init(key: ["verifyKey" : .s(vKey)], tableName: tableName))
        _ = try await dynamoDB.putItem(.init(item: verify, tableName: tableName))
    }
    
    private func dynamoKey(test: String, value: String?) -> String {
        if let value = value {
            return "namespace:\(namespace):test:\(test):value:\(value)"
        }
        return "namespace:\(namespace):test:\(test)"
    }
    

    private func fetchIsMatching(
        test: String,
        value: String? = nil,
        ttlOffset: TimeInterval = 3600,
        numAttempts: Int = 30
    ) async throws -> Bool {
        let oneSecond: UInt64 = 1_000_000_000
        let vKey = dynamoKey(test: test, value: value)
        let result = try await dynamoDB.getItem(
            .init(key: ["verifyKey" : .s(vKey)], tableName: tableName),
            type: Verify.self
        )
        if let item = result.item, TimeInterval(item.ttl) >= Date().timeIntervalSince1970 {
            _ = try await dynamoDB.deleteItem(.init(key: ["verifyKey" : .s(vKey)], tableName: tableName))
            if item.verifyKey == vKey {
                return true
            } else {
                print("Verification failed, expected \(vKey), got \(item.verifyKey)")
                return false
            }
        } else if numAttempts - 1 == 0 {
            print("Verification failed, timeout")
            return false
        } else {
            try await Task.sleep(nanoseconds: oneSecond)
            return try await fetchIsMatching(test: test, value: value, numAttempts: numAttempts - 1)
        }
    }
    
}
