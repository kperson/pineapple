import Foundation
import SystemTestsCommon
import SotoDynamoDB
import XCTest


class RemoteTestCase: XCTestCase {

    let verifier = RemoteVerify(
        dynamoDB:  DynamoDB(client: AWSClient(httpClientProvider: .createNew)),
        testRunKey: UUID().uuidString,
        tableName: ProcessInfo.processInfo.environment["REMOTE_VERIFY_TABLE_NAME"]!
    )

}
