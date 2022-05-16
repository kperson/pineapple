import Foundation
import Messaging
import SotoSQS


public class SQSWrite<Out>: PartitionWrite {
        
    public let sqs: SQS
    public let queueUrl: LazyValue<String>
    public let delaySeconds: Int?
    public var messageCustomization: (SQS.SendMessageRequest, Out) -> SQS.SendMessageRequest = {
        msg, val in msg
    }
    private let encodeFunc: (Out) throws -> Data
    
    public init<E: Encode>(
        sqs: SQS,
        queueUrl: LazyValue<String>,
        delaySeconds: Int? = nil,
        encode: E
    ) where E.In == Out, E.Out == Data {
        self.sqs = sqs
        self.queueUrl = queueUrl
        self.encodeFunc = {
            try encode.encode(input: $0)
        }
        self.delaySeconds = delaySeconds
    }
    
    public func write(partitionKey: String, value: Out) async throws {
        let url = queueUrl.materialValue
        let shouldPartition = url.hasSuffix(".fifo")
        let data = try encodeFunc(value)
        let dedupKey = (value as? Deduplicatable)?.deduplicationKey
        if let dataStr = String(data: data, encoding: .utf8) {
            let input = messageCustomization(SQS.SendMessageRequest(
               delaySeconds: delaySeconds,
               messageBody: dataStr,
               messageDeduplicationId: dedupKey,
               messageGroupId: shouldPartition ? partitionKey : nil,
               queueUrl: url
            ), value)
            _ = try await sqs.sendMessage(input)
        }
    }

}

public extension SQSWrite {
    
    convenience init(
        sqs: SQS,
        queueUrl: LazyValue<String>,
        delaySeconds: Int? = nil
    ) where Out: Encodable {
        self.init(
            sqs: sqs,
            queueUrl: queueUrl,
            delaySeconds: delaySeconds,
            encode: JSONEncode(encoder: JSONEncoder())
        )
    }
    
}
