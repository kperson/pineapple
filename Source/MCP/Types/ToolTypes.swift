import Foundation
import Logging
import JSONValueCoding

// MARK: - Tool Request & Response Types

/// Request context for tool handlers
///
/// Provides typed access to tool input parameters along with MCP context,
/// path parameters (from the route), and a request-scoped logger. This enables
/// multi-tenant tool architectures where the same tool can serve different
/// customers/tenants based on the route.
///
/// ## Type Parameter
///
/// - **Input**: The tool's input type conforming to `InputWithSchema` (JSONSchemaProvider & Decodable)
///
/// ## Properties
///
/// - **input**: Strongly-typed tool input parameters decoded from the request
/// - **pathParams**: Extracted from the router URL pattern (e.g., `/mcp/{customerId}/tools`)
/// - **context**: MCP request context with requestId, method, logger, and metadata
/// - **logger**: Request-scoped logger with request metadata
///
/// ## Example
///
/// ```swift
/// // Router pattern: /mcp/{customerId}/tools
/// // URL: /mcp/acme-corp/tools
/// // Tool input: {"filename": "report.pdf"}
///
/// @JSONSchema
/// struct FileInput: Codable {
///     let filename: String
/// }
///
/// server.addTool("read_file", inputType: FileInput.self) { request in
///     request.logger.info("Processing: \(request.input.filename)")
///     let customerId = try request.pathParamOrThrow("customerId")  // "acme-corp"
///
///     // Read customer-specific file
///     let content = readFile(customerId: customerId, filename: request.input.filename)
///     return .text(content)
/// }
/// ```
public struct ToolHandlerRequest<Input>: Sendable where Input: Sendable {

    /// MCP request context with requestId, method, logger, and metadata
    public let context: MCPContext

    /// Strongly-typed tool input parameters decoded from the request
    public let input: Input

    /// Parameters extracted from the URL route pattern
    ///
    /// Contains values from the router path like `/mcp/{customerId}/tools`.
    /// May be nil if no router path parameters are defined.
    public let pathParams: Params?

    /// Request-scoped logger with MCP request metadata
    ///
    /// Includes requestId and method in log metadata for request correlation.
    public let logger: Logger

    public init(context: MCPContext, input: Input, pathParams: Params?, logger: Logger) {
        self.context = context
        self.input = input
        self.pathParams = pathParams
        self.logger = logger
    }

    /// Get a required path parameter or throw an error
    ///
    /// Convenience method to safely extract path parameters with clear error messages.
    ///
    /// - Parameter name: The parameter name from the route pattern
    /// - Returns: The parameter value
    /// - Throws: MCPError with parseError code if parameter is not found
    public func pathParamOrThrow(_ name: String) throws -> String {
        if let pathParam = pathParams?[name] {
            return pathParam
        } else {
            throw MCPError(code: MCPErrorCode.parseError, message: "Unable to parse path parameter = \(name)")
        }
    }
}

/// Tool handler response types for MCP tools
///
/// Represents the different types of content that can be returned from a tool execution.
/// The MCP protocol supports rich media responses including text, images, audio, and
/// references to resources.
///
/// ## Response Types
///
/// - **text**: Plain text response (most common)
/// - **image**: Binary image data with MIME type (e.g., PNG, JPEG)
/// - **audio**: Binary audio data with MIME type (e.g., MP3, WAV)
/// - **resourceLink**: URI reference to an existing MCP resource
/// - **embeddedResource**: Full resource object embedded in the response
///
/// ## Examples
///
/// ```swift
/// // Text response
/// return .text("File processed successfully")
///
/// // Image response
/// let chartData = generateChart(data)
/// return .image(chartData, "image/png")
///
/// // Audio response
/// let audioData = textToSpeech(text)
/// return .audio(audioData, "audio/mp3")
///
/// // Resource link
/// return .resourceLink("file://customer-123/document.pdf")
///
/// // Embedded resource
/// let resource = Resource(uri: "file://data.json", response: ...)
/// return .embeddedResource(resource)
/// ```
///
/// ## Encoding
///
/// Binary data (image, audio) is automatically base64-encoded when sent over the wire.
/// The MCP protocol handles this encoding/decoding transparently.
public enum ToolHandlerResponse: Codable {
    
