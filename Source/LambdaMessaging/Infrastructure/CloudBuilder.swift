import Foundation

public typealias EnvVarName = String
public typealias EnvVarValue = TerraformValue<String>

public protocol Instructions {
    
    var envs: [EnvVarName : EnvVarValue] { get }
    var snsTopics: [SNSTopic] { get }
    var snsReadLambdas: [SNSReadLambda] { get }
    
}

public class CloudBuilder: Instructions {
    
    public var envs: [EnvVarName : EnvVarValue] = [:]
    public var snsTopics: [SNSTopic] = []
    public var snsReadLambdas: [SNSReadLambda] = []
    private(set) var allLambdaNames = Set<FunctionName>()
    
    
    public init() {}
    
    public func addEnv(name: EnvVarName, value: EnvVarValue) {
        if let cachedValue = envs[name], value != cachedValue {
            fatalError("You may not override an existing environment variable.")
        }
        else {
            envs[name] = value
        }        
    }
    
    public func addSNSTopic(_ topic: SNSTopic) {
        if !snsTopics.contains(topic) {
            snsTopics.append(topic)
        }
    }
    
    public func addSNSReadLambda(_ lambda: SNSReadLambda) {
        if !allLambdaNames.contains(lambda.functionName) {
            allLambdaNames.insert(lambda.functionName)
            snsReadLambdas.append(lambda)
        }
        else {
            fatalError("A function named = '\(lambda.functionName)' already exists. You may not override.")
        }
    }
    
}
