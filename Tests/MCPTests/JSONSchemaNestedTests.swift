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

// Test @SchemaDescription on properties
@JSONSchema
struct DescribedInput: Codable {
    @SchemaDescription("The URL to send the request to")
    let url: String

    @SchemaDescription("HTTP method (GET, POST, PUT, PATCH, DELETE)")
    let method: String

    @SchemaDescription("Optional request headers")
    let headers: [String: String]?

    let body: String?
}

// Test @SchemaDescription on a nested @JSONSchema struct property
@JSONSchema
struct ConnectionConfig: Codable {
    @SchemaDescription("Hostname or IP address")
    let host: String

    @SchemaDescription("Port number")
    let port: Int
}

@JSONSchema
struct ServiceInput: Codable {
    @SchemaDescription("Name of the service")
    let name: String

    @SchemaDescription("Primary connection configuration")
    let connection: ConnectionConfig

    @SchemaDescription("Optional fallback connection")
    let fallback: ConnectionConfig?

    @SchemaDescription("Tags for this service")
    let tags: [String]?
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

    @Test("SchemaDescription adds descriptions to properties")
    func testSchemaDescriptions() throws {
        let schema = DescribedInput.jsonSchema

        guard case .object(let topLevel) = schema,
              case .object(let properties) = topLevel["properties"] else {
            Issue.record("Expected object with properties")
            return
        }

        // url should have type + description
        guard case .object(let urlSchema) = properties["url"] else {
            Issue.record("Expected url to be an object schema")
            return
        }
        #expect(urlSchema["type"] == .string("string"))
        #expect(urlSchema["description"] == .string("The URL to send the request to"))

        // method should have type + description
        guard case .object(let methodSchema) = properties["method"] else {
            Issue.record("Expected method to be an object schema")
            return
        }
        #expect(methodSchema["type"] == .string("string"))
        #expect(methodSchema["description"] == .string("HTTP method (GET, POST, PUT, PATCH, DELETE)"))

        // headers should have type + additionalProperties + description
        guard case .object(let headersSchema) = properties["headers"] else {
            Issue.record("Expected headers to be an object schema")
            return
        }
        #expect(headersSchema["type"] == .string("object"))
        #expect(headersSchema["additionalProperties"] == .object(["type": .string("string")]))
        #expect(headersSchema["description"] == .string("Optional request headers"))

        // body should have type only, no description
        guard case .object(let bodySchema) = properties["body"] else {
            Issue.record("Expected body to be an object schema")
            return
        }
        #expect(bodySchema["type"] == .string("string"))
        #expect(bodySchema["description"] == nil)
    }

    @Test("SchemaDescription works on nested @JSONSchema struct properties")
    func testNestedSchemaWithDescriptions() throws {
        let schema = ServiceInput.jsonSchema

        guard case .object(let topLevel) = schema,
              case .object(let properties) = topLevel["properties"] else {
            Issue.record("Expected object with properties")
            return
        }

        // connection should be ConnectionConfig's schema + description merged in
        guard case .object(let connSchema) = properties["connection"] else {
            Issue.record("Expected connection to be an object schema")
            return
        }
        #expect(connSchema["type"] == .string("object"))
        #expect(connSchema["description"] == .string("Primary connection configuration"))
        // Should still have the nested struct's properties
        guard case .object(let connProperties) = connSchema["properties"] else {
            Issue.record("Expected connection to have properties from ConnectionConfig")
            return
        }
        #expect(connProperties["host"] != nil)
        #expect(connProperties["port"] != nil)

        // fallback should also have description merged
        guard case .object(let fallbackSchema) = properties["fallback"] else {
            Issue.record("Expected fallback to be an object schema")
            return
        }
        #expect(fallbackSchema["type"] == .string("object"))
        #expect(fallbackSchema["description"] == .string("Optional fallback connection"))

        // tags (array of primitives) should have description
        guard case .object(let tagsSchema) = properties["tags"] else {
            Issue.record("Expected tags to be an object schema")
            return
        }
        #expect(tagsSchema["type"] == .string("array"))
        #expect(tagsSchema["description"] == .string("Tags for this service"))

        // required should only contain name and connection
        guard case .array(let required) = topLevel["required"] else {
            Issue.record("Expected required array")
            return
        }
        #expect(required.contains(.string("name")))
        #expect(required.contains(.string("connection")))
        #expect(!required.contains(.string("fallback")))
        #expect(!required.contains(.string("tags")))
    }
}
