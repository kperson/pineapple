import Foundation
import Hummingbird
import HummingbirdCore
import HTTPTypes
import NIOCore
import LambdaApp
import Logging

// MARK: - Hummingbird to Lambda Adapter

/// Bridges Hummingbird Router to AWS Lambda via API Gateway
///
/// `HummingbirdLambdaAdapter` converts between API Gateway requests/responses and Hummingbird's
/// request/response types, enabling standard Hummingbird routing code to run on AWS Lambda.
///
/// ## Architecture
///
/// ```
/// API Gateway → Lambda → HummingbirdLambdaAdapter → Hummingbird Router → Route Handler
///                              ↓                           ↓
///                        APIGatewayRequest → Request     Response → APIGatewayResponse
/// ```
///
/// The adapter:
/// 1. Converts `APIGatewayRequest` to Hummingbird `Request`
/// 2. Creates `LambdaRequestContext` with Lambda context and original request
/// 3. Routes through Hummingbird router
/// 4. Converts Hummingbird `Response` to `APIGatewayResponse`
///
/// ## Basic Usage
///
/// ```swift
/// // Create Hummingbird router with Lambda context
/// let router = Router(context: LambdaRequestContext.self)
/// router.get("users/:id") { req, ctx in
///     let id = ctx.parameters.get("id") ?? "unknown"
///     return "User: \(id)"
/// }
///
/// // Register with LambdaApp
/// let app = LambdaApp()
///     .addHummingbird(key: "api", router: router)
///
/// app.run(handlerKey: "api")
/// ```
///
/// ## Request Conversion
///
/// | API Gateway | Hummingbird |
/// |-------------|-------------|
/// | `httpMethod` | `head.method` |
/// | `path` + query params | `uri` |
/// | `headers` | `head.headerFields` |
/// | `body` (+ base64 decode) | `body` |
///
/// ## Response Conversion
///
/// | Hummingbird | API Gateway |
/// |-------------|-------------|
/// | `status` | `statusCode` |
/// | `headers` | `headers` |
/// | `body` (collected) | `body` + `isBase64Encoded` |
///
/// ## Response Encoding
///
/// All response bodies are base64-encoded for reliable transmission through API Gateway.
/// This handles both text and binary content correctly without needing content-type detection.
public final class HummingbirdLambdaAdapter: @unchecked Sendable {

    public init() {}

    /// Bridge a Hummingbird Router to a Lambda API Gateway handler
    ///
    /// Creates a Lambda handler function that:
    /// 1. Converts API Gateway request to Hummingbird request
    /// 2. Creates LambdaRequestContext with Lambda context
    /// 3. Routes through the provided router
    /// 4. Converts Hummingbird response to API Gateway response
    ///
    /// - Parameter router: Hummingbird router configured with `LambdaRequestContext`
    /// - Returns: Lambda handler function compatible with `LambdaApp.addAPIGateway()`
    public func bridge(
        _ router: Router<LambdaRequestContext>
    ) -> (LambdaContext, APIGatewayRequest) async throws -> APIGatewayResponse {
        return bridge(router, pathOverride: nil)
    }

    /// Bridge a Hummingbird Router with optional path override
    ///
    /// When `pathOverride` is provided, uses that path for routing instead of
    /// the API Gateway request path. This enables mounting Hummingbird under
    /// a prefix via `APIGatewayRouter.mountHummingbird()`.
    ///
    /// - Parameters:
    ///   - router: Hummingbird router configured with `LambdaRequestContext`
    ///   - pathOverride: Path to use for routing (nil = use request.path)
    /// - Returns: Lambda handler function
    public func bridge(
        _ router: Router<LambdaRequestContext>,
        pathOverride: String?
    ) -> (LambdaContext, APIGatewayRequest) async throws -> APIGatewayResponse {
        // Build the router responder once
        let responder = router.buildResponder()

        return { [self] lambdaContext, apiGwRequest in
            // Convert API Gateway request to Hummingbird request
            let (request, requestContext) = self.convertRequest(
                apiGwRequest,
                lambdaContext: lambdaContext,
                pathOverride: pathOverride
            )

            // Route through Hummingbird
            let response = try await responder.respond(to: request, context: requestContext)

            // Convert Hummingbird response to API Gateway response
            return try await self.convertResponse(response)
        }
    }

