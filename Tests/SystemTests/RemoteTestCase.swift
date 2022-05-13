import Foundation
import SystemTestsCommon
import SotoDynamoDB
import XCTest


class RemoteTestCase: XCTestCase {

    let verifier = RemoteVerify(
        dynamoDB:  DynamoDB(client: AWSClient(httpClientProvider: .createNew)),
        testRunKey: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        tableName: ProcessInfo.processInfo.environment["REMOTE_VERIFY_TABLE_NAME"]!
    )

}

extension RemoteVerify {
    
    func retrieveOrFail(key: String, failureMessage: String) async throws -> String? {
        if let value = try await fetch(key: key) {
            return value
        }
        else {
            XCTFail(failureMessage)
        }
        return nil
    }
    
}
