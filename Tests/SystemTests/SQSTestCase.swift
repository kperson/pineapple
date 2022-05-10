import Foundation
import SotoSQS
import XCTest


class SQSTestCase: RemoteTestCase {
    
    let sqs = SQS(client: AWSClient(httpClientProvider: .createNew))
    
    func testSend() async throws {
        let sentMessageBody = "hello world"
        
        let queueUrl = try await sqs.getQueueUrl(.init(queueName: "pineapple-test-queue")).queueUrl!
        let attributes = [
            "testRunKey"          : SQS.MessageAttributeValue(dataType: "String", stringValue: verifier.testRunKey),
            "testRunKeyAsBinary"  : SQS.MessageAttributeValue(binaryValue: verifier.testRunKey.data(using: .utf8)!, dataType: "Binary")
        ]
        _ = try await sqs.sendMessage(.init(
            messageAttributes: attributes,
            messageBody: sentMessageBody,
            messageDeduplicationId: nil,
            messageGroupId: nil,
            queueUrl: queueUrl
        ))
        
        let messageBody = try await verifier.retrieveOrFail(
            key: "messageBody",
            failureMessage: "Lambda did not set messageBody in time"
        )
        XCTAssertEqual(messageBody, sentMessageBody)

        
//        let messageBodyFromBinary = try await verifier.retrieveOrFail(
//            key: "messageBodyBinary",
//            failureMessage: "Lambda did not set messageBody in time from binary value"
//        )
//        XCTAssertEqual(messageBodyFromBinary, sentMessageBody)
    }
    
}
