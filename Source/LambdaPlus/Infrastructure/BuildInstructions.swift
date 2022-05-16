import Foundation


public protocol BuildInstructions {
    
    var envs: [EnvVarName : EnvVarValue] { get }
    var snsTopics: [SNSTopic] { get }
    var snsReadLambdas: [SNSReadLambda] { get }
    
}
