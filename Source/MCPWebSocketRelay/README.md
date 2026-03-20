# MCPWebSocketRelay

AWS Lambda relay server that bridges HTTP MCP clients to iOS apps connected via WebSocket. Provides pluggable authentication, DynamoDB-backed session tracking, and integration with API Gateway's WebSocket and HTTP APIs.

## Architecture

```
MCP Client (Claude)                              iOS App
     |                                              |
     | POST /mcp/{sessionId}                        | WSS connect
     | Header: X-API-Key: <key>                     | Header: Authorization: Bearer <jwt>
     v                                              | Header: X-Session-Id: <uuid>
+----------------------------------------------------+
|               AWS API Gateway                      |
|  HTTP API                  WebSocket API           |
+------+-----------------------+---------------------+
       v                       v
  HTTP Lambda              WS Lambda
  (HTTPRelayHandler)       (WebSocketRelayHandler)
       |                       |
       +------- DynamoDB ------+
               (sessions + request/response)
```

### Request Flow

1. iOS app generates a `sessionId` (UUID), connects via WebSocket with JWT + session ID
2. `$connect` Lambda validates JWT via `WebSocketAuthenticator`, stores connection in DynamoDB
3. MCP client POSTs to `/mcp/{sessionId}` with API key
4. HTTP Lambda validates API key via `HTTPClientAuthenticator`
5. HTTP Lambda looks up WebSocket connection by `sessionId` in DynamoDB (GSI)
6. HTTP Lambda stores request in DynamoDB, forwards to iOS via API Gateway Management API (`PostToConnection`)
7. iOS app processes request through its `MCPServer`, sends `RelayResponse` back over WebSocket
8. `$default` Lambda writes response to DynamoDB
9. HTTP Lambda polls DynamoDB (every 300ms, up to 25s), picks up response, returns to MCP client

## Components

### WebSocketRelayHandler

Handles WebSocket API Gateway events:

| Route | Action |
|-------|--------|
| `$connect` | Validate JWT, store connection + sessionId in DynamoDB |
| `$disconnect` | Remove connection from DynamoDB |
| `$default` | Parse `RelayResponse`, write to DynamoDB for HTTP Lambda to pick up |

### HTTPRelayHandler

Handles MCP client HTTP POST requests:

1. Validate API key
2. Find connection by sessionId (DynamoDB GSI lookup)
3. Store pending request in DynamoDB
4. Forward to iOS via `PostToConnection`
5. Poll DynamoDB for response (300ms intervals, 25s timeout)
6. Return response to caller

### DynamoDBRelayStore

DynamoDB table schema:

| PK (`connectionId`) | SK | Purpose |
|---------------------|-----|---------|
| `conn-abc` | `CONNECTION` | Active WebSocket connection record |
| `conn-abc` | `REQ#<correlationId>` | Pending request / completed response |

**GSI**: `sessionId-index` on `sessionId` for connection lookup by session.

**TTL**: All items expire after 1 hour.

## Authentication

Two independent auth layers with pluggable implementations:

### iOS App -> Relay (WebSocket)

```swift
struct MyJWTAuth: WebSocketAuthenticator {
    func validate(token: String) async throws -> AuthResult {
        let claims = try JWTVerifier.verify(token)
        return .valid(principalId: claims.sub)
    }
}
```

### MCP Client -> Relay (HTTP)

```swift
struct MyAPIKeyAuth: HTTPClientAuthenticator {
    func validate(apiKey: String) async throws -> Bool {
        return try await db.isValidKey(apiKey)
    }
}
```

## Integration

### Using RelayBuilder

```swift
let config = RelayConfig(
    tableName: "my-relay-table",
    wsManagementEndpoint: "https://abc123.execute-api.us-east-1.amazonaws.com/production"
)

let relay = RelayBuilder(
    config: config,
    dynamoDB: DynamoDB(client: awsClient),
    managementApiClient: ApiGatewayManagementApi(client: awsClient, endpoint: config.wsManagementEndpoint),
    wsAuthenticator: MyJWTAuth(),
    httpAuthenticator: MyAPIKeyAuth()
)

let wsHandler = relay.buildWebSocketHandler()
let httpHandler = relay.buildHTTPHandler()
```

### With LambdaApp

```swift
let app = LambdaApp()

// WebSocket Lambda
app.addAPIGatewayWebSocket(key: "ws") { context, request in
    let routeKey = request.context.routeKey
    let connectionId = request.context.connectionId
    // ... dispatch to wsHandler
}

// HTTP Lambda
app.addAPIGatewayV2(key: "http") { context, request in
    // ... dispatch to httpHandler
}

app.run(handlerKey: ProcessInfo.processInfo.environment["_HANDLER"])
```

## Configuration

```swift
RelayConfig(
    tableName: "my-relay",                  // DynamoDB table name
    wsManagementEndpoint: "https://...",     // API Gateway Management API URL
    timeoutSeconds: 25,                     // HTTP poll timeout (< API GW 29s limit)
    pollIntervalSeconds: 0.3,               // DynamoDB poll interval
    ttlSeconds: 3600                        // Item expiry (1 hour)
)
```

Or from environment variables:

```swift
let config = RelayConfig.fromEnvironment()
// Reads: RELAY_TABLE_NAME, WS_MANAGEMENT_ENDPOINT,
//        RELAY_TIMEOUT_SECONDS, RELAY_POLL_INTERVAL_SECONDS
```

## Terraform

A reusable Terraform module is provided at `terraform-support/websocket-api-lambda/` for creating the WebSocket API Gateway + Lambda integration. See `Build/main.tf` for a complete deployment example including the DynamoDB table, IAM policies, and both Lambda functions.

## Dependencies

- `MCP` - Core MCP framework
- `MCPWebSocketShared` - Relay wire protocol types
- `SotoDynamoDB` - DynamoDB client
- `SotoApiGatewayManagementApi` - WebSocket PostToConnection API
- `swift-log` - Structured logging

## Testing

Unit tests use mock implementations of `RelayStore`, `WebSocketAuthenticator`, `HTTPClientAuthenticator`, and `WebSocketManagementAPI`. No AWS credentials needed:

```bash
swift test --filter MCPWebSocketRelayTests
```

End-to-end tests (require deployed infrastructure):

```bash
export TEST_WS_RELAY_ENDPOINT=wss://...
export TEST_HTTP_RELAY_ENDPOINT=https://...
swift test --filter WebSocketRelayTests
```
