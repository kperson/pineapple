import Foundation
import Logging

// MARK: - API Gateway V2 Router

/// Simple prefix-based router for API Gateway HTTP API (V2) requests
///
/// Mirrors `APIGatewayRouter` but uses V2 types (`APIGatewayV2Request`/`APIGatewayV2Response`).
/// HTTP API (V2) is lower latency and lower cost than REST API (V1).
///
/// ## Key Differences from V1
///
/// - Path is read from `request.rawPath` instead of `request.path`
/// - Method is at `request.context.http.method` instead of `request.httpMethod`
/// - Response supports `cookies: [String]?` field
///
/// ## Usage
///
/// ```swift
/// let router = APIGatewayV2Router()
///     .mount("/health", handler: { ctx, req, path in
///         return APIGatewayV2Response(statusCode: .ok, body: "OK")
///     })
///     .mount("/api", handler: { ctx, req, path in
///         return handleAPI(ctx, req, path)
///     })
///
/// let app = LambdaApp()
///     .addAPIGatewayV2(key: "api", router: router)
/// ```
public final class APIGatewayV2Router: @unchecked Sendable {

    /// Handler that receives context, original request, and stripped path
    public typealias RouteHandler = (LambdaContext, APIGatewayV2Request, String) async throws -> APIGatewayV2Response

    private var routes: [Route] = []

    public init() {}

    /// Mount a handler at the root (handles all requests)
    @discardableResult
    public func mount(
        handler: @escaping RouteHandler
    ) -> APIGatewayV2Router {
        return mount("/", handler: handler)
    }

    /// Mount a handler at a path prefix
    @discardableResult
    public func mount(
        _ prefix: String,
        handler: @escaping RouteHandler
    ) -> APIGatewayV2Router {
        let normalizedPrefix = normalizePrefix(prefix)
        routes.append(Route(prefix: normalizedPrefix, handler: handler))
        return self
    }

    /// Build the router into a Lambda API Gateway V2 handler
    public func build() -> (LambdaContext, APIGatewayV2Request) async throws -> APIGatewayV2Response {
        let capturedRoutes = routes

        return { context, request in
            let path = request.rawPath

            for route in capturedRoutes {
                if let strippedPath = route.matchAndStrip(path) {
                    return try await route.handler(context, request, strippedPath)
                }
            }

            return APIGatewayV2Response(
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
        if !p.hasPrefix("/") {
            p = "/" + p
        }
        if p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        return p
    }

    private struct Route {
        let prefix: String
        let handler: RouteHandler

        func matchAndStrip(_ path: String) -> String? {
            if prefix == "/" {
                return path
            }
            if path == prefix {
                return "/"
            }
            if path.hasPrefix(prefix + "/") {
                return String(path.dropFirst(prefix.count))
            }
            return nil
        }
    }
}

// MARK: - LambdaApp Extension

public extension LambdaApp {

    /// Register an API Gateway V2 router
    @discardableResult
    func addAPIGatewayV2(key: String, router: APIGatewayV2Router) -> LambdaApp {
        return addAPIGatewayV2(key: key, handler: router.build())
    }
}
