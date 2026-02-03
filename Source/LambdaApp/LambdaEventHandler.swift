import Foundation

/// Base protocol for Lambda event handlers that process events and return results
///
/// Use this protocol when your Lambda function needs to return a response, such as:
/// - API Gateway handlers returning HTTP responses
/// - Custom event processors returning structured data
///
/// ## Example
///
/// ```swift
/// struct MyAPIHandler: LambdaEventHandler {
///     typealias Event = APIGatewayRequest
///     typealias Output = APIGatewayResponse
///
///     func handleEvent(context: LambdaContext, event: APIGatewayRequest) async throws -> APIGatewayResponse {
///         context.logger.info("Processing request: \(event.path)")
///         return APIGatewayResponse(statusCode: .ok, body: "Success")
///     }
/// }
/// ```
///
/// For most use cases, prefer the fluent builder API (`.addAPIGateway()`) over
/// implementing this protocol directly.
public protocol LambdaEventHandler {
    /// The event type this handler processes (must be Decodable from JSON)
    associatedtype Event: Decodable
    
    /// The output type this handler returns (must be Encodable to JSON)
    associatedtype Output: Encodable
    
    /// Process an event and return a result
    ///
    /// - Parameters:
    ///   - context: Lambda execution context with request metadata and logger
    ///   - event: Decoded event payload
    /// - Returns: Response to send back to Lambda runtime
    /// - Throws: Any errors that should be reported as Lambda invocation errors
    func handleEvent(context: LambdaContext, event: Event) async throws -> Output
}

/// Base protocol for Lambda event handlers that process events without returning results
///
/// Use this protocol for event-driven handlers that don't need to return data, such as:
/// - SQS message processors
/// - SNS notification handlers
/// - S3 event processors
/// - DynamoDB Stream consumers
/// - EventBridge event handlers
///
/// ## Example
///
/// ```swift
/// struct MySQSHandler: LambdaVoidEventHandler {
///     typealias Event = SQSEvent
///
///     func handleEvent(context: LambdaContext, event: SQSEvent) async throws {
///         for record in event.records {
///             context.logger.info("Processing message: \(record.messageId)")
///             // Process message...
///         }
///     }
/// }
/// ```
///
/// For most use cases, prefer the fluent builder API (`.addSQS()`, `.addS3()`, etc.)
/// over implementing this protocol directly.
public protocol LambdaVoidEventHandler {
    /// The event type this handler processes (must be Decodable from JSON)
    associatedtype Event: Decodable
    
    /// Process an event without returning a result
    ///
    /// - Parameters:
    ///   - context: Lambda execution context with request metadata and logger
    ///   - event: Decoded event payload
    /// - Throws: Any errors that should be reported as Lambda invocation errors
    func handleEvent(context: LambdaContext, event: Event) async throws
}
