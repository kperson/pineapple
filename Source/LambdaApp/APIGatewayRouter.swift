import Foundation
import Logging

// MARK: - API Gateway Router

/// Simple prefix-based router for API Gateway requests
///
/// Enables mounting multiple "sub-applications" under different path prefixes
/// within a single Lambda function. Each mounted handler receives requests
/// with the prefix stripped, enabling composable applications that don't
/// need to know their mount point.
///
/// ## Path Stripping Behavior
///
/// When a request matches a prefix, the prefix is stripped:
///
/// | Mount Prefix | Request Path | Stripped Path |
/// |--------------|--------------|---------------|
/// | `/users` | `/users/123` | `/123` |
/// | `/users` | `/users` | `/` |
/// | `/api/v1` | `/api/v1/foo/bar` | `/foo/bar` |
/// | `/` | `/anything` | `/anything` |
/// | `/` | `/` | `/` |
///
/// ## Route Matching Order
///
/// Routes are matched in **registration order** (first match wins).
/// Register specific prefixes before general ones:
///
/// ```swift
/// let router = APIGatewayRouter()
///     .mount("/users/admin", handler: adminHandler)  // Matched first for /users/admin/*
///     .mount("/users", handler: usersHandler)        // Matched for other /users/*
///     .mount("/", handler: fallbackHandler)          // Catch-all (register last)
/// ```
///
/// ## Basic Usage
///
/// ```swift
/// let router = APIGatewayRouter()
///     .mount("/health", handler: { ctx, req, path in
///         return APIGatewayResponse(statusCode: .ok, body: "OK")
///     })
///     .mount("/api", handler: { ctx, req, path in
///         // path = "/users/123" when request is "/api/users/123"
///         return handleAPI(ctx, req, path)
///     })
///
/// let app = LambdaApp()
///     .addAPIGateway(key: "api", router: router)
/// ```
///
/// ## Composing Multiple Applications
///
/// Mount independent handlers that don't need to know their prefix:
///
/// ```swift
/// // Each handler receives paths relative to its mount point
/// let router = APIGatewayRouter()
///     .mount("/users", handler: usersApp.handle)      // usersApp sees /123, not /users/123
///     .mount("/products", handler: productsApp.handle)
///     .mount("/orders", handler: ordersApp.handle)
///
/// let app = LambdaApp()
///     .addAPIGateway(key: "api", router: router)
/// ```
///
/// ## Root Handler
///
/// Use `mount(handler:)` without a prefix for single-handler scenarios
/// or as a catch-all:
///
/// ```swift
/// // Single handler - receives all requests
/// let router = APIGatewayRouter()
///     .mount(handler: myHandler)
///
/// // Or as catch-all after specific routes
/// let router = APIGatewayRouter()
///     .mount("/api", handler: apiHandler)
///     .mount(handler: staticFileHandler)  // Everything else
/// ```
///
/// ## MCP Integration
///
/// Use with MCPLambda's `mountMCP` extension to combine HTTP and MCP:
///
/// ```swift
/// // Import MCPLambda for mountMCP extension
/// let router = APIGatewayRouter()
///     .mount("/health", handler: healthHandler)
///     .mount("/api", handler: restAPIHandler)
///     .mountMCP("/mcp", router: mcpRouter)  // MCP at /mcp/*
///
/// let app = LambdaApp()
///     .addAPIGateway(key: "api", router: router)
/// ```
///
/// ## Handler Signature
///
/// Handlers receive three parameters:
/// - `context: LambdaContext` - Lambda execution context (request ID, logger, etc.)
/// - `request: APIGatewayRequest` - Original API Gateway request (path unchanged)
/// - `path: String` - Stripped path relative to mount point
///
/// ```swift
/// func myHandler(
///     context: LambdaContext,
///     request: APIGatewayRequest,
///     path: String
/// ) async throws -> APIGatewayResponse {
///     // request.path = "/api/users/123" (original)
///     // path = "/users/123" (stripped, if mounted at "/api")
///
///     context.logger.info("Handling \(path)")
///     return APIGatewayResponse(statusCode: .ok, body: "OK")
/// }
/// ```
///
/// ## Error Handling
///
/// Unmatched paths return a 404 JSON response:
///
/// ```json
/// {"error": "No route found for path: /unknown"}
/// ```
public final class APIGatewayRouter: @unchecked Sendable {