    // MARK: - Request Conversion

    /// Convert API Gateway request to Hummingbird Request and Context
    private func convertRequest(
        _ apiGwRequest: APIGatewayRequest,
        lambdaContext: LambdaContext,
        pathOverride: String?
    ) -> (Request, LambdaRequestContext) {
        // Build the URI with path and query string using URLComponents for proper encoding
        let path = pathOverride ?? apiGwRequest.path
        let uri: String
        let queryParams = apiGwRequest.queryStringParameters
        if !queryParams.isEmpty {
            var components = URLComponents()
            components.path = path
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            // URLComponents.string properly encodes the query parameters
            uri = components.string ?? path
        } else {
            uri = path
        }

        // Convert HTTP method
        let method = HTTPRequest.Method(rawValue: apiGwRequest.httpMethod.rawValue) ?? .get

        // Convert headers
        var headerFields = HTTPFields()
        let headers = apiGwRequest.headers
        for (name, value) in headers {
            if let fieldName = HTTPField.Name(name) {
                headerFields[fieldName] = value
            }
        }

        // Decode body
        let bodyData: Data?
        if let body = apiGwRequest.body {
            if apiGwRequest.isBase64Encoded {
                bodyData = Data(base64Encoded: body)
            } else {
                bodyData = body.data(using: .utf8)
            }
        } else {
            bodyData = nil
        }

        // Create request body
        let requestBody: RequestBody
        if let data = bodyData {
            let buffer = ByteBuffer(data: data)
            requestBody = .init(buffer: buffer)
        } else {
            requestBody = .init(buffer: ByteBuffer())
        }

        // Build Hummingbird Request
        let head = HTTPRequest(method: method, scheme: "https", authority: nil, path: uri, headerFields: headerFields)
        let request = Request(head: head, body: requestBody)

        // Create context source
        let source = LambdaRequestContextSource(
            lambdaContext: lambdaContext,
            apiGatewayRequest: apiGwRequest
        )

        // Create LambdaRequestContext
        let context = LambdaRequestContext(source: source)

        return (request, context)
    }

    // MARK: - Response Conversion

    /// Convert Hummingbird Response to API Gateway Response
    private func convertResponse(_ response: Response) async throws -> APIGatewayResponse {
        // Convert status code
        let statusCode = HTTPResponse.Status(code: Int(response.status.code), reasonPhrase: response.status.reasonPhrase)

        // Convert headers
        var headers: [String: String] = [:]
        for field in response.headers {
            headers[field.name.rawName] = field.value
        }

        // Collect response body using a custom writer
        let writer = CollectingResponseBodyWriter()
        try await response.body.write(writer)

        // Combine collected buffers into a single Data
        var bodyData = Data()
        for buffer in writer.buffers {
            bodyData.append(contentsOf: buffer.readableBytesView)
        }

        // Always base64 encode - simpler and handles all content types correctly
        let body: String?
        if bodyData.isEmpty {
            body = nil
        } else {
            body = bodyData.base64EncodedString()
        }

        return APIGatewayResponse(
            statusCode: statusCode,
            headers: headers.isEmpty ? nil : headers,
            body: body,
            isBase64Encoded: !bodyData.isEmpty
        )
    }
}

// MARK: - Collecting Response Body Writer

/// A ResponseBodyWriter that collects all written buffers
final class CollectingResponseBodyWriter: ResponseBodyWriter {
    var buffers: [ByteBuffer] = []

    func write(_ buffer: ByteBuffer) async throws {
        buffers.append(buffer)
    }

    func finish(_ trailers: HTTPFields?) async throws {
        // Nothing to do - we've collected the buffers
    }
}

