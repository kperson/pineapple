import Testing
import Foundation
@testable import JSONValueCoding

@Suite("JSONValue literal expressibility")
struct JSONValueLiteralTests {

    @Test("nil literal becomes .null")
    func nilLiteral() {
        let v: JSONValue = nil
        #expect(v == .null)
    }

    @Test("bool literal becomes .bool")
    func boolLiteral() {
        let t: JSONValue = true
        let f: JSONValue = false
        #expect(t == .bool(true))
        #expect(f == .bool(false))
    }

    @Test("integer literal becomes .int")
    func integerLiteral() {
        let v: JSONValue = 42
        #expect(v == .int(42))
    }

    @Test("float literal becomes .double")
    func floatLiteral() {
        let v: JSONValue = 3.14
        #expect(v == .double(3.14))
    }

    @Test("string literal becomes .string")
    func stringLiteral() {
        let v: JSONValue = "hello"
        #expect(v == .string("hello"))
    }

    @Test("array literal becomes .array")
    func arrayLiteral() {
        let v: JSONValue = [1, "two", true, nil]
        #expect(v == .array([
            .int(1),
            .string("two"),
            .bool(true),
            .null,
        ]))
    }

    @Test("dictionary literal becomes .object")
    func dictionaryLiteral() {
        let v: JSONValue = [
            "type": "string",
            "format": "date-time",
        ]
        #expect(v == .object([
            "type": .string("string"),
            "format": .string("date-time"),
        ]))
    }

    @Test("nested mixed literal builds the right tree")
    func nestedMixedLiteral() {
        let v: JSONValue = [
            "a": 1,
            "b": [true, "x"],
            "c": nil,
            "d": [
                "nested": "yes",
                "depth": 2,
            ],
        ]
        let expected: JSONValue = .object([
            "a": .int(1),
            "b": .array([.bool(true), .string("x")]),
            "c": .null,
            "d": .object([
                "nested": .string("yes"),
                "depth": .int(2),
            ]),
        ])
        #expect(v == expected)
    }

    @Test("literal form encodes identically to explicit form")
    func literalEncodesEquivalently() throws {
        let viaLiteral: JSONValue = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "age": ["type": "integer"],
            ],
        ]
        let viaExplicit: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")]),
                "age": .object(["type": .string("integer")]),
            ]),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let dataA = try encoder.encode(viaLiteral)
        let dataB = try encoder.encode(viaExplicit)
        #expect(dataA == dataB)
    }
}
