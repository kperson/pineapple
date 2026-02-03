// MARK: - JSON Schema DSL

/// Type-safe builder for JSON Schema definitions
///
/// `JSONSchema` provides a fluent DSL for constructing JSON Schema objects used by MCP tools
/// to describe their input and output types. The schema is used for validation and
/// documentation of tool interfaces.
///
/// ## Basic Types
///
/// ```swift
/// JSONSchema.string()   // { "type": "string" }
/// JSONSchema.integer()  // { "type": "integer" }
/// JSONSchema.number()   // { "type": "number" }
/// JSONSchema.boolean()  // { "type": "boolean" }
/// ```
///
/// ## Objects with Properties
///
/// ```swift
/// JSONSchema.object(
///     properties: [
///         "name": .string(),
///         "age": .integer(),
///         "email": .optional(.string())
///     ],
///     required: ["name", "age"]
/// )
/// // Produces:
/// // {
/// //   "type": "object",
/// //   "properties": {
/// //     "name": { "type": "string" },
/// //     "age": { "type": "integer" },
/// //     "email": { "anyOf": [{ "type": "string" }, { "type": "null" }] }
/// //   },
/// //   "required": ["name", "age"]
/// // }
/// ```
///
/// ## Arrays
///
/// ```swift
/// JSONSchema.array(of: .string())
/// // Produces: { "type": "array", "items": { "type": "string" } }
///
/// JSONSchema.array(of: .object(
///     properties: ["id": .integer(), "value": .string()],
///     required: ["id"]
/// ))
/// ```
///
/// ## Optional Fields
///
/// ```swift
/// JSONSchema.optional(.string())
/// // Produces: { "anyOf": [{ "type": "string" }, { "type": "null" }] }
/// ```
///
/// ## Usage with MCP Tools
///
/// ```swift
/// server.addTool(
///     "create_user",
///     description: "Create a new user",
///     inputSchema: .object(
///         properties: [
///             "username": .string(),
///             "email": .string(),
///             "age": .optional(.integer())
///         ],
///         required: ["username", "email"]
///     )
/// ) { request in
///     // Handle tool request
/// }
/// ```
///
/// ## Extracting the Schema Value
///
/// The underlying dictionary can be accessed via the `value` property:
///
/// ```swift
/// let schema = JSONSchema.string()
/// let dict = schema.value  // ["type": "string"]
/// ```
///
/// ## Sequence Conformance
///
/// `JSONSchema` conforms to `Sequence`, allowing iteration over its key-value pairs:
///
/// ```swift
/// for (key, value) in schema {
///     print("\(key): \(value)")
/// }
/// ```
public struct JSONSchema: @unchecked Sendable, Sequence {

    /// The underlying JSON Schema dictionary
    ///
    /// Contains the raw JSON Schema representation as a dictionary.
    /// Keys are schema keywords (e.g., "type", "properties", "required")
    /// and values are their corresponding schema values.
    public let value: [String: Any]

    /// Create a JSON Schema for an object with typed properties
    ///
    /// Objects are the most common schema type for MCP tool inputs. They define
    /// a structure with named properties, each having its own schema.
    ///
    /// - Parameters:
    ///   - properties: Dictionary mapping property names to their schemas
    ///   - required: Array of property names that must be present (defaults to empty)
    /// - Returns: A JSON Schema describing an object
    ///
    /// ## Example
    ///
    /// ```swift
    /// .object(
    ///     properties: [
    ///         "path": .string(),
    ///         "content": .string(),
    ///         "overwrite": .boolean()
    ///     ],
    ///     required: ["path", "content"]
    /// )
    /// ```
    public static func object(
        properties: [String: JSONSchema],
        required: [String] = []
    ) -> JSONSchema {
        JSONSchema(value: [
            "type": "object",
            "properties": properties.mapValues(\.value),
            "required": required
        ])
    }
    
    /// Create a JSON Schema for a string value
    ///
    /// - Returns: A JSON Schema describing a string
    ///
    /// ## Example
    ///
    /// ```swift
    /// .string()  // { "type": "string" }
    /// ```
    public static func string() -> JSONSchema {
        JSONSchema(value: ["type": "string"])
    }

    /// Create a JSON Schema for an integer value
    ///
    /// Use for whole numbers. For decimal numbers, use `number()`.
    ///
    /// - Returns: A JSON Schema describing an integer
    ///
    /// ## Example
    ///
    /// ```swift
    /// .integer()  // { "type": "integer" }
    /// ```
    public static func integer() -> JSONSchema {
        JSONSchema(value: ["type": "integer"])
    }

    /// Create a JSON Schema for a numeric value (integer or decimal)
    ///
    /// Use for any numeric type including decimals. For integers only, use `integer()`.
    ///
    /// - Returns: A JSON Schema describing a number
    ///
    /// ## Example
    ///
    /// ```swift
    /// .number()  // { "type": "number" }
    /// ```
    public static func number() -> JSONSchema {
        JSONSchema(value: ["type": "number"])
    }

    /// Create a JSON Schema for a boolean value
    ///
    /// - Returns: A JSON Schema describing a boolean
    ///
    /// ## Example
    ///
    /// ```swift
    /// .boolean()  // { "type": "boolean" }
    /// ```
    public static func boolean() -> JSONSchema {
        JSONSchema(value: ["type": "boolean"])
    }

    /// Create a JSON Schema for an array of items
    ///
    /// - Parameter items: The schema for array elements
    /// - Returns: A JSON Schema describing an array
    ///
    /// ## Examples
    ///
    /// ```swift
    /// // Array of strings
    /// .array(of: .string())
    /// // { "type": "array", "items": { "type": "string" } }
    ///
    /// // Array of objects
    /// .array(of: .object(
    ///     properties: ["id": .integer()],
    ///     required: ["id"]
    /// ))
    /// ```
    public static func array(of items: JSONSchema) -> JSONSchema {
        JSONSchema(value: [
            "type": "array",
            "items": items.value
        ])
    }

    /// Create a JSON Schema for an optional (nullable) value
    ///
    /// Wraps a schema to allow null values using JSON Schema's `anyOf` construct.
    ///
    /// - Parameter schema: The schema for the non-null value
    /// - Returns: A JSON Schema that allows the value or null
    ///
    /// ## Example
    ///
    /// ```swift
    /// .optional(.string())
    /// // { "anyOf": [{ "type": "string" }, { "type": "null" }] }
    /// ```
    public static func optional(_ schema: JSONSchema) -> JSONSchema {
        JSONSchema(value: [
            "anyOf": [
                schema.value,
                ["type": "null"]
            ]
        ])
    }

    // MARK: - Sequence Conformance

    /// Returns an iterator over the schema's key-value pairs
    public func makeIterator() -> Dictionary<String, Any>.Iterator {
        value.makeIterator()
    }
}
