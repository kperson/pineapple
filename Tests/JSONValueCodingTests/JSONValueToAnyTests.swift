import Testing
import Foundation
@testable import JSONValueCoding

@Suite("JSONValue.toAny() Tests")
struct JSONValueToAnyTests {

    @Test("null converts to NSNull")
    func testNullToAny() {
        let value = JSONValue.null
        #expect(value.toAny() is NSNull)
    }

    @Test("bool converts to Bool")
    func testBoolToAny() {
        #expect(JSONValue.bool(true).toAny() as? Bool == true)
        #expect(JSONValue.bool(false).toAny() as? Bool == false)
    }

    @Test("int converts to Int")
    func testIntToAny() {
        #expect(JSONValue.int(42).toAny() as? Int == 42)
        #expect(JSONValue.int(-1).toAny() as? Int == -1)
    }

    @Test("int8 converts to Int")
    func testInt8ToAny() {
        #expect(JSONValue.int8(127).toAny() as? Int == 127)
    }

    @Test("int16 converts to Int")
    func testInt16ToAny() {
        #expect(JSONValue.int16(1000).toAny() as? Int == 1000)
    }

    @Test("int32 converts to Int")
    func testInt32ToAny() {
        #expect(JSONValue.int32(100000).toAny() as? Int == 100000)
    }

    @Test("int64 converts to Int")
    func testInt64ToAny() {
        #expect(JSONValue.int64(9999999).toAny() as? Int == 9999999)
    }

    @Test("double converts to Double")
    func testDoubleToAny() {
        #expect(JSONValue.double(3.14).toAny() as? Double == 3.14)
    }

    @Test("string converts to String")
    func testStringToAny() {
        #expect(JSONValue.string("hello").toAny() as? String == "hello")
        #expect(JSONValue.string("").toAny() as? String == "")
    }

    @Test("array converts to [Any]")
    func testArrayToAny() {
        let value = JSONValue.array([.int(1), .string("two"), .bool(true)])
        guard let array = value.toAny() as? [Any] else {
            #expect(Bool(false), "Expected [Any]")
            return
        }
        #expect(array.count == 3)
        #expect(array[0] as? Int == 1)
        #expect(array[1] as? String == "two")
        #expect(array[2] as? Bool == true)
    }

    @Test("object converts to [String: Any]")
    func testObjectToAny() {
        let value = JSONValue.object([
            "name": .string("test"),
            "count": .int(5),
            "active": .bool(true)
        ])
        guard let dict = value.toAny() as? [String: Any] else {
            #expect(Bool(false), "Expected [String: Any]")
            return
        }
        #expect(dict["name"] as? String == "test")
        #expect(dict["count"] as? Int == 5)
        #expect(dict["active"] as? Bool == true)
    }

    @Test("nested objects convert recursively")
    func testNestedObjectToAny() {
        let value = JSONValue.object([
            "outer": .object([
                "inner": .string("deep"),
                "list": .array([.int(1), .int(2)])
            ])
        ])
        guard let dict = value.toAny() as? [String: Any],
              let outer = dict["outer"] as? [String: Any] else {
            #expect(Bool(false), "Expected nested dict")
            return
        }
        #expect(outer["inner"] as? String == "deep")
        guard let list = outer["list"] as? [Any] else {
            #expect(Bool(false), "Expected array")
            return
        }
        #expect(list[0] as? Int == 1)
        #expect(list[1] as? Int == 2)
    }

    @Test("toAny result is JSONSerialization-compatible")
    func testToAnyIsSerializable() throws {
        let value = JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string")
                ]),
                "age": .object([
                    "type": .string("integer")
                ])
            ]),
            "required": .array([.string("name"), .string("age")])
        ])

        let any = value.toAny()
        let data = try JSONSerialization.data(withJSONObject: any)
        #expect(!data.isEmpty)

        // Round-trip back
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed?["type"] as? String == "object")
    }
}