// MARK: - LambdaApp Extension

/// Convenience extension for adding Hummingbird routers to LambdaApp
public extension LambdaApp {

    /// Add Hummingbird Router as a Lambda handler
    ///
    /// Registers a Hummingbird router as a Lambda API Gateway handler. The router
    /// must be configured with `LambdaRequestContext` to access Lambda-specific context.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let router = Router(context: LambdaRequestContext.self)
    /// router.get("users/:id") { req, ctx in
    ///     let id = ctx.parameters.get("id") ?? "unknown"
    ///     return "User: \(id)"
    /// }
    /// router.post("users") { req, ctx in
    ///     // Create user...
    ///     return Response(status: .created)
    /// }
    ///
    /// let app = LambdaApp()
    ///     .addHummingbird(key: "api", router: router)
    ///     .addSQS(key: "queue") { ctx, event in ... }
    ///
    /// app.run(handlerKey: ProcessInfo.processInfo.environment["MY_HANDLER"])
    /// ```
    ///
    /// - Parameters:
    ///   - key: Handler key for LambdaApp routing (matches `MY_HANDLER` env var)
    ///   - router: Hummingbird router configured with `LambdaRequestContext`
    /// - Returns: Self for method chaining
    @discardableResult
    func addHummingbird(
        key: String,
        router: Router<LambdaRequestContext>
    ) -> LambdaApp {
        let adapter = HummingbirdLambdaAdapter()
        return addAPIGateway(key: key, handler: adapter.bridge(router))
    }
}

// MARK: - APIGatewayRouter Extension

/// Extension to mount Hummingbird routers within an APIGatewayRouter
///
/// Enables mixing Hummingbird routes with other handlers (MCP, custom HTTP, etc.)
/// under different path prefixes within a single Lambda function.
public extension APIGatewayRouter {

    /// Mount a Hummingbird router at a path prefix
    ///
    /// The Hummingbird router receives requests with the prefix stripped, allowing
    /// route handlers to be unaware of their mount point.
    ///
    /// ## Path Rewriting
    ///
    /// ```
    /// Mount: "/api"
    /// Request: "/api/users/123"
    /// Hummingbird sees: "/users/123"
    /// ```
    ///
    /// ## Example
    ///
    /// ```swift
    /// let hbRouter = Router(context: LambdaRequestContext.self)
    /// hbRouter.get("users/:id") { req, ctx in
    ///     return "User: \(ctx.parameters.get("id") ?? "?")"
    /// }
    ///
    /// let apiRouter = APIGatewayRouter()
    ///     .mount("/health") { ctx, req, path in
    ///         APIGatewayResponse(statusCode: .ok, body: "OK")
    ///     }
    ///     .mountHummingbird("/api", router: hbRouter)
    ///
    /// let app = LambdaApp()
    ///     .addAPIGateway(key: "http", router: apiRouter)
    /// ```
    ///
    /// - Parameters:
    ///   - prefix: Path prefix for Hummingbird routes (e.g., "/api")
    ///   - router: Hummingbird router configured with `LambdaRequestContext`
    /// - Returns: Self for method chaining
    @discardableResult
    func mountHummingbird(
        _ prefix: String,
        router: Router<LambdaRequestContext>
    ) -> APIGatewayRouter {
        let adapter = HummingbirdLambdaAdapter()
        return mount(prefix) { lambdaContext, apiGwRequest, strippedPath in
            let handler = adapter.bridge(router, pathOverride: strippedPath)
            return try await handler(lambdaContext, apiGwRequest)
        }
    }

    /// Mount a Hummingbird router at the root
    ///
    /// Use this when Hummingbird handles all requests for this Lambda.
    ///
    /// - Parameter router: Hummingbird router configured with `LambdaRequestContext`
    /// - Returns: Self for method chaining
    @discardableResult
    func mountHummingbird(
        router: Router<LambdaRequestContext>
    ) -> APIGatewayRouter {
        return mountHummingbird("/", router: router)
    }
}
