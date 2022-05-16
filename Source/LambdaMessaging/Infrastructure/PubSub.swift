import Foundation
import LambdaApp


public class PubSubRef {
    
    public let context: AWSI.Context
    public let ref: SNSTopicRef

    public init(context: AWSI.Context, ref: SNSTopicRef) {
        self.context = context
        self.ref = ref
    }
    
    public func reader<T: Decodable>(type: T.Type, functionName: String) -> SNSRead<T> {
        switch ref {
        case .unmanaged(let arn):
            context.cloudBuilder.addSNSReadLambda(.init(topicArn: arn, functionName: functionName))
        case .managed(let topic):
            context.cloudBuilder.addSNSReadLambda(.init(
                topicArn: context.nameResolver.interpolateTopicArn(topic.name),
                functionName: functionName
            ))
        }
        return SNSRead<T>(app: context.app, functionName: functionName)
    }
    
    public func writer<T: Encodable>(type: T.Type, envName: String) -> SNSWrite<T> {
        switch ref {
        case .unmanaged(let arn):
            context.cloudBuilder.addEnv(name: envName, value: arn)
        case .managed(let topic):
            context.cloudBuilder.addEnv(
                name: envName,
                value: context.nameResolver.interpolateTopicArn(topic.name)
            )
        }
        return SNSWrite(sns: context.sns, targetArn: LazyEnv.envStr(envName))
    }
    
}

public class PubSub {
    
    public let context: AWSI.Context
    private var cache: [SNSTopicRef: PubSubRef] = [:]

    public init(context: AWSI.Context) {
        self.context = context
    }
    
    public func getTopic(_ ref: SNSTopicRef) -> PubSubRef {
        if let cached = cache[ref] {
            return cached
        }
        if case .managed(let topic) = ref {
            context.cloudBuilder.addSNSTopic(topic)
        }
        let rs = PubSubRef(context: context, ref: ref)
        cache[ref] = rs
        return rs
    }
    
}
