# MCPWebSocket

iOS client adapter for connecting MCP servers to the [WebSocket relay](../MCPWebSocketRelay/README.md). Enables iOS apps to expose MCP tools, resources, and prompts to remote MCP clients like Claude.

## Problem

iOS apps can't run HTTP servers. MCP clients expect to call tools over HTTP. The WebSocket relay bridges this gap: the iOS app connects **outbound** to an AWS WebSocket endpoint, and MCP clients send HTTP requests to the relay, which forwards them over the WebSocket.

## Architecture

```
MCP Client (Claude)                              iOS App
     |                                              |
     | POST /mcp/{sessionId}                        | WSS outbound connect
     v                                              v
+-------------------------------------------------+
|            AWS API Gateway                      |
|  HTTP API          WebSocket API                |
+------+--------------------+---------------------+
       v                    v
  HTTP Lambda          WS Lambda
       |     DynamoDB      |
       +--------+----------+
```

## Quick Start

```swift
import MCP
import MCPWebSocket

// Build your MCP server with tools
let server = Server()
    .addTool("get_location", description: "Get device location",
             inputType: Empty.self) { _ in
        let location = await LocationManager.shared.currentLocation()
        return .text("\(location.latitude), \(location.longitude)")
    }

// Connect to the relay
let relayURL = URL(string: "wss://your-relay.execute-api.us-east-1.amazonaws.com/production")!
let adapter = WebSocketAdapter(server: server, url: relayURL)

// Generate a session ID and share it with the MCP client
let sessionId = UUID().uuidString
displaySessionId(sessionId) // Show in UI for user to copy

// Run (blocks, auto-reconnects on disconnect)
try await adapter.run(sessionId: sessionId, token: jwtToken)
```

## Multi-Server Routing

```swift
let router = WebSocketRouter()
    .addServer(path: "/tools", server: toolServer)
    .addServer(path: "/data/{source}", server: dataServer)

let adapter = WebSocketAdapter(router: router, url: relayURL)
try await adapter.run(sessionId: sessionId, token: jwtToken, mcpPath: "/tools")
```

## Middleware

```swift
let adapter = WebSocketAdapter(server: server, url: relayURL)
    .usePreRequestMiddleware(PreRequestMiddlewareHelpers.from {
        (context: WebSocketMCPContext, envelope: TransportEnvelope) in
        // Access session info
        print("Session: \(context.sessionId)")
        return .accept(metadata: ["sessionId": context.sessionId])
    })
```

## Connection Management

The adapter handles connection lifecycle automatically:

- **Reconnection**: Exponential backoff from 1s to 30s on disconnect
- **Keep-alive**: Sends WebSocket pings every 5 minutes (under API Gateway's 10-min idle timeout)
- **Cancellation**: Supports Swift structured concurrency cancellation

Configure behavior:

```swift
adapter.pingInterval = 300          // 5 min (default)
adapter.baseReconnectDelay = 1      // 1s (default)
adapter.maxReconnectDelay = 30      // 30s cap (default)
adapter.maxReconnectAttempts = 0    // 0 = unlimited (default)
```

## Context Type

Middleware and handlers receive `WebSocketMCPContext`:

| Property | Type | Description |
|----------|------|-------------|
| `sessionId` | `String` | Session identifier for this relay connection |
| `routePath` | `String` | Resolved MCP route path |
| `relayURL` | `URL` | WebSocket relay URL |
| `connectionId` | `String?` | API Gateway connection ID (if known) |

## Testability

The `WebSocketConnection` protocol and `WebSocketConnectionFactory` enable dependency injection for testing without a network:

```swift
// In tests, inject a mock connection
let mock = MockWebSocketConnection(incomingMessages: [...])
let factory = MockFactory(connection: mock)
let adapter = WebSocketAdapter(server: server, url: url, connectionFactory: factory)
```

## Dependencies

- `MCP` - Core MCP framework
- `MCPWebSocketShared` - Relay wire protocol types
- `swift-log` - Structured logging
