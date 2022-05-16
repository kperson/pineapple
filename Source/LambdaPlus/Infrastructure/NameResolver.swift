import Foundation

public class NameResolver {
    
    public var topicArnEnv: (TopicName) -> EnvVarName = { "\($0.uppercased())_TOPIC_ARN" }
    
    public var interpolateTopicArn: (TopicName) -> TopicArn = {
        .ref("aws_sns_topic.\($0.lowercased()).arn")
    }
            
}
