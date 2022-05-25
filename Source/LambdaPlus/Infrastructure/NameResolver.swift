import Foundation

public class NameResolver {
    
    public init() {}
    
    public var topicArnEnv: (TopicName) -> EnvVarName = { "\($0.uppercased())_TOPIC_ARN" }
    
    public var interpolateTopicArn: (TopicName) -> TopicArn = {
        .ref("aws_sns_topic.\($0.lowercased()).arn")
    }
    
    func functionHandler(_ functionName: String) -> String {
        return "pineapple-\(functionName)"
    }
            
}
