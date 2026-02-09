import Hummingbird
import LambdaApp

/// Fluent builder for Hummingbird applications deployed to AWS Lambda
///
/// `App` provides a consistent closure-based API for configuring Hummingbird routers to run
/// on AWS Lambda via API Gateway. It encapsulates the adapter and router configuration
/// into a single, easy-to-use interface that matches the patterns used in MCPLambda
/// and MCPHummingbird.
///
/// ## Architecture
///
/// ```
/// API Gateway → Lambda → HummingbirdLambda.App → HummingbirdLambdaAdapter → Router → Handler
/// ```
///
/// The App class:
/// 1. Creates a `Router<LambdaRequestContext>` for standard Hummingbird routing
/// 2. Provides the router to your configure closure
/// 3. Generates a Lambda handler via internal bridge
/// 4. Integrates with `LambdaApp` for multi-handler deployments
///
/// ## Basic Usage
///
/// ```swift
/// // Configure Hummingbird app with closure-based pattern
/// let hbApp = HummingbirdLambda.App { router in
///     router.get("hello") { _, _ in "Hello, World!" }
///
///     router.get("users/:id") { req, ctx in
///         let id = ctx.parameters.get("id") ?? "unknown"
///         return "User: \(id)"
///     }
///
///     router.post("users") { req, ctx in
///         // Parse request body, create user...
///         return Response(status: .created)
///     }
/// }
///
/// // Integrate with LambdaApp
/// let lambdaApp = LambdaApp()
///     .addHummingbird(key: "api", hbApp: hbApp)
///
/// lambdaApp.run(handlerKey: "api")
/// ```
///
/// ## Accessing Lambda Context
///
/// Route handlers receive `LambdaRequestContext` which provides access to both
/// Hummingbird features and Lambda-specific context:
///
/// ```swift
/// let hbApp = HummingbirdLambda.App { router in
///     router.get("info") { req, ctx in
///         // Hummingbird path parameters
///         let userId = ctx.parameters.get("userId")
///
///         // Lambda context
///         let requestId = ctx.lambdaContext.requestId
///         let timeRemaining = ctx.lambdaContext.deadline.timeIntervalSinceNow
///
///         // Original API Gateway request
///         let authHeader = ctx.apiGatewayRequest.headers?["Authorization"]
///
///         ctx.lambdaContext.logger.info("Handling request \(requestId)")
///
///         return "Request ID: \(requestId)"
///     }
/// }
/// ```
///
/// ## Multi-Handler Lambda
///
/// Combine Hummingbird with other event handlers in a single Lambda:
///
/// ```swift
/// let hbApp = HummingbirdLambda.App { router in
///     router.get("users/:id") { req, ctx in ... }
///     router.post("users") { req, ctx in ... }
/// }
///
/// let lambdaApp = LambdaApp()
///     .addSQS(key: "queue") { ctx, event in ... }
///     .addHummingbird(key: "api", hbApp: hbApp)
///     .addS3(key: "files") { ctx, event in ... }
///
/// // Set MY_HANDLER environment variable to: "queue", "api", or "files"
/// lambdaApp.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
/// ```
///
/// ## Response Types
///
/// Hummingbird supports various response types:
///
/// ```swift
/// router.get("text") { _, _ in "Plain text" }
///
/// router.get("json") { _, _ in
///     let data = try! JSONEncoder().encode(["key": "value"])
///     return Response(
///         status: .ok,
///         headers: [.contentType: "application/json"],
///         body: .init(byteBuffer: ByteBuffer(data: data))
///     )
/// }
///
/// router.get("status") { _, _ in Response(status: .noContent) }
/// ```
///
/// ## Design Pattern
///
/// This class enforces a closure-based configuration pattern to reduce cognitive load:
/// - Router is private (only configurable in closure)
/// - Single integration method via `LambdaApp.addHummingbird()`
/// - Consistent with `MCPLambda.App` pattern
public class App {

    /// The configured Hummingbird router
    internal let router: Router<LambdaRequestContext>

