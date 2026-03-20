import Foundation

/// Configuration for the WebSocket relay
///
/// Controls DynamoDB table names, WebSocket management endpoint,
/// timeouts, and polling intervals.
public struct RelayConfig: Sendable {

    /// DynamoDB table name for connection tracking and request/response storage
    public let tableName: String

    /// API Gateway WebSocket management endpoint URL
    /// (e.g., "https://abc123.execute-api.us-east-1.amazonaws.com/production")
    public let wsManagementEndpoint: String

    /// Maximum time (seconds) to wait for iOS app response before timing out.
    /// Must be under API Gateway's 29s limit. Default: 25s
    public let timeoutSeconds: TimeInterval

    /// DynamoDB poll interval (seconds) when waiting for response. Default: 0.3s
    public let pollIntervalSeconds: TimeInterval

    /// TTL duration (seconds) for DynamoDB items. Default: 3600 (1 hour)
    public let ttlSeconds: Int

    public init(
        tableName: String,
        wsManagementEndpoint: String,
        timeoutSeconds: TimeInterval = 25,
        pollIntervalSeconds: TimeInterval = 0.3,
        ttlSeconds: Int = 3600
    ) {
        self.tableName = tableName
        self.wsManagementEndpoint = wsManagementEndpoint
        self.timeoutSeconds = timeoutSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
        self.ttlSeconds = ttlSeconds
    }

    /// Create config from environment variables
    ///
    /// Expected env vars:
    /// - `RELAY_TABLE_NAME` — DynamoDB table name
    /// - `WS_MANAGEMENT_ENDPOINT` — API Gateway management URL
    /// - `RELAY_TIMEOUT_SECONDS` — (optional) timeout, default 25
    /// - `RELAY_POLL_INTERVAL_SECONDS` — (optional) poll interval, default 0.3
    public static func fromEnvironment() -> RelayConfig {
        let env = ProcessInfo.processInfo.environment
        return RelayConfig(
            tableName: env["RELAY_TABLE_NAME"] ?? "mcp-relay-connections",
            wsManagementEndpoint: env["WS_MANAGEMENT_ENDPOINT"] ?? "",
            timeoutSeconds: env["RELAY_TIMEOUT_SECONDS"].flatMap(Double.init) ?? 25,
            pollIntervalSeconds: env["RELAY_POLL_INTERVAL_SECONDS"].flatMap(Double.init) ?? 0.3
        )
    }
}
