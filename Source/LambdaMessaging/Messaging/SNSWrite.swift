import Foundation
import Messaging
import SotoSNS


public class SNSWrite<Out>: PartitionWrite {
        
    public let sns: SNS
    public let targetArn: LazyValue<String>?
    public var messageCustomization: (SNS.PublishInput, Out) -> SNS.PublishInput = {
        msg, val in msg
    }
    private let encodeFunc: (Out) throws -> Data

    public init<E: Encode>(
        sns: SNS,
        targetArn: LazyValue<String>?,
        encode: E
    ) where E.In == Out, E.Out == Data {
        self.sns = sns
        self.targetArn = targetArn
        self.encodeFunc = {
            try encode.encode(input: $0)
        }
    }
    
    public func write(partitionKey: String, value: Out) async throws {
        let target = targetArn?.materialValue
        let shouldPartition = target.map { $0.hasSuffix(".fifo") } ?? false
        let data = try encodeFunc(value)
        let dedupKey = (value as? Deduplicatable)?.deduplicationKey
        if let dataStr = String(data: data, encoding: .utf8) {
            let input = messageCustomization(SNS.PublishInput(
                message: dataStr,
                messageDeduplicationId: dedupKey,
                messageGroupId: shouldPartition ? partitionKey : nil,
                targetArn: target
            ), value)
            _ = try await sns.publish(input)
        }
    }

}

public extension SNSWrite {
    
    convenience init(sns: SNS, targetArn: LazyValue<String>?) where Out: Encodable {
        self.init(
            sns: sns,
            targetArn: targetArn,
            encode: JSONEncode(encoder: JSONEncoder())
        )
    }
    
}