    /// Handler that receives context, original request, and stripped path
    public typealias RouteHandler = (LambdaContext, APIGatewayRequest, String) async throws -> APIGatewayResponse

    private var routes: [Route] = []

    public init() {}

    /// Mount a handler at the root (handles all requests)
    ///
    /// Use this when you have a single handler or as a catch-all at the end.
    /// The handler receives the full path unchanged.
    ///
    /// ```swift
    /// let router = APIGatewayRouter()
    ///     .mount(handler: myHandler)  // handles all requests
    /// ```
    ///
    /// - Parameter handler: Handler function receiving (context, request, path)
    /// - Returns: Self for method chaining
    @discardableResult
    public func mount(
        handler: @escaping RouteHandler
    ) -> APIGatewayRouter {
        return mount("/", handler: handler)
    }

    /// Mount a handler at a path prefix
    ///
    /// The handler receives the original request plus the stripped path.
    ///
    /// - Parameters:
    ///   - prefix: Path prefix to match (e.g., "/users", "/api/v1")
    ///   - handler: Handler function receiving (context, request, strippedPath)
    /// - Returns: Self for method chaining
    @discardableResult
    public func mount(
        _ prefix: String,
        handler: @escaping RouteHandler
    ) -> APIGatewayRouter {
        let normalizedPrefix = normalizePrefix(prefix)
        routes.append(Route(prefix: normalizedPrefix, handler: handler))
        return self
    }


    /// Build the router into a Lambda API Gateway handler
    ///
    /// - Returns: Handler function compatible with `LambdaApp.addAPIGateway()`
    public func build() -> (LambdaContext, APIGatewayRequest) async throws -> APIGatewayResponse {
        // Capture routes for the closure
        let capturedRoutes = routes

        return { context, request in
            let path = request.path

            // Find first matching route
            for route in capturedRoutes {
                if let strippedPath = route.matchAndStrip(path) {
                    return try await route.handler(context, request, strippedPath)
                }
            }

            // No route matched
            return APIGatewayResponse(
                statusCode: .notFound,
                headers: ["Content-Type": "application/json"],
                body: "{\"error\": \"No route found for path: \(path)\"}"
            )
        }
    }

    // MARK: - Internal for Testing

    /// Match a path and return the stripped path (exposed for testing)
    internal func matchAndStrip(_ path: String) -> (prefix: String, strippedPath: String)? {
        for route in routes {
            if let stripped = route.matchAndStrip(path) {
                return (route.prefix, stripped)
            }
        }
        return nil
    }

    // MARK: - Private

    private func normalizePrefix(_ prefix: String) -> String {
        var p = prefix
        // Ensure leading slash
        if !p.hasPrefix("/") {
            p = "/" + p
        }
        // Remove trailing slash (unless it's just "/")
        if p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        return p
    }

    private struct Route {
        let prefix: String
        let handler: RouteHandler

        /// Check if path matches prefix, return stripped path if it does
        func matchAndStrip(_ path: String) -> String? {
            // Root prefix - match everything, don't strip
            if prefix == "/" {
                return path
            }

            // Exact match - return root
            if path == prefix {
                return "/"
            }

            // Prefix match with more path
            if path.hasPrefix(prefix + "/") {
                return String(path.dropFirst(prefix.count))  // keeps the leading "/"
            }

            return nil
        }
    }
}

// MARK: - LambdaApp Extension

public extension LambdaApp {

    /// Register an API Gateway router
    ///
    /// Convenience method that builds the router and registers it as an API Gateway handler.
    ///
    /// ```swift
    /// let router = APIGatewayRouter()
    ///     .mount("/users") { ctx, req, path in ... }
    ///     .mount("/products") { ctx, req, path in ... }
    ///
    /// let app = LambdaApp()
    ///     .addAPIGateway(key: "api", router: router)
    /// ```
    ///
    /// - Parameters:
    ///   - key: Handler key for LambdaApp routing
    ///   - router: APIGatewayRouter to register
    /// - Returns: Self for method chaining
    @discardableResult
    func addAPIGateway(key: String, router: APIGatewayRouter) -> LambdaApp {
        return addAPIGateway(key: key, handler: router.build())
    }
}
