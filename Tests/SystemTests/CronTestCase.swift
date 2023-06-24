import Foundation
import SotoS3
import XCTest
import SystemTestsCommon


class CronTestCase: RemoteTestCase {
    
    func testCreateAndDelete() async throws {
        let cronVerify = RemoteVerify(
            dynamoDB:  verifier.dynamoDB,
            testRunKey: "cron",
            tableName: verifier.tableName
        )
        _ = try await cronVerify.retrieveOrFail(
            key: "cronTriggered",
            failureMessage: "Lambda did not set cronExecuted receipt in time"
        )
    }
    
}
