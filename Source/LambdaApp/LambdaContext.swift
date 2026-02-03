import Foundation
import Logging

/// Errors that can occur during Lambda context initialization
///
/// These errors indicate problems with the Lambda runtime environment that
/// prevent creating a valid execution context.
public enum LambdaContextError: Error, CustomStringConvertible {
    /// A required Lambda runtime header is missing from the invocation
    ///
    /// - Parameter String: Name of the missing header
    case missingRequiredHeader(String)
    
    /// A Lambda runtime header has an invalid value
    ///
    /// - Parameters:
    ///   - header: Name of the header with invalid value
    ///   - value: The invalid value received
    ///   - reason: Explanation of why the value is invalid
    case invalidHeaderValue(header: String, value: String, reason: String)
    
    public var description: String {
        switch self {
        case .missingRequiredHeader(let header):
            return "Missing required Lambda runtime header: \(header)"
        case .invalidHeaderValue(let header, let value, let reason):
            return "Invalid value for header '\(header)': '\(value)' - \(reason)"
        }
    }
}

/// Protocol defining the Lambda execution context interface
///
/// Provides access to request metadata, logging, and execution environment
/// information during Lambda function execution. This context is passed to
/// every event handler.
///
/// ## Available Information
///
/// - **requestId**: Unique identifier for this invocation (for tracing/debugging)
/// - **traceId**: AWS X-Ray trace ID (if X-Ray tracing is enabled)
/// - **invokedFunctionArn**: Full ARN of the Lambda function being executed
/// - **deadline**: When this invocation will timeout (use for time-budget decisions)
/// - **cognitoIdentity**: Cognito identity info (if invoked via AWS Mobile SDK)
/// - **clientContext**: Client context info (if invoked via AWS Mobile SDK)
/// - **logger**: Pre-configured logger with request metadata
///
/// ## Usage
///
/// ```swift
/// let app = LambdaApp()
///     .addSQS(key: "processor") { context, event in
///         context.logger.info("Request ID: \(context.requestId)")
///
///         // Check time remaining before timeout
///         let timeRemaining = context.deadline.timeIntervalSinceNow
///         if timeRemaining < 5.0 {
///             context.logger.warning("Less than 5 seconds remaining!")
///         }
///
///         // Process event...
///     }
/// ```
public protocol LambdaContext: Sendable {
    /// Unique identifier for this Lambda invocation (AWS request ID)
    ///
    /// Use this for correlating logs, errors, and CloudWatch metrics.
    var requestId: String { get }
    
    /// AWS X-Ray trace ID (if tracing is enabled)
    ///
    /// Format: `Root=1-5759e988-bd862e3fe1be46a994272793;Parent=53995c3f42cd8ad8;Sampled=1`
    var traceId: String? { get }
    
    /// ARN of the Lambda function being invoked
    ///
    /// Example: `arn:aws:lambda:us-east-1:123456789012:function:my-function`
    var invokedFunctionArn: String { get }
    
    /// Deadline when this invocation will timeout
    ///
    /// Use this to determine how much time remains for processing:
    /// ```swift
    /// let timeRemaining = context.deadline.timeIntervalSinceNow
    /// if timeRemaining < 10.0 {
    ///     // Less than 10 seconds left, start wrapping up
    /// }
    /// ```
    var deadline: Date { get }
    
    /// Cognito identity information (if invoked via AWS Mobile SDK)
    ///
    /// Will be `nil` for most invocations. Only populated when using
    /// AWS Mobile SDK with Cognito authentication.
    var cognitoIdentity: String? { get }
    
    /// Client context from AWS Mobile SDK (if provided)
    ///
    /// Will be `nil` for most invocations. Only populated when using
    /// AWS Mobile SDK.
    var clientContext: String? { get }
    
    /// Pre-configured logger with request metadata
    ///
    /// The logger automatically includes:
    /// - `requestId` in log metadata
    /// - `traceId` in log metadata (if available)
    ///
    /// Example logs:
    /// ```
    /// 2024-01-31T12:00:00-0600 info sqs-processor : [requestId: abc-123] Processing message
    /// ```
    var logger: Logger { get }
}

/// Pineapple's implementation of the Lambda execution context
///
/// This struct is created automatically by the Lambda runtime for each invocation.
/// You don't need to create instances yourself - the runtime passes it to your handlers.
///
/// ## Initialization
///
/// The context is initialized from Lambda runtime headers:
/// - `lambda-runtime-aws-request-id` → `requestId`
/// - `lambda-runtime-trace-id` → `traceId`
/// - `lambda-runtime-invoked-function-arn` → `invokedFunctionArn`
/// - `lambda-runtime-deadline-ms` → `deadline`
/// - `lambda-runtime-cognito-identity` → `cognitoIdentity`
/// - `lambda-runtime-client-context` → `clientContext`
///
/// If required headers are missing or malformed, initialization throws `LambdaContextError`.
public struct PineappleLambdaContext: LambdaContext {
    
    public let requestId: String
    public let traceId: String?
    public let invokedFunctionArn: String
    public let deadline: Date
    public let cognitoIdentity: String?
    public let clientContext: String?
    public var logger: Logger
    
    /// Create a Lambda context from runtime headers
    ///
    /// This initializer is used internally by the Lambda runtime. You typically
    /// don't need to call this yourself.
    ///
    /// - Parameters:
    ///   - requestId: AWS request ID for this invocation
    ///   - headers: Lambda runtime headers from the invocation
    ///   - logger: Logger instance to use for this context
    /// - Throws: `LambdaContextError` if required headers are missing or invalid
    public init(requestId: String, headers: [String: String], logger: Logger) throws {
        self.logger = logger
        self.requestId = requestId
        // Extract Lambda runtime headers
        self.traceId = headers["lambda-runtime-trace-id"]

        guard let functionArn = headers["lambda-runtime-invoked-function-arn"] else {
            throw LambdaContextError.missingRequiredHeader("lambda-runtime-invoked-function-arn")
        }
        self.invokedFunctionArn = functionArn
        
        self.cognitoIdentity = headers["lambda-runtime-cognito-identity"]
        self.clientContext = headers["lambda-runtime-client-context"]
        
        // Calculate deadline from Lambda-Runtime-Deadline-Ms header
        guard let deadlineMs = headers["lambda-runtime-deadline-ms"] else {
            throw LambdaContextError.missingRequiredHeader("lambda-runtime-deadline-ms")
        }
    
        guard let deadlineMsDoubleValue = Double(deadlineMs) else {
            throw LambdaContextError.invalidHeaderValue(
                header: "lambda-runtime-deadline-ms",
                value: deadlineMs,
                reason: "Unable to convert to numeric value"
            )
        }
        self.deadline = Date(timeIntervalSince1970: deadlineMsDoubleValue / 1000.0)

        self.logger[metadataKey: "requestId"] = .string(requestId)
        if let traceId = self.traceId {
            self.logger[metadataKey: "traceId"] = .string(traceId)
        }
    }
}
