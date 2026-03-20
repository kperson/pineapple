import Testing
import Foundation
import JSONValueCoding
@testable import MCP

// Mirrors HttpRequestHeader from kelti-chat-api
@JSONSchema
struct HttpRequestHeader: Codable {
    let name: String
    let value: String
}

// Mirrors HttpRequestInput from kelti-chat-api
@JSONSchema
struct HttpRequestInput: Codable {
    let url: String
    let method: String
    let headers: [HttpRequestHeader]?
    let body: String?
}

// Variant using a dictionary for headers instead of an array of structs
@JSONSchema
struct HttpRequestInputWithDictHeaders: Codable {
    let url: String
    let method: String
    let headers: [String: String]?
    let body: String?
}

@Suite("JSONSchema Nested Type Tests")
struct JSONSchemaNestedTests {

    @Test("HttpRequestInput schema generates correctly with nested array of structs")
    func testHttpRequestInputSchema() throws {
        let schema = HttpRequestInput.jsonSchema

        // Verify top-level structure
        guard case .object(let topLevel) = schema else {
            Issue.record("Expected object at top level")
            return
        }

        #expect(topLevel["type"] == .string("object"))

        // Verify required fields
        guard case .array(let required) = topLevel["required"] else {
            Issue.record("Expected required array")
            return
        }
        #expect(required.contains(.string("url")))
        #expect(required.contains(.string("method")))
        #expect(!required.contains(.string("headers")))
        #expect(!required.contains(.string("body")))

        // Verify properties exist
        guard case .object(let properties) = topLevel["properties"] else {
            Issue.record("Expected properties object")
            return
        }

        // Check simple string properties
        #expect(properties["url"] == .object(["type": .string("string")]))
        #expect(properties["method"] == .object(["type": .string("string")]))
        #expect(properties["body"] == .object(["type": .string("string")]))

        // Check headers is an array with items referencing HttpRequestHeader's schema
        guard case .object(let headersSchema) = properties["headers"] else {
            Issue.record("Expected headers to be an object schema")
            return
        }
        #expect(headersSchema["type"] == .string("array"))

        // The items should match HttpRequestHeader.jsonSchema
        guard let items = headersSchema["items"] else {
            Issue.record("Expected items in headers array schema")
            return
        }
        #expect(items == HttpRequestHeader.jsonSchema)
    }

    @Test("HttpRequestHeader schema generates correctly")
    func testHttpRequestHeaderSchema() throws {
        let schema = HttpRequestHeader.jsonSchema

        guard case .object(let topLevel) = schema else {
            Issue.record("Expected object at top level")
            return
        }

        #expect(topLevel["type"] == .string("object"))

        guard case .object(let properties) = topLevel["properties"] else {
            Issue.record("Expected properties object")
            return
        }

        #expect(properties["name"] == .object(["type": .string("string")]))
        #expect(properties["value"] == .object(["type": .string("string")]))

        guard case .array(let required) = topLevel["required"] else {
            Issue.record("Expected required array")
            return
        }
        #expect(required.contains(.string("name")))
        #expect(required.contains(.string("value")))
    }

    @Test("Dictionary headers schema generates with additionalProperties")
    func testDictHeadersSchema() throws {
        let schema = HttpRequestInputWithDictHeaders.jsonSchema

        guard case .object(let topLevel) = schema else {
            Issue.record("Expected object at top level")
            return
        }

        guard case .object(let properties) = topLevel["properties"] else {
            Issue.record("Expected properties object")
            return
        }

        // headers should be { "type": "object", "additionalProperties": { "type": "string" } }
        guard case .object(let headersSchema) = properties["headers"] else {
            Issue.record("Expected headers to be an object schema")
            return
        }
        #expect(headersSchema["type"] == .string("object"))
        #expect(headersSchema["additionalProperties"] == .object(["type": .string("string")]))
    }
}