    /// Create a new Hummingbird Lambda app with closure-based configuration
    ///
    /// The configure closure receives the router, allowing you to:
    /// - Add route handlers with `.get()`, `.post()`, `.put()`, `.delete()`, etc.
    /// - Configure middleware via `.middlewares.add()`
    /// - Set up route groups for organized routes
    ///
    /// ## Example
    ///
    /// ```swift
    /// let hbApp = HummingbirdLambda.App { router in
    ///     // Add routes
    ///     router.get("hello") { _, _ in "Hello!" }
    ///
    ///     // Route with path parameters
    ///     router.get("users/:id") { req, ctx in
    ///         let id = ctx.parameters.get("id") ?? "unknown"
    ///         return "User: \(id)"
    ///     }
    ///
    ///     // Route group for organized paths
    ///     router.group("api/v1") { api in
    ///         api.get("status") { _, _ in "OK" }
    ///         api.post("data") { req, ctx in ... }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter configure: Optional closure to configure the router
    public init(
        configure: ((Router<LambdaRequestContext>) -> Void)? = nil
    ) {
        self.router = Router(context: LambdaRequestContext.self)
        configure?(router)
    }

    /// Creates the Lambda API Gateway handler function
    ///
    /// This method is called by the `LambdaApp.addHummingbird()` extension to
    /// generate the handler function that bridges API Gateway requests to Hummingbird.
    ///
    /// - Returns: Lambda handler function
    internal func createHandler() -> (LambdaContext, APIGatewayRequest) async throws -> APIGatewayResponse {
        let adapter = HummingbirdLambdaAdapter()
        return adapter.bridge(router)
    }
}

// MARK: - LambdaApp Extension for App

/// LambdaApp extension for integrating HummingbirdLambda.App
public extension LambdaApp {

    /// Add HummingbirdLambda.App to LambdaApp's multi-handler registry
    ///
    /// Registers the Hummingbird app as a Lambda handler with the specified key.
    /// The key is used to route Lambda invocations when multiple handlers are
    /// registered (via `MY_HANDLER` environment variable).
    ///
    /// ## Example
    ///
    /// ```swift
    /// let hbApp = HummingbirdLambda.App { router in
    ///     router.get("users/:id") { req, ctx in
    ///         let id = ctx.parameters.get("id") ?? "unknown"
    ///         return "User: \(id)"
    ///     }
    /// }
    ///
    /// let lambdaApp = LambdaApp()
    ///     .addSQS(key: "queue") { ctx, event in ... }
    ///     .addHummingbird(key: "api", hbApp: hbApp)
    ///
    /// // Set MY_HANDLER=api to route to the Hummingbird handler
    /// lambdaApp.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
    /// ```
    ///
    /// - Parameters:
    ///   - key: Handler key for routing (matches `MY_HANDLER` environment variable)
    ///   - hbApp: Configured HummingbirdLambda.App
    /// - Returns: Self for method chaining
    @discardableResult
    func addHummingbird(key: String, hbApp: App) -> LambdaApp {
        addAPIGateway(key: key, handler: hbApp.createHandler())
    }
}

// MARK: - V2 App

/// Fluent builder for Hummingbird applications deployed to AWS Lambda via API Gateway HTTP API (V2)
///
/// Mirrors `App` but uses V2 types for lower latency and lower cost HTTP API.
public class V2App {

    internal let router: Router<LambdaV2RequestContext>

    /// Create a new Hummingbird Lambda V2 app with closure-based configuration
    public init(
        configure: ((Router<LambdaV2RequestContext>) -> Void)? = nil
    ) {
        self.router = Router(context: LambdaV2RequestContext.self)
        configure?(router)
    }

    /// Creates the Lambda API Gateway V2 handler function
    internal func createHandler() -> (LambdaContext, APIGatewayV2Request) async throws -> APIGatewayV2Response {
        let adapter = HummingbirdLambdaAdapter()
        return adapter.bridgeV2(router)
    }
}

// MARK: - LambdaApp Extension for V2App

public extension LambdaApp {

    @discardableResult
    func addHummingbirdV2(key: String, hbApp: V2App) -> LambdaApp {
        addAPIGatewayV2(key: key, handler: hbApp.createHandler())
    }
}
