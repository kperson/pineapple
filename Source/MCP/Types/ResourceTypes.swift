import Foundation

// MARK: - Resource Request Types

/// Request context for resource handlers
///
/// Provides access to both path parameters (from the route) and resource parameters
/// (from the resource URI pattern), along with the MCP context for the request.
///
/// ## Parameter Types
///
/// - **pathParams**: Extracted from the router URL pattern (e.g., `/mcp/{customerId}/files`)
/// - **resourceParams**: Extracted from the resource URI pattern (e.g., `file://{docId}.json`)
///
/// This dual-parameter system enables multi-tenant resource architectures where the
/// same resource handler can serve different customers/tenants based on the route,
/// while also accepting parameters within the resource URI itself.
///
/// ## Example
///
/// ```swift
/// // Router pattern: /mcp/{customerId}/files
/// // Resource pattern: file://{docId}.json
/// // Actual request: /mcp/acme-corp/files with URI "file://report-2024.json"
///
/// server.addResource("file://{docId}.json", ...) { request in
///     let customerId = try request.pathParamOrThrow("customerId")     // "acme-corp"
///     let docId = try request.resourceParamOrThrow("docId")           // "report-2024"
///
///     // Load document for specific customer
///     let content = loadDocument(customerId: customerId, docId: docId)
///     return ResourceHandlerResponse(name: "\(docId).json", data: .text(content))
/// }
/// ```
public struct ResourceHandlerRequest {

    /// Parameters extracted from the URL route pattern
    ///
    /// Contains values from the router path like `/mcp/{customerId}/files`.
    /// May be nil if no router path parameters are defined.
    public let pathParams: Params?

    /// Parameters extracted from the resource URI pattern
    ///
    /// Contains values from the resource URI like `file://{docId}.json`.
    /// Always present as resource URIs are required.
    public let resourceParams: Params

    /// MCP request context with requestId, method, logger, and metadata
    public let context: MCPContext

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

    /// Get a required resource parameter or throw an error
    ///
    /// Convenience method to safely extract resource URI parameters with clear error messages.
    ///
    /// - Parameter name: The parameter name from the resource URI pattern
    /// - Returns: The parameter value
    /// - Throws: MCPError with parseError code if parameter is not found
    public func resourceParamOrThrow(_ name: String) throws -> String {
        if let pathParam = resourceParams[name] {
            return pathParam
        } else {
            throw MCPError(code: MCPErrorCode.parseError, message: "Unable to parse resource parameter = \(name)")
        }
    }
}

// MARK: - Public Resource Types

/// MCP resource response wrapper
///
/// Wraps the handler's response with MIME type information for transmission
/// over the MCP protocol. This is the structure sent to clients when they
/// read a resource.
public struct ResourceResponse {

    /// The actual resource content from the handler
    let handlerResponse: ResourceHandlerResponse

    /// MIME type of the resource (e.g., "text/plain", "application/json")
    let mimeType: String
    
    public init(handlerResponse: ResourceHandlerResponse, mimeType: String) {
        self.handlerResponse = handlerResponse
        self.mimeType = mimeType
    }
    
}

// MARK: - MCP Protocol Response Types

/// MCP protocol response for `resources/read` method
///
/// Returns the contents of one or more resources when read by a client.
/// Multiple resources can be returned in a single response.
struct ResourceReadResponse: Encodable {
    /// Array of resource contents
    let contents: [Resource]
}

/// MCP protocol response for `resources/list` method
///
/// Returns static resources (without parameters) available on this server.
/// Static resources have fixed URIs like `file://config.json`.
struct ResourcesListResponse: Encodable {

    /// Static resource information for discovery
    struct StaticResource: Encodable {
        /// Fixed URI of the resource
        let uri: String

        /// Human-readable resource name
        let name: String

        /// Description of what this resource provides
        let description: String

        /// MIME type of the resource content
        let mimeType: String
    }

    /// Array of static resources
    let resources: [StaticResource]
}

/// MCP protocol response for `resources/templates/list` method
///
/// Returns resource templates (with parameters) available on this server.
/// Templates contain URI patterns like `file://{customerId}/data.json`.
struct ResourcesTemplateResponse: Encodable {

    /// Resource template information for discovery
    struct Template: Encodable {
        /// URI template with parameters (e.g., "file://{id}/data.json")
        let uriTemplate: String

        /// Human-readable template name
        let name: String

        /// Description of what this resource template provides
        let description: String

        /// MIME type of the resource content
        let mimeType: String
    }

    /// Array of resource templates
    let resourceTemplates: [Template]
}

// MARK: - Internal Resource Types

/// Resource signature definition for MCP protocol
///
/// Describes a resource's interface including its URI pattern, name, description,
/// and MIME type. Used internally to generate MCP resource list responses.
struct ResourceSignature {
    /// URI pattern matcher (e.g., "file://{customerId}/data.json")
    let pattern: ResourcePattern

