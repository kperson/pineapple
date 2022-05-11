import Foundation
import SotoSNS
import XCTest
import SystemTestsCommon


class SNSTestCase: RemoteTestCase {
    
    let sns = SNS(client: AWSClient(httpClientProvider: .createNew))
    let topicArn = ProcessInfo.processInfo.environment["TOPIC_ARN"]!
    
    func testSend() async throws {
        let message = DemoMessage(testRunKey: verifier.testRunKey, message: "hello world")
        _ = try await sns.publish(.init(
            message: message.jsonStr(),
            messageAttributes: nil,
            messageDeduplicationId: nil,
            messageGroupId: nil,
            topicArn: topicArn
        ))
        if let messageBodyStr = try await verifier.retrieveOrFail(
            key: "messageBody",
            failureMessage: "Lambda did not set messageBody in time"
        ) {
            let messageFromStr = try DemoMessage(jsonStr: messageBodyStr)
            XCTAssertEqual(messageFromStr, message)
        }
    }
    
}
