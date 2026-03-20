import Foundation

// MARK: - Relay Wire Protocol

/// Message types exchanged between relay components over WebSocket and DynamoDB.
///
/// All types are `Codable` and transport MCP request/response bodies as raw `Data`
/// (base64-encoded in JSON) to avoid coupling to `MCP.Request` types.

/// Top-level relay message envelope
public enum RelayMessage: Codable, Sendable {
    case request(RelayRequest)
    case response(RelayResponse)
    case control(RelayControlMessage)

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum MessageType: String, Codable {
        case request, response, control
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .request:
            self = .request(try container.decode(RelayRequest.self, forKey: .payload))
        case .response:
            self = .response(try container.decode(RelayResponse.self, forKey: .payload))
        case .control:
            self = .control(try container.decode(RelayControlMessage.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .request(let req):
            try container.encode(MessageType.request, forKey: .type)
            try container.encode(req, forKey: .payload)
        case .response(let res):
            try container.encode(MessageType.response, forKey: .type)
            try container.encode(res, forKey: .payload)
        case .control(let ctrl):
            try container.encode(MessageType.control, forKey: .type)
            try container.encode(ctrl, forKey: .payload)
        }
    }
}

/// A relay request forwarded from MCP client to iOS app
public struct RelayRequest: Codable, Sendable {
    /// Unique correlation ID for matching request to response
    public let correlationId: String

    /// Raw MCP JSON-RPC request body (base64 encoded in JSON)
    public let body: Data

    public init(correlationId: String, body: Data) {
        self.correlationId = correlationId
        self.body = body
    }

    private enum CodingKeys: String, CodingKey {
        case correlationId, body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        correlationId = try container.decode(String.self, forKey: .correlationId)
        let base64 = try container.decode(String.self, forKey: .body)
        guard let data = Data(base64Encoded: base64) else {
            throw DecodingError.dataCorruptedError(
                forKey: .body,
                in: container,
                debugDescription: "Invalid base64 body"
            )
        }
        body = data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(correlationId, forKey: .correlationId)
        try container.encode(body.base64EncodedString(), forKey: .body)
    }
}

/// A relay response sent from iOS app back through the relay
public struct RelayResponse: Codable, Sendable {
    /// Correlation ID matching the original request
    public let correlationId: String

    /// Raw MCP JSON-RPC response body (base64 encoded in JSON)
    public let body: Data

    public init(correlationId: String, body: Data) {
        self.correlationId = correlationId
        self.body = body
    }

    private enum CodingKeys: String, CodingKey {
        case correlationId, body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        correlationId = try container.decode(String.self, forKey: .correlationId)
        let base64 = try container.decode(String.self, forKey: .body)
        guard let data = Data(base64Encoded: base64) else {
            throw DecodingError.dataCorruptedError(
                forKey: .body,
                in: container,
                debugDescription: "Invalid base64 body"
            )
        }
        body = data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(correlationId, forKey: .correlationId)
        try container.encode(body.base64EncodedString(), forKey: .body)
    }
}

/// Control messages for relay management
public enum RelayControlMessage: Codable, Sendable {
    /// Ping to keep the WebSocket connection alive
    case ping

    /// Pong response to a ping
    case pong

    /// Session established confirmation with session ID
    case sessionEstablished(sessionId: String)

    /// Error notification
    case error(message: String)

    private enum CodingKeys: String, CodingKey {
        case type, sessionId, message
    }

    private enum ControlType: String, Codable {
        case ping, pong, sessionEstablished, error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ControlType.self, forKey: .type)
        switch type {
        case .ping:
            self = .ping
        case .pong:
            self = .pong
        case .sessionEstablished:
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .sessionEstablished(sessionId: sessionId)
        case .error:
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message: message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ping:
            try container.encode(ControlType.ping, forKey: .type)
        case .pong:
            try container.encode(ControlType.pong, forKey: .type)
        case .sessionEstablished(let sessionId):
            try container.encode(ControlType.sessionEstablished, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        case .error(let message):
            try container.encode(ControlType.error, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}
