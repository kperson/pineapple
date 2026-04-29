import Testing
import Foundation
@testable import JSONValueCoding
@testable import MCP

@Suite("@JSONSchema knows Foundation types")
struct JSONSchemaFoundationTypesTests {

    @Test("Date.jsonSchema is iso8601 date-time string")
    func dateSchema() {
        let s: JSONValue = [
            "type": "string",
            "format": "date-time",
        ]
        #expect(Date.jsonSchema == s)
    }

    @Test("UUID.jsonSchema is uuid format string")
    func uuidSchema() {
        let s: JSONValue = [
            "type": "string",
            "format": "uuid",
        ]
        #expect(UUID.jsonSchema == s)
    }

    @Test("URL.jsonSchema is uri format string")
    func urlSchema() {
        let s: JSONValue = [
            "type": "string",
            "format": "uri",
        ]
        #expect(URL.jsonSchema == s)
    }

    @Test("Data.jsonSchema is base64 string")
    func dataSchema() {
        let s: JSONValue = [
            "type": "string",
            "contentEncoding": "base64",
        ]
        #expect(Data.jsonSchema == s)
    }

    // MARK: - Macro integration

    @JSONSchema
    struct Sample: Codable {
        let id: UUID
        let createdAt: Date
        let homepage: URL?
        let blob: Data
    }

    @Test("Macro emits the right per-property schemas for Foundation fields")
    func macroIntegratesFoundationTypes() {
        guard case .object(let outer) = Sample.jsonSchema else {
            Issue.record("Sample.jsonSchema is not an object")
            return
        }
        guard case .object(let props) = outer["properties"] ?? .null else {
            Issue.record("missing properties dict")
            return
        }

        // Each Foundation property should advertise the canonical schema.
        #expect(props["id"] == .object([
            "type": .string("string"),
            "format": .string("uuid"),
        ]))
        #expect(props["createdAt"] == .object([
            "type": .string("string"),
            "format": .string("date-time"),
        ]))
        #expect(props["homepage"] == .object([
            "type": .string("string"),
            "format": .string("uri"),
        ]))
        #expect(props["blob"] == .object([
            "type": .string("string"),
            "contentEncoding": .string("base64"),
        ]))

        // Required: id, createdAt, blob (homepage is optional).
        guard case .array(let required) = outer["required"] ?? .null else {
            Issue.record("missing required array")
            return
        }
        let names = Set(required.compactMap { $0.string })
        #expect(names == ["id", "createdAt", "blob"])
    }
}