    /// Human-readable resource name
    let name: String

    /// Description of what this resource provides
    let description: String

    /// MIME type of the resource content
    let mimeType: String
}

/// Complete resource definition including signature and handler
///
/// Combines the resource's public signature (pattern, name, description, MIME type)
/// with the actual handler function that serves the resource content.
/// Stored in the server's resource registry.
struct ResourceDefinition {
    /// Resource's public signature
    let signature: ResourceSignature

    /// Async handler function that serves the resource
    /// - Parameter request: MCP resource request with path and resource parameters
    /// - Returns: Resource content (text or binary data)
    let handler: (ResourceHandlerRequest) async throws -> ResourceHandlerResponse
}



/// Resource handler response for MCP resources
///
/// Represents the content returned from a resource handler. Resources can contain
/// either text or binary data, along with metadata like name and description.
///
/// ## Examples
///
/// ```swift
/// // Text resource
/// return ResourceHandlerResponse(
///     name: "config.json",
///     data: .text("{\"version\": \"1.0\"}"),
///     description: "Application configuration"
/// )
///
/// // Binary resource
/// let imageData = try Data(contentsOf: imageURL)
/// return ResourceHandlerResponse(
///     name: "logo.png",
///     data: .blob(imageData),
///     description: "Company logo"
/// )
/// ```
///
/// ## Encoding
///
/// Binary data (blob) is automatically base64-encoded when sent over the wire.
/// The MCP protocol handles this encoding/decoding transparently.
public struct ResourceHandlerResponse {

    /// Resource content data type
    ///
    /// Supports both text and binary content for maximum flexibility.
    public enum ResourceData: Codable {
        /// Binary data (images, PDFs, etc.)
        case blob(Data)

        /// Text content (JSON, XML, plain text, etc.)
        case text(String)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let asText = try container.decodeIfPresent(String.self, forKey: .text) {
                self = .text(asText)
            } else if let asBlob = try container.decodeIfPresent(String.self, forKey: .blob),
                      let asData = Data(base64Encoded: asBlob) {
                self = .blob(asData)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "ResourceData must contain either 'text' or 'blob' field"
                    )
                )
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .blob(let data):
                try container.encode(data.base64EncodedString(), forKey: .blob)
            case .text(let str):
                try container.encode(str, forKey: .text)
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case text, blob
        }
    }

    /// Resource name (e.g., filename or identifier)
    public let name: String

    /// Resource content (text or binary)
    public let data: ResourceData

    /// Optional description of the resource
    public let description: String?
        
    public init(
        name: CustomStringConvertible,
        data: ResourceData,
        description: CustomStringConvertible? = nil
    ) {
        self.name = name.description
        self.data = data
        self.description = description?.description
    }

}

/// MCP Resource with URI and content
///
/// Represents a complete resource in the MCP protocol, combining a URI with
/// the resource's content. Used in resource read responses to clients.
///
/// ## Example
///
/// ```swift
/// let response = ResourceHandlerResponse(
///     name: "document.pdf",
///     data: .blob(pdfData)
/// )
/// let resourceResponse = ResourceResponse(
///     handlerResponse: response,
///     mimeType: "application/pdf"
/// )
/// let resource = Resource(
///     uri: "file://customer-123/document.pdf",
///     response: resourceResponse
/// )
/// ```
public struct Resource: Codable {

    /// The URI that identifies this resource (e.g., "file://path/to/resource")
    public let uri: String

    /// The resource's content and metadata
    public let response: ResourceResponse
        
    public init(uri: String, response: ResourceResponse) {
        self.uri = uri
        self.response = response
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uri = try container.decode(String.self, forKey: .uri)
        
        let data: ResourceHandlerResponse.ResourceData
        if let asText = try container.decodeIfPresent(String.self, forKey: .text) {
            data = .text(asText)
        } else if let asBlob = try container.decodeIfPresent(String.self, forKey: .blob),
                  let asData = Data(base64Encoded: asBlob) {
            data = .blob(asData)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "ResourceData must contain either 'text' or 'blob' field"
                )
            )
        }
        self.response = ResourceResponse(
            handlerResponse: .init(
                name: try container.decode(String.self, forKey: .name),
                data: data,
                description: try container.decode(String.self, forKey: .description)
            ),
            mimeType: try container.decode(String.self, forKey: .mimeType)
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uri, forKey: .uri)
        try container.encode(response.mimeType, forKey: .mimeType)
        try container.encodeIfPresent(response.handlerResponse.name, forKey: .name)
        try container.encodeIfPresent(response.handlerResponse.description, forKey: .description)
        switch response.handlerResponse.data {
        case .blob(let data):
            try container.encode(data.base64EncodedString(), forKey: .blob)
        case .text(let str):
            try container.encode(str, forKey: .text)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case uri, mimeType, name, description, text, blob
    }
}
