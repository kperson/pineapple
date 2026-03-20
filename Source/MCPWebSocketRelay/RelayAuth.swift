import Foundation

// MARK: - Auth Result

/// Result of WebSocket JWT authentication
public struct AuthResult: Sendable {
    /// Whether the token is valid
    public let isValid: Bool

    /// Authenticated user/device identifier (for logging/tracking)
    public let principalId: String?

    /// Additional claims or metadata from the token
    public let claims: [String: String]

    public init(isValid: Bool, principalId: String? = nil, claims: [String: String] = [:]) {
        self.isValid = isValid
        self.principalId = principalId
        self.claims = claims
    }

    /// Convenience for a successful auth result
    public static func valid(principalId: String, claims: [String: String] = [:]) -> AuthResult {
        AuthResult(isValid: true, principalId: principalId, claims: claims)
    }

    /// Convenience for a failed auth result
    public static let invalid = AuthResult(isValid: false)
}

// MARK: - WebSocket Authenticator (iOS app → Relay)

/// Protocol for validating JWT tokens on WebSocket `$connect`
///
/// Implement this to validate the iOS app's JWT when it connects
/// to the relay WebSocket endpoint.
///
/// ## Example
///
/// ```swift
/// struct MyJWTAuthenticator: WebSocketAuthenticator {
///     func validate(token: String) async throws -> AuthResult {
///         // Validate JWT against your auth system
///         let claims = try JWTVerifier.verify(token)
///         return .valid(principalId: claims.sub, claims: ["role": claims.role])
///     }
/// }
/// ```
public protocol WebSocketAuthenticator: Sendable {
    func validate(token: String) async throws -> AuthResult
}

// MARK: - HTTP Client Authenticator (MCP client → Relay)

/// Protocol for validating API keys on HTTP requests from MCP clients
///
/// Implement this to validate the API key that MCP clients use
/// to send requests through the relay.
///
/// ## Example
///
/// ```swift
/// struct APIKeyAuthenticator: HTTPClientAuthenticator {
///     let validKeys: Set<String>
///
///     func validate(apiKey: String) async throws -> Bool {
///         return validKeys.contains(apiKey)
///     }
/// }
/// ```
public protocol HTTPClientAuthenticator: Sendable {
    func validate(apiKey: String) async throws -> Bool
}
