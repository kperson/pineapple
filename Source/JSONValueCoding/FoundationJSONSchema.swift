import Foundation

/// `JSONSchemaProvider` conformances for the Foundation types that show up
/// most often in tool inputs and outputs. Schemas are written to align with
/// the `Server`'s default Date encoding (`.iso8601`):
///
/// - `Date`  → string, format `date-time` (RFC 3339 / ISO 8601)
/// - `UUID`  → string, format `uuid`
/// - `URL`   → string, format `uri`
/// - `Data`  → string, contentEncoding `base64` (matches Foundation's
///             default Codable handling of Data — base64-encoded string).
///
/// Without these, `@JSONSchema struct Foo: Codable { let id: UUID }` would
/// fail at compile time because the macro tries to look up `UUID.jsonSchema`.

extension Date: JSONSchemaProvider {
    public static var jsonSchema: JSONValue {
        [
            "type": "string",
            "format": "date-time",
        ]
    }
}

extension UUID: JSONSchemaProvider {
    public static var jsonSchema: JSONValue {
        [
            "type": "string",
            "format": "uuid",
        ]
    }
}

extension URL: JSONSchemaProvider {
    public static var jsonSchema: JSONValue {
        [
            "type": "string",
            "format": "uri",
        ]
    }
}

extension Data: JSONSchemaProvider {
    public static var jsonSchema: JSONValue {
        [
            "type": "string",
            "contentEncoding": "base64",
        ]
    }
}
