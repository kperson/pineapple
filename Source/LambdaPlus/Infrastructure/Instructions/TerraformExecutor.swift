import Foundation

public class TerraformExecutor: BuildInstructionsExecutor {
    
    
    public init() {  }
    
    public func build(instructions: BuildInstructions) {
//        let snsTopicText = instructions.snsTopics.map(snsTopicTerraform).joined(separator: "\n\n")

    }
    
    public func snsTopicText(t: SNSTopic) -> String {
        let fullName = t.isFifo ? "\(t.name.lowercased()).fifo" : t.name.lowercased()
        let text = """
        resource "aws_sns_topic" "\(t.name.lowercased())" {
            name       = format("%s_%s", terraform.workspace, "\(fullName)")
            fifo_topic = \(t.isFifo)
        }
        """
        return text
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

