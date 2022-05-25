import Foundation

public typealias TopicName = String
public typealias TopicArn = BuildValue<String>

public struct SNSTopic: Hashable, Equatable {
        
    public let name: TopicName
    public let isFifo: Bool
    
    public init(name: CustomStringConvertible, isFifo: Bool = true) {
        self.name = String(describing: name)
        self.isFifo = isFifo
    }
    
}

public enum SNSTopicRef: Hashable, Equatable {
    
    case managed(SNSTopic)
    case unmanaged(TopicArn)
    
}

public struct SNSReadLambda: Hashable, Equatable {
    
    
    let topicArn: TopicArn
    let functionName: FunctionName
    let settings: LambdaSettings
    
    init(topicArn: TopicArn, functionName: String, settings: LambdaSettings) {
        self.topicArn = topicArn
        self.functionName = functionName
        self.settings = settings
    }
    
}