    /// Plain text response
    case text(String)

    /// Image data response with MIME type
    /// - Parameters:
    ///   - data: Binary image data
    ///   - mimeType: MIME type (e.g., "image/png", "image/jpeg")
    case image(Data, String)

    /// Audio data response with MIME type
    /// - Parameters:
    ///   - data: Binary audio data
    ///   - mimeType: MIME type (e.g., "audio/mp3", "audio/wav")
    case audio(Data, String)

    /// URI reference to an existing MCP resource
    /// - Parameter uri: Resource URI (e.g., "file://customer-123/document.pdf")
    case resourceLink(String)

    /// Full resource object embedded in the tool response
    /// - Parameter resource: Complete resource with content
    case embeddedResource(Resource)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let dataString = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            guard let data = Data(base64Encoded: dataString) else {
                throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "Invalid base64")
            }
            self = .image(data, mimeType)
        case "audio":
            let dataString = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            guard let data = Data(base64Encoded: dataString) else {
                throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "Invalid base64")
            }
            self = .audio(data, mimeType)
        case "resource_link":
            let uri = try container.decode(String.self, forKey: .uri)
            self = .resourceLink(uri)
        case "embedded_resource":
            let resource = try container.decode(Resource.self, forKey: .resource)
            self = .embeddedResource(resource)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown result type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data.base64EncodedString(), forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .audio(let data, let mimeType):
            try container.encode("audio", forKey: .type)
            try container.encode(data.base64EncodedString(), forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resourceLink(let uri):
            try container.encode("resource_link", forKey: .type)
            try container.encode(uri, forKey: .uri)
        case .embeddedResource(let resource):
            try container.encode("embedded_resource", forKey: .type)
            try container.encode(resource, forKey: .resource)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, uri, resource
    }
}

// MARK: - Internal Tool Types

/// Tool signature definition for MCP protocol
///
/// Describes a tool's interface including its name, description, and JSON schemas
/// for input parameters and output results. Used internally to generate the
/// MCP `tools/list` response.
///
/// The schemas are generated automatically from Swift types using the `@JSONSchema` macro.
struct ToolSignature: Codable {

    /// Unique tool name (e.g., "read_file", "generate_chart")
    let name: String

    /// Human-readable description of what the tool does
    let description: String

    /// JSON Schema describing the tool's input parameters
    let inputSchema: JSONValue

    /// Optional JSON Schema describing the tool's output structure
    let outputSchema: JSONValue?

}

/// MCP protocol response wrapper for tool execution results
///
/// Wraps the handler's response for transmission over the MCP protocol.
/// Contains both the content array (required by MCP) and optional structured
/// content for tools that return typed output.
struct ToolCallResponse: Encodable {

    /// Array of content items (text, image, audio, resource references)
    let content: [JSONValue]

    /// Optional structured output matching the tool's output schema
    let structuredContent: JSONValue?

}

/// Complete tool definition including signature and handler
///
/// Combines the tool's public signature (name, description, schemas) with
/// the actual handler function that executes when the tool is called.
/// Stored in the server's tool registry.
struct ToolDefinition {

    /// Tool's public signature
    let signature: ToolSignature

    /// Async handler function that executes the tool
    /// - Parameters:
    ///   - context: MCP request context (requestId, method, logger, metadata)
    ///   - arguments: Tool input as JSONValue
    ///   - pathParams: Parameters extracted from the URL route
    /// - Returns: Tool call response with content and optional structured output
    let handler: (MCPContext, JSONValue, Params?) async throws -> ToolCallResponse
}

/// Tool information for MCP `tools/list` response
///
/// Subset of ToolSignature used in protocol responses. Contains only the
/// information needed by MCP clients to discover and use tools.
struct ToolInfo: Encodable {

    /// Unique tool name
    let name: String

    /// Human-readable description
    let description: String

    /// JSON Schema for input parameters
    let inputSchema: JSONValue

    /// Optional JSON Schema for output structure
    let outputSchema: JSONValue?
}

/// MCP protocol response for `tools/list` method
///
/// Returns the complete list of tools available on this server.
/// Sent in response to MCP client discovery requests.
struct ToolsListResponse: Encodable {

    /// Array of available tools with their signatures
    let tools: [ToolInfo]
}
