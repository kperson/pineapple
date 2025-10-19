import Foundation
import Logging

/**
 Protocol defining the Lambda execution context interface
 
 Provides access to request metadata, logging, and execution environment
 information during Lambda function execution.
 */
public protocol LambdaContext {
    var requestId: String { get }
    var traceId: String? { get }
    var invokedFunctionArn: String { get }
    var deadline: Date { get }
    var cognitoIdentity: String? { get }
    var clientContext: String? { get }
    var logger: Logger { get }
}

public struct PineappleLambdaContext: LambdaContext {
    
    public let requestId: String
    public let traceId: String?
    public let invokedFunctionArn: String
    public let deadline: Date
    public let cognitoIdentity: String?
    public let clientContext: String?
    public var logger: Logger
    
    public init(requestId: String, headers: [String: String], logger: Logger) {
        self.logger = logger
        self.requestId = requestId
        // Extract Lambda runtime headers
        self.traceId = headers["lambda-runtime-trace-id"]

        guard let functionArn = headers["lambda-runtime-invoked-function-arn"] else {
            fatalError("Missing required Lambda-Runtime-Invoked-Function-Arn header from AWS Lambda Runtime")
        }
        self.invokedFunctionArn = functionArn
        
        self.cognitoIdentity = headers["lambda-runtime-cognito-identity"]
        self.clientContext = headers["lambda-runtime-client-context"]
        
        // Calculate deadline from Lambda-Runtime-Deadline-Ms header
        guard let deadlineMs = headers["lambda-runtime-deadline-ms"] else {
            fatalError("Missing required Lambda-Runtime-Deadline-Ms header from AWS Lambda Runtime")
        }
    
        guard let deadlineMsDoubleValue = Double(deadlineMs) else {
            fatalError("Unable to convert Lambda-Runtime-Deadline-Ms to numeric value")
        }
        self.deadline = Date(timeIntervalSince1970: deadlineMsDoubleValue / 1000.0)

        self.logger[metadataKey: "requestId"] = .string(requestId)
        if let traceId = self.traceId {
            self.logger[metadataKey: "traceId"] = .string(traceId)
        }
    }
}
