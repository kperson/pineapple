import Testing
import Foundation
@testable import JSONValueCoding

@Suite("JSONValue Accessor Tests")
struct JSONValueAccessorsTests {
    
    // MARK: - Bool Accessor Tests
    
    @Test("Bool accessor returns value for bool case")
    func testBoolAccessorReturnsValueForBoolCase() {
        let jsonTrue = JSONValue.bool(true)
        let jsonFalse = JSONValue.bool(false)
        
        #expect(jsonTrue.bool == true)
        #expect(jsonFalse.bool == false)
    }
    
    @Test("Bool accessor returns nil for non-bool cases")
    func testBoolAccessorReturnsNilForNonBoolCases() {
        #expect(JSONValue.null.bool == nil)
        #expect(JSONValue.int(42).bool == nil)
        #expect(JSONValue.string("true").bool == nil)
        #expect(JSONValue.array([]).bool == nil)
        #expect(JSONValue.object([:]).bool == nil)
    }
    
    // MARK: - Int Accessor Tests
    
    @Test("Int accessor returns value for int case")
    func testIntAccessorReturnsValueForIntCase() {
        let json = JSONValue.int(42)
        #expect(json.int == 42)
    }
    
    @Test("Int accessor returns nil for non-int cases")
    func testIntAccessorReturnsNilForNonIntCases() {
        #expect(JSONValue.null.int == nil)
        #expect(JSONValue.bool(true).int == nil)
        #expect(JSONValue.int8(10).int == nil)
        #expect(JSONValue.double(3.14).int == nil)
        #expect(JSONValue.string("42").int == nil)
    }
    
    // MARK: - Int8 Accessor Tests
    
    @Test("Int8 accessor returns value for int8 case")
    func testInt8AccessorReturnsValueForInt8Case() {
        let json = JSONValue.int8(127)
        #expect(json.int8 == 127)
    }
    
    @Test("Int8 accessor returns nil for non-int8 cases")
    func testInt8AccessorReturnsNilForNonInt8Cases() {
        #expect(JSONValue.null.int8 == nil)
        #expect(JSONValue.int(42).int8 == nil)
        #expect(JSONValue.int16(100).int8 == nil)
    }
    
    // MARK: - Int16 Accessor Tests
    
    @Test("Int16 accessor returns value for int16 case")
    func testInt16AccessorReturnsValueForInt16Case() {
        let json = JSONValue.int16(32767)
        #expect(json.int16 == 32767)
    }
    
    @Test("Int16 accessor returns nil for non-int16 cases")
    func testInt16AccessorReturnsNilForNonInt16Cases() {
        #expect(JSONValue.null.int16 == nil)
        #expect(JSONValue.int(42).int16 == nil)
        #expect(JSONValue.int8(10).int16 == nil)
    }
    
    // MARK: - Int32 Accessor Tests
    
    @Test("Int32 accessor returns value for int32 case")
    func testInt32AccessorReturnsValueForInt32Case() {
        let json = JSONValue.int32(2147483647)
        #expect(json.int32 == 2147483647)
    }
    
    @Test("Int32 accessor returns nil for non-int32 cases")
    func testInt32AccessorReturnsNilForNonInt32Cases() {
        #expect(JSONValue.null.int32 == nil)
        #expect(JSONValue.int(42).int32 == nil)
    }
    
    // MARK: - Int64 Accessor Tests
    
    @Test("Int64 accessor returns value for int64 case")
    func testInt64AccessorReturnsValueForInt64Case() {
        let json = JSONValue.int64(9223372036854775807)
        #expect(json.int64 == 9223372036854775807)
    }
    
    @Test("Int64 accessor returns nil for non-int64 cases")
    func testInt64AccessorReturnsNilForNonInt64Cases() {
        #expect(JSONValue.null.int64 == nil)
        #expect(JSONValue.int(42).int64 == nil)
    }
    
    // MARK: - UInt Accessor Tests
    
    @Test("UInt accessor returns value for uint case")
    func testUIntAccessorReturnsValueForUIntCase() {
        let json = JSONValue.uint(42)
        #expect(json.uint == 42)
    }
    
    @Test("UInt accessor returns nil for non-uint cases")
    func testUIntAccessorReturnsNilForNonUIntCases() {
        #expect(JSONValue.null.uint == nil)
        #expect(JSONValue.int(42).uint == nil)
        #expect(JSONValue.uint8(10).uint == nil)
    }
    
    // MARK: - UInt8 Accessor Tests
    
    @Test("UInt8 accessor returns value for uint8 case")
    func testUInt8AccessorReturnsValueForUInt8Case() {
        let json = JSONValue.uint8(255)
        #expect(json.uint8 == 255)
    }
    
