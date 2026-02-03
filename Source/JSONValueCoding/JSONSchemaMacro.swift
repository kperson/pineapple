/// Generates a JSON schema for a Codable struct at compile time
///
/// Usage:
/// ```swift
/// @JSONSchema
/// struct FileArgs: Codable {
///     let filename: String
///     let content: String?
///     let size: Int
/// }
/// 
/// // Generates:
/// // static let jsonSchema = JSONValue([
/// //     "type": "object",
/// //     "properties": [
/// //         "filename": ["type": "string"],
/// //         "content": ["type": "string"],
/// //         "size": ["type": "integer"]
/// //     ],
/// //     "required": ["filename", "size"]
/// // ])
/// ```
@attached(member, names: named(jsonSchema))
@attached(extension, conformances: JSONSchemaProvider)
public macro JSONSchema() = #externalMacro(module: "MCPMacros", type: "JSONSchemaMacro")

/// Protocol for types that provide their own JSON schema
public protocol JSONSchemaProvider {
    static var jsonSchema: JSONValue { get }
}
