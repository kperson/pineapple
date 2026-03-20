import Foundation
import MCPWebSocketShared
import SotoDynamoDB
import SotoApiGatewayManagementApi
import Logging

// MARK: - Soto-based WebSocket Management API

/// Production implementation using Soto's ApiGatewayManagementApi client
public struct SotoWebSocketManagementAPI: WebSocketManagementAPI {

    private let client: ApiGatewayManagementApi

    public init(client: ApiGatewayManagementApi) {
        self.client = client
    }

    public func postToConnection(connectionId: String, data: Data) async throws {
        let input = ApiGatewayManagementApi.PostToConnectionRequest(
            connectionId: connectionId,
            data: .init(bytes: data)
        )
        try await client.postToConnection(input)
    }
}

// MARK: - Relay Builder

/// Factory for creating relay handler instances with shared infrastructure
///
/// Builds both the WebSocket handler (for iOS app connections) and the HTTP handler
/// (for MCP client requests) from shared configuration and dependencies.
///
/// ## Example
///
/// ```swift
/// let awsClient = AWSClient(httpClient: httpClient)
/// let config = RelayConfig.fromEnvironment()
///
/// let relay = RelayBuilder(
///     config: config,
///     dynamoDB: DynamoDB(client: awsClient),
///     managementApiClient: ApiGatewayManagementApi(
///         client: awsClient,
///         endpoint: config.wsManagementEndpoint
///     ),
///     wsAuthenticator: MyJWTAuth(),
///     httpAuthenticator: MyAPIKeyAuth()
/// )
///
/// // Wire up the WebSocket Lambda handler
/// let wsHandler = relay.buildWebSocketHandler()
///
/// // Wire up the HTTP Lambda handler
/// let httpHandler = relay.buildHTTPHandler()
/// ```
public struct RelayBuilder {

    private let config: RelayConfig
    private let store: RelayStore
    private let managementAPI: WebSocketManagementAPI
    private let wsAuthenticator: WebSocketAuthenticator
    private let httpAuthenticator: HTTPClientAuthenticator

    public init(
        config: RelayConfig,
        store: RelayStore,
        managementAPI: WebSocketManagementAPI,
        wsAuthenticator: WebSocketAuthenticator,
        httpAuthenticator: HTTPClientAuthenticator
    ) {
        self.config = config
        self.store = store
        self.managementAPI = managementAPI
        self.wsAuthenticator = wsAuthenticator
        self.httpAuthenticator = httpAuthenticator
    }

    /// Convenience initializer using Soto clients directly
    public init(
        config: RelayConfig,
        dynamoDB: DynamoDB,
        managementApiClient: ApiGatewayManagementApi,
        wsAuthenticator: WebSocketAuthenticator,
        httpAuthenticator: HTTPClientAuthenticator
    ) {
        let store = DynamoDBRelayStore(dynamoDB: dynamoDB, config: config)
        let mgmtAPI = SotoWebSocketManagementAPI(client: managementApiClient)
        self.init(
            config: config,
            store: store,
            managementAPI: mgmtAPI,
            wsAuthenticator: wsAuthenticator,
            httpAuthenticator: httpAuthenticator
        )
    }

    /// Build the WebSocket relay handler
    public func buildWebSocketHandler() -> WebSocketRelayHandler {
        WebSocketRelayHandler(store: store, authenticator: wsAuthenticator)
    }

    /// Build the HTTP relay handler
    public func buildHTTPHandler() -> HTTPRelayHandler {
        HTTPRelayHandler(
            store: store,
            authenticator: httpAuthenticator,
            managementAPI: managementAPI,
            config: config
        )
    }
}