    @Test("UInt8 accessor returns nil for non-uint8 cases")
    func testUInt8AccessorReturnsNilForNonUInt8Cases() {
        #expect(JSONValue.null.uint8 == nil)
        #expect(JSONValue.uint(42).uint8 == nil)
    }
    
    // MARK: - UInt16 Accessor Tests
    
    @Test("UInt16 accessor returns value for uint16 case")
    func testUInt16AccessorReturnsValueForUInt16Case() {
        let json = JSONValue.uint16(65535)
        #expect(json.uint16 == 65535)
    }
    
    @Test("UInt16 accessor returns nil for non-uint16 cases")
    func testUInt16AccessorReturnsNilForNonUInt16Cases() {
        #expect(JSONValue.null.uint16 == nil)
        #expect(JSONValue.uint(42).uint16 == nil)
    }
    
    // MARK: - UInt32 Accessor Tests
    
    @Test("UInt32 accessor returns value for uint32 case")
    func testUInt32AccessorReturnsValueForUInt32Case() {
        let json = JSONValue.uint32(4294967295)
        #expect(json.uint32 == 4294967295)
    }
    
    @Test("UInt32 accessor returns nil for non-uint32 cases")
    func testUInt32AccessorReturnsNilForNonUInt32Cases() {
        #expect(JSONValue.null.uint32 == nil)
        #expect(JSONValue.uint(42).uint32 == nil)
    }
    
    // MARK: - UInt64 Accessor Tests
    
    @Test("UInt64 accessor returns value for uint64 case")
    func testUInt64AccessorReturnsValueForUInt64Case() {
        let json = JSONValue.uint64(18446744073709551615)
        #expect(json.uint64 == 18446744073709551615)
    }
    
    @Test("UInt64 accessor returns nil for non-uint64 cases")
    func testUInt64AccessorReturnsNilForNonUInt64Cases() {
        #expect(JSONValue.null.uint64 == nil)
        #expect(JSONValue.uint(42).uint64 == nil)
    }
    
    // MARK: - Double Accessor Tests
    
    @Test("Double accessor returns value for double case")
    func testDoubleAccessorReturnsValueForDoubleCase() {
        let json = JSONValue.double(3.14159)
        #expect(json.double == 3.14159)
    }
    
    @Test("Double accessor returns nil for non-double cases")
    func testDoubleAccessorReturnsNilForNonDoubleCases() {
        #expect(JSONValue.null.double == nil)
        #expect(JSONValue.int(42).double == nil)
        #expect(JSONValue.decimal(Decimal(3.14)).double == nil)
        #expect(JSONValue.string("3.14").double == nil)
    }
    
    // MARK: - Decimal Accessor Tests
    
    @Test("Decimal accessor returns value for decimal case")
    func testDecimalAccessorReturnsValueForDecimalCase() {
        let decimalValue = Decimal(string: "123.456")!
        let json = JSONValue.decimal(decimalValue)
        #expect(json.decimal == decimalValue)
    }
    
    @Test("Decimal accessor returns nil for non-decimal cases")
    func testDecimalAccessorReturnsNilForNonDecimalCases() {
        #expect(JSONValue.null.decimal == nil)
        #expect(JSONValue.int(42).decimal == nil)
        #expect(JSONValue.double(3.14).decimal == nil)
    }
    
    // MARK: - String Accessor Tests
    
    @Test("String accessor returns value for string case")
    func testStringAccessorReturnsValueForStringCase() {
        let json = JSONValue.string("hello")
        #expect(json.string == "hello")
    }
    
    @Test("String accessor returns nil for non-string cases")
    func testStringAccessorReturnsNilForNonStringCases() {
        #expect(JSONValue.null.string == nil)
        #expect(JSONValue.int(42).string == nil)
        #expect(JSONValue.bool(true).string == nil)
        #expect(JSONValue.array([]).string == nil)
        #expect(JSONValue.object([:]).string == nil)
    }
    
    // MARK: - Array Accessor Tests
    
    @Test("Array accessor returns value for array case")
    func testArrayAccessorReturnsValueForArrayCase() {
        let arrayValue: [JSONValue] = [.int(1), .string("two"), .bool(true)]
        let json = JSONValue.array(arrayValue)
        
        guard let result = json.array else {
            #expect(Bool(false), "Expected array to be non-nil")
            return
        }
        
        #expect(result.count == 3)
        #expect(result[0].int == 1)
        #expect(result[1].string == "two")
        #expect(result[2].bool == true)
    }
    
