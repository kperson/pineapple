import Hummingbird
import LambdaApp
import Logging
import NIOCore

// MARK: - Lambda Request Context Source

/// Source for creating LambdaRequestContext
///
/// Contains all the information needed to create a LambdaRequestContext,
/// including Lambda execution context and the original API Gateway request.
public struct LambdaRequestContextSource: RequestContextSource {

    /// Logger for the request (from Lambda context)
    public let logger: Logger

    /// AWS Lambda execution context
    public let lambdaContext: LambdaContext

    /// Original API Gateway request
    public let apiGatewayRequest: APIGatewayRequest

    /// Create a new LambdaRequestContextSource
    ///
    /// - Parameters:
    ///   - lambdaContext: AWS Lambda execution context
    ///   - apiGatewayRequest: Original API Gateway request
    public init(lambdaContext: LambdaContext, apiGatewayRequest: APIGatewayRequest) {
        self.logger = lambdaContext.logger
        self.lambdaContext = lambdaContext
        self.apiGatewayRequest = apiGatewayRequest
    }
}

// MARK: - Lambda Request Context

/// Custom Hummingbird RequestContext providing access to AWS Lambda execution context
///
/// `LambdaRequestContext` bridges Hummingbird's request context with AWS Lambda's execution
/// environment, enabling route handlers to access both Hummingbird's standard routing features
/// (path parameters, request data) and Lambda-specific metadata (request ID, deadline, ARN).
///
/// ## Available Information
///
/// From Hummingbird's `BasicRequestContext`:
/// - `coreContext`: Core request storage (allocator, logger)
/// - `parameters`: Path parameters extracted from route patterns (e.g., `/users/:id`)
///
/// From Lambda:
/// - `lambdaContext`: Lambda execution context (request ID, deadline, function ARN, logger)
/// - `apiGatewayRequest`: Original API Gateway request with headers, stage variables, etc.
///
/// ## Example Usage
///
/// ```swift
/// let router = Router(context: LambdaRequestContext.self)
///
/// router.get("users/:id") { req, ctx in
///     // Access path parameters from Hummingbird
///     let userId = ctx.parameters.get("id") ?? "unknown"
///
///     // Access Lambda-specific context
///     let requestId = ctx.lambdaContext.requestId
///     let timeRemaining = ctx.lambdaContext.deadline.timeIntervalSinceNow
///
///     ctx.lambdaContext.logger.info("Handling user \(userId)")
///
///     // Access original API Gateway headers
///     if let authHeader = ctx.apiGatewayRequest.headers["Authorization"] {
///         // Validate auth...
///     }
///
///     return "User: \(userId)"
/// }
/// ```
///
/// ## Creating the Context
///
/// You don't create `LambdaRequestContext` directly. It's created by the `HummingbirdLambdaAdapter`
/// when converting API Gateway requests to Hummingbird requests:
///
/// ```swift
/// let router = Router(context: LambdaRequestContext.self)
/// router.get("hello") { _, _ in "Hello!" }
///
/// let app = LambdaApp()
///     .addHummingbird(key: "api", router: router)
/// ```
public struct LambdaRequestContext: RequestContext {

    /// The source type for this context
    public typealias Source = LambdaRequestContextSource

    /// Core request context storage (allocator, logger)
    public var coreContext: CoreRequestContextStorage

    /// AWS Lambda execution context
    ///
    /// Provides access to:
    /// - `requestId`: Unique identifier for this Lambda invocation
    /// - `deadline`: When this invocation will timeout
    /// - `invokedFunctionArn`: Full ARN of the Lambda function
    /// - `logger`: Pre-configured logger with request metadata
    public let lambdaContext: LambdaContext

    /// Original API Gateway request
    ///
    /// Provides access to:
    /// - `headers`: HTTP headers from the client
    /// - `path`: Request path
    /// - `queryStringParameters`: Query string parameters
    /// - `stageVariables`: API Gateway stage variables
    /// - `requestContext.authorizer`: Cognito authorizer claims (if configured)
    public let apiGatewayRequest: APIGatewayRequest

    /// Create a new LambdaRequestContext from source
    ///
    /// This initializer is called by the router when processing requests.
    /// You typically don't need to call this directly.
    ///
    /// - Parameter source: Source containing Lambda context and API Gateway request
    public init(source: LambdaRequestContextSource) {
        self.coreContext = .init(source: source)
        self.lambdaContext = source.lambdaContext
        self.apiGatewayRequest = source.apiGatewayRequest
    }
}
