import Foundation
import SotoDynamoDB
import XCTest
import SystemTestsCommon


class DynamoStreamTestCase: RemoteTestCase {
    
    let table = "pineapplTest"
    let dynamo = DynamoDB(client: AWSClient(httpClientProvider: .createNew))
    let expiration = Int(Date().timeIntervalSince1970) + 60
    
    func testCreateUpdateAndDelete() async throws {
        let message = Verify(verifyKey: verifier.testRunKey, value: "hello world", ttl: expiration)
        _ = try await dynamo.putItem(.init(item: message, tableName: table))
        if let messageCreate = try await verifier.retrieveOrFail(
            key: "new",
            failureMessage: "Lambda did not set `new` ack in time"
        ) {
            XCTAssertEqual(messageCreate, verifier.testRunKey)
        }
                
        let changeMessage = Verify(verifyKey: verifier.testRunKey, value: "hello world 2", ttl: expiration)
        _ = try await dynamo.putItem(.init(item: changeMessage, tableName: table))
        if let messageUpdate = try await verifier.retrieveOrFail(
            key: "update",
            failureMessage: "Lambda did not set `update` ack in time"
        ) {
            XCTAssertEqual(messageUpdate, verifier.testRunKey)
        }
        
        
        _ = try await dynamo.deleteItem(.init(key: ["verifyKey" : .s(verifier.testRunKey)], tableName: table))
        if let messageDelete = try await verifier.retrieveOrFail(
            key: "delete",
            failureMessage: "Lambda did not set `delete` ack in time"
        ) {
            XCTAssertEqual(messageDelete, verifier.testRunKey)
        }

    }
    
}
