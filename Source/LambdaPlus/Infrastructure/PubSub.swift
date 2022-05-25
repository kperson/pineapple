import Foundation
import LambdaApp

public struct LambdaSettings: Hashable, Equatable {
    
    public let memory: Int?
    public let timeout: Int?
    public let environmentVariables: [String : String]
    
    public init(
        memory: Int? = nil,
        timeout: Int? = nil,
        environmentVariables: [String : String] = [:]
    ) {
        self.memory = memory
        self.timeout = timeout
        self.environmentVariables = environmentVariables
    }
    
}

public class PubSubRef {
    
    public let context: AWSContext
    public let ref: SNSTopicRef

    public init(context: AWSContext, ref: SNSTopicRef) {
        self.context = context
        self.ref = ref
    }
    
    public func reader<T: Decodable>(
        _ type: T.Type,
        lambdaName: CustomStringConvertible,
        settings: LambdaSettings = LambdaSettings(),
        decode: ((Data) throws -> T)? = nil
    ) -> SNSRead<T> {
        let fName = String(describing: lambdaName)
        let fHandler = context.nameResolver.functionHandler(fName)
        switch ref {
        case .unmanaged(let arn):
            context.cloudBuilder.addSNSReadLambda(.init(topicArn: arn, functionName: fName, settings: settings))
        case .managed(let topic):
            context.cloudBuilder.addSNSReadLambda(.init(
                topicArn: context.nameResolver.interpolateTopicArn(topic.name),
                functionName: fName,
                settings: settings
            ))
        }
        if let d = (decode.map { FuncDecode($0) }) {
            return SNSRead<T>(
                app: context.app,
                functionName: fHandler,
                decode: d
            )
        }
        else {
            return SNSRead<T>(
                app: context.app,
                functionName: fHandler,
                decode: JSONDecode(decoder: JSONDecoder())
            )
        }

    }
    
    public func writer<T: Encodable>(
        _ type: T.Type,
        targetArnEnvName: CustomStringConvertible? = nil,
        encode: ((T) throws -> Data)? = nil
    ) -> SNSWrite<T> {
        let envNameRaw = targetArnEnvName.map {
            String(describing: $0)
        } ?? context.envNameGenerator.topicWriterEnv(ref: self)
        
        switch ref {
        case .unmanaged(let arn):
            context.cloudBuilder.addEnv(name: envNameRaw, value: arn)
        case .managed(let topic):
            context.cloudBuilder.addEnv(
                name: envNameRaw,
                value: context.nameResolver.interpolateTopicArn(topic.name)
            )
        }
        let targetArn = LazyEnv.envStr(envNameRaw)
        if let e = (encode.map { FuncEncode($0) }) {
            return SNSWrite(
                sns: context.sns,
                targetArn: targetArn,
                encode: e
            )
        }
        else {
            return SNSWrite(
                sns: context.sns,
                targetArn: targetArn,
                encode: JSONEncode(encoder: JSONEncoder())
            )
        }
    }
    
}

public class PubSub {
    
    public unowned let context: AWSContext
    private var cache: [SNSTopicRef: PubSubRef] = [:]

    public init(context: AWSContext) {
        self.context = context
    }
    
    public func topic(_ ref: SNSTopicRef) -> PubSubRef {
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

public extension PubSub {

    func managedTopic(_ snsTopic: SNSTopic) -> PubSubRef {
        topic(.managed(snsTopic))
    }
    
    func unmanagedTopic(_ arn: TopicArn) -> PubSubRef {
        topic(.unmanaged(arn))
    }
    
}