    @Test("Array accessor returns nil for non-array cases")
    func testArrayAccessorReturnsNilForNonArrayCases() {
        #expect(JSONValue.null.array == nil)
        #expect(JSONValue.int(42).array == nil)
        #expect(JSONValue.string("[]").array == nil)
        #expect(JSONValue.object([:]).array == nil)
    }
    
    // MARK: - Object Accessor Tests
    
    @Test("Object accessor returns value for object case")
    func testObjectAccessorReturnsValueForObjectCase() {
        let objectValue: [String: JSONValue] = [
            "name": .string("Alice"),
            "age": .int(30),
            "active": .bool(true)
        ]
        let json = JSONValue.object(objectValue)
        
        guard let result = json.object else {
            #expect(Bool(false), "Expected object to be non-nil")
            return
        }
        
        #expect(result.count == 3)
        #expect(result["name"]?.string == "Alice")
        #expect(result["age"]?.int == 30)
        #expect(result["active"]?.bool == true)
    }
    
    @Test("Object accessor returns nil for non-object cases")
    func testObjectAccessorReturnsNilForNonObjectCases() {
        #expect(JSONValue.null.object == nil)
        #expect(JSONValue.int(42).object == nil)
        #expect(JSONValue.string("{}").object == nil)
        #expect(JSONValue.array([]).object == nil)
    }
    
    // MARK: - IsNull Accessor Tests
    
    @Test("IsNull returns true for null case")
    func testIsNullReturnsTrueForNullCase() {
        let json = JSONValue.null
        #expect(json.isNull == true)
    }
    
    @Test("IsNull returns false for non-null cases")
    func testIsNullReturnsFalseForNonNullCases() {
        #expect(JSONValue.bool(false).isNull == false)
        #expect(JSONValue.int(0).isNull == false)
        #expect(JSONValue.string("").isNull == false)
        #expect(JSONValue.array([]).isNull == false)
        #expect(JSONValue.object([:]).isNull == false)
    }
    
    // MARK: - Chained Access Tests
    
    @Test("Chained access works for nested objects")
    func testChainedAccessWorksForNestedObjects() {
        let json = JSONValue.object([
            "user": .object([
                "profile": .object([
                    "name": .string("Alice"),
                    "age": .int(30)
                ]),
                "active": .bool(true)
            ])
        ])
        
        // Test chained optional access
        let name = json.object?["user"]?.object?["profile"]?.object?["name"]?.string
        let age = json.object?["user"]?.object?["profile"]?.object?["age"]?.int
        let active = json.object?["user"]?.object?["active"]?.bool
        
        #expect(name == "Alice")
        #expect(age == 30)
        #expect(active == true)
    }
    
    @Test("Chained access returns nil for invalid paths")
    func testChainedAccessReturnsNilForInvalidPaths() {
        let json = JSONValue.object([
            "user": .object([
                "name": .string("Alice")
            ])
        ])
        
        // Invalid path
        let result = json.object?["user"]?.object?["nonexistent"]?.string
        #expect(result == nil)
        
        // Type mismatch
        let wrongType = json.object?["user"]?.array
        #expect(wrongType == nil)
    }
    
    @Test("Array of objects can be accessed")
    func testArrayOfObjectsCanBeAccessed() {
        let json = JSONValue.array([
            .object(["id": .int(1), "name": .string("Alice")]),
            .object(["id": .int(2), "name": .string("Bob")]),
            .object(["id": .int(3), "name": .string("Charlie")])
        ])
        
        guard let array = json.array else {
            #expect(Bool(false), "Expected array")
            return
        }
        
        #expect(array.count == 3)
        #expect(array[0].object?["name"]?.string == "Alice")
        #expect(array[1].object?["id"]?.int == 2)
        #expect(array[2].object?["name"]?.string == "Charlie")
    }
    
    // MARK: - Numeric Conversion Tests
    
    @Test("Numeric values remain type-specific")
    func testNumericValuesRemainTypeSpecific() {
        // Each numeric type should only match its own accessor
        let intValue = JSONValue.int(42)
        let doubleValue = JSONValue.double(42.0)
        let int8Value = JSONValue.int8(42)
        let uint64Value = JSONValue.uint64(42)
        
        // Int should only match .int
        #expect(intValue.int == 42)
        #expect(intValue.double == nil)
        #expect(intValue.int8 == nil)
        #expect(intValue.uint64 == nil)
        
        // Double should only match .double
        #expect(doubleValue.double == 42.0)
        #expect(doubleValue.int == nil)
        
        // Int8 should only match .int8
        #expect(int8Value.int8 == 42)
        #expect(int8Value.int == nil)
        
        // UInt64 should only match .uint64
        #expect(uint64Value.uint64 == 42)
        #expect(uint64Value.int == nil)
    }
}
