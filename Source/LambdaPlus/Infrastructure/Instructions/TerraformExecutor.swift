import Foundation


public class TerraformExecutor: BuildInstructionsExecutor {
    
    public struct ExecutorDefaults {
        
        public let memory: Int
        public let timeout: Int
        
        public init(memory: Int = 512, timeout: Int = 30) {
            self.memory = memory
            self.timeout = timeout
        }
        
    }
    
    public let defaults: ExecutorDefaults
    public let appName: String
    public let nameResolver: NameResolver
    public let handlerEnv: String
    public let outDir: URL
    
    public init(
        appName: String = "app",
        handlerEnv: String = "MY_HANDLER",
        outDir: URL? = nil,
        defaults: ExecutorDefaults = ExecutorDefaults(),
        nameResolver: NameResolver = NameResolver()
    ) {
        self.outDir = outDir ?? URL(fileURLWithPath: "Build/")
        self.defaults = defaults
        self.handlerEnv = handlerEnv
        self.appName = appName
        self.nameResolver = nameResolver
    }
    
    var moduleBaseUrl: String {
        return "../terraform-support"
    }
    
    private var roleAttachements = Set<String>()
    
    public func build(instructions: BuildInstructions) throws {
        try removeManagedFiles()
        let files = buildFiles(instructions: instructions)
        try files.saveFiles(baseDir: outDir)
    }
    
    public func removeManagedFiles() throws {
        let manager = FileManager.default
        let contents = try manager.contentsOfDirectory(
            at: outDir,
            includingPropertiesForKeys: nil
        )
        for url in contents {
            let fileBaseName = url.lastPathComponent.lowercased()
            if  fileBaseName.hasSuffix(".tf")
                && (fileBaseName.hasPrefix("pineapple-") || fileBaseName.hasPrefix("pineapple_")) {
                try manager.removeItem(at: url)
            }
        }
    }
    
    public func buildFiles(instructions: BuildInstructions) -> [BuildFile] {
        var files: [BuildFile] = []
        if !instructions.snsTopics.isEmpty {
            let text = instructions.snsTopics
                .map {
                    let (topicText, roleAttachement) = snsTopicText(t: $0)
                    roleAttachements.insert(roleAttachement)
                    return topicText
                }
                .joined(separator: "\n\n") + "\n"
            files.append(BuildFile(path: "pineapple_pubsub_topics.tf", data: text))
        }
        
        if !instructions.snsReadLambdas.isEmpty {
            let text = instructions.snsReadLambdas
                .map { snsReadLambdaText(lambda: $0) }
                .joined(separator: "\n\n") + "\n"
            files.append(BuildFile(path: "pineapple_pubsub_readers.tf", data: text))
        }
        return files
        
    }
    
    public func snsReadLambdaText(lambda: SNSReadLambda) -> String {
        let envs = lambda.settings.environmentVariables
        let text = """
        # Begin SNS Read Lambda: \(lambda.functionName.lowercased())
        
        module "pubsub_read_\(lambda.functionName.lowercased())" {
          source        = "\(moduleBaseUrl)/sns-lambda"
          depends_on    = [module.ecr_push]
          topic_arn     = \(lambda.topicArn.terraformStr)
          function_name = format("%s-%s-%s", terraform.workspace, "\(appName)", "\(lambda.functionName)")
          role          = module.lambda_role_arn.out
          ecr_repo_name = module.ecr_push.ecr_repo_name
          ecr_repo_tag  = module.ecr_push.ecr_repo_tag
          memory_size   = \(lambda.settings.memory ?? defaults.memory)
          timeout       = \(lambda.settings.timeout ?? defaults.timeout)
          \(lambdaEnvs(envs: envs, functionName: lambda.functionName))
        }
        
        # End SNS Read Lambda: \(lambda.functionName.lowercased())
        """
        return text
    }
    
    private func lambdaEnvs(envs: [String : String], functionName: String) -> String {
        var allEnvs = envs.keys.sorted().map { k in
            return "\(k) = \"\(envs[k]!)\""
        }
        allEnvs.append("\(handlerEnv) = \"\(nameResolver.functionHandler(functionName))\"")
        let envText = allEnvs.joined(separator: ",\n")
        let text = """
        env = merge(
          local.env,
          local.managedEnv,
          {   
              \(envText)
          }
        )
        """
        return text
    }
    
    public func snsTopicText(t: SNSTopic) -> (String, String) {
        let lowerCaseName = t.name.lowercased()
        let lowerCaseNameTopic = "\(lowerCaseName)_topic"
        let fullName = t.isFifo ? "\(lowerCaseName).fifo" : lowerCaseName
        let text = """
        # Begin SNS Topic: \(t.name)
        
        resource "aws_sns_topic" "\(t.name.lowercased())" {
            name       = format("%s-%s-%s", terraform.workspace, "\(appName)", "\(fullName)")
            fifo_topic = \(t.isFifo)
        }
        
        data "aws_iam_policy_document" "\(lowerCaseNameTopic)" {
          statement {
            actions = [
              "sns:Publish"
            ]
            resources = [
                aws_sns_topic.\(lowerCaseName).arn
            ]
          }
        }
        
        resource "aws_iam_policy" "\(lowerCaseNameTopic)" {
          policy = data.aws_iam_policy_document."\(lowerCaseNameTopic).json
        }

        module "\(lowerCaseNameTopic)_role_attatchment" {
          source     = "github.com/kperson/terraform-modules//aws_role_attachment"
          role       = aws_iam_role.lambda.name
          policy_arn = aws_iam_policy."\(lowerCaseNameTopic).arn
        }
        
        # End SNS Topic: \(t.name)
        """
        return (text, "\(lowerCaseName)_topic")
    }
    
}

extension BuildValue where T == String {
 
    var terraformStr: String {
        switch self {
        case .literal(let l): return "\"\(l)\""
        case .ref(let r): return r
        }
    }
    
}

