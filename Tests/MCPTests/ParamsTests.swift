import Testing
import MCP

@Suite("Params Tests")
struct ParamsTests {
    
    // MARK: - Test Fixtures
    
    let validParams = Params([
        "userId": "user-123",
        "count": "42",
        "age": "25",
        "port": "8080",
        "timestamp": "1234567890",
        "largeNumber": "9223372036854775807",
        "requestId": "550e8400-e29b-41d4-a716-446655440000",
        "enabled": "true",
        "disabled": "false",
        "price": "99.99",
        "emptyString": "",
        "int8Max": "127",
        "int8Min": "-128",
        "int16Max": "32767",
        "int16Min": "-32768",
        "int32Max": "2147483647",
        "int32Min": "-2147483648",
        "int64Max": "9223372036854775807",
        "int64Min": "-9223372036854775808",
        "uint8Max": "255",
        "uint16Max": "65535",
        "uint32Max": "4294967295",
        "uint64Max": "18446744073709551615",
        "overflow": "9999999999999999999999",
        "negative": "-1",
        "invalidNumber": "abc",
        "invalidUUID": "not-a-uuid",
        "invalidBool": "yes"
    ])
    
    let emptyParams = Params([:])
    
    // MARK: - Initialization
    
    @Test("Init with values")
    func testInitWithValues() {
        let params = Params(["key1": "value1", "key2": "value2"])
        #expect(params["key1"] == "value1")
        #expect(params["key2"] == "value2")
    }
    
    @Test("Init with empty dictionary")
    func testInitWithEmptyDictionary() {
        let params = Params([:])
        #expect(params["anyKey"] == nil)
        #expect(params.string("anyKey") == nil)
        #expect(params.int("anyKey") == nil)
    }
    
    // MARK: - String Accessors
    
    @Test("String subscript")
    func testStringSubscript() {
        #expect(validParams["userId"] == "user-123")
        #expect(validParams["count"] == "42")
    }
    
    @Test("String function")
    func testStringFunction() {
        #expect(validParams.string("userId") == "user-123")
        #expect(validParams.string("port") == "8080")
    }
    
    @Test("String missing key")
    func testStringMissingKey() {
        #expect(validParams["nonExistent"] == nil)
        #expect(validParams.string("nonExistent") == nil)
        #expect(emptyParams["anyKey"] == nil)
        #expect(emptyParams.string("anyKey") == nil)
    }
    
    // MARK: - Signed Integer Accessors
    
    // MARK: Int
    
    @Test("Int valid conversion")
    func testIntValidConversion() {
        #expect(validParams.int("count") == 42)
        #expect(validParams.int("age") == 25)
        #expect(validParams.int("negative") == -1)
    }
    
    @Test("Int invalid conversion")
    func testIntInvalidConversion() {
        #expect(validParams.int("invalidNumber") == nil)
        #expect(validParams.int("requestId") == nil)
    }
    
    @Test("Int missing key")
    func testIntMissingKey() {
        #expect(validParams.int("nonExistent") == nil)
        #expect(emptyParams.int("anyKey") == nil)
    }
    
    // MARK: Int8
    
    @Test("Int8 valid conversion")
    func testInt8ValidConversion() {
        #expect(validParams.int8("age") == 25)
        #expect(validParams.int8("negative") == -1)
    }
    
    @Test("Int8 boundary min")
    func testInt8BoundaryMin() {
        #expect(validParams.int8("int8Min") == Int8.min)
        #expect(validParams.int8("int8Min") == -128)
    }
    
    @Test("Int8 boundary max")
    func testInt8BoundaryMax() {
        #expect(validParams.int8("int8Max") == Int8.max)
        #expect(validParams.int8("int8Max") == 127)
    }
    
    @Test("Int8 overflow")
    func testInt8Overflow() {
        // Test overflow (128 > Int8.max)
        let overflowParams = Params(["value": "128"])
        #expect(overflowParams.int8("value") == nil)
        
        // Test underflow (-129 < Int8.min)
        let underflowParams = Params(["value": "-129"])
        #expect(underflowParams.int8("value") == nil)
        
        #expect(validParams.int8("overflow") == nil)
    }
    
    // MARK: Int16
    
    @Test("Int16 valid conversion")
    func testInt16ValidConversion() {
        let params = Params(["value": "1000"])
        #expect(params.int16("value") == 1000)
        #expect(validParams.int16("port") == 8080)
    }
    
    @Test("Int16 boundary min")
    func testInt16BoundaryMin() {
        #expect(validParams.int16("int16Min") == Int16.min)
        #expect(validParams.int16("int16Min") == -32768)
    }
    
    @Test("Int16 boundary max")
    func testInt16BoundaryMax() {
        #expect(validParams.int16("int16Max") == Int16.max)
        #expect(validParams.int16("int16Max") == 32767)
    }
    
    @Test("Int16 overflow")
    func testInt16Overflow() {
        // Test overflow
        let overflowParams = Params(["value": "32768"])
        #expect(overflowParams.int16("value") == nil)
        
        // Test underflow
        let underflowParams = Params(["value": "-32769"])
        #expect(underflowParams.int16("value") == nil)
    }
    
    // MARK: Int32
    
    @Test("Int32 valid conversion")
    func testInt32ValidConversion() {
        let params = Params(["value": "100000"])
        #expect(params.int32("value") == 100000)
        #expect(validParams.int32("timestamp") == 1234567890)
    }
    
    @Test("Int32 boundary min")
    func testInt32BoundaryMin() {
        #expect(validParams.int32("int32Min") == Int32.min)
        #expect(validParams.int32("int32Min") == -2147483648)
    }
    
    @Test("Int32 boundary max")
    func testInt32BoundaryMax() {
        #expect(validParams.int32("int32Max") == Int32.max)
        #expect(validParams.int32("int32Max") == 2147483647)
    }
    
    @Test("Int32 overflow")
    func testInt32Overflow() {
        // Test overflow
        let overflowParams = Params(["value": "2147483648"])
        #expect(overflowParams.int32("value") == nil)
        
        #expect(validParams.int32("overflow") == nil)
    }
    
    // MARK: Int64
    
    @Test("Int64 valid conversion")
    func testInt64ValidConversion() {
        #expect(validParams.int64("largeNumber") == 9223372036854775807)
        #expect(validParams.int64("timestamp") == 1234567890)
        #expect(validParams.int64("negative") == -1)
    }
    
    @Test("Int64 boundary min")
    func testInt64BoundaryMin() {
        #expect(validParams.int64("int64Min") == Int64.min)
        #expect(validParams.int64("int64Min") == -9223372036854775808)
    }
    
    @Test("Int64 boundary max")
    func testInt64BoundaryMax() {
        #expect(validParams.int64("int64Max") == Int64.max)
        #expect(validParams.int64("int64Max") == 9223372036854775807)
    }
    
    @Test("Int64 overflow")
    func testInt64Overflow() {
        #expect(validParams.int64("overflow") == nil)
    }
    
    @Test("Int64 invalid conversion")
    func testInt64InvalidConversion() {
        #expect(validParams.int64("invalidNumber") == nil)
        #expect(validParams.int64("requestId") == nil)
    }
    
    @Test("Int64 missing key")
    func testInt64MissingKey() {
        #expect(validParams.int64("nonExistent") == nil)
        #expect(emptyParams.int64("anyKey") == nil)
    }
    
    // MARK: - Unsigned Integer Accessors
    
    // MARK: UInt
    
    @Test("UInt valid conversion")
    func testUIntValidConversion() {
        #expect(validParams.uint("count") == 42)
        #expect(validParams.uint("port") == 8080)
    }
    
    @Test("UInt invalid negative")
    func testUIntInvalidNegative() {
        #expect(validParams.uint("negative") == nil)
    }
    
    @Test("UInt invalid conversion")
    func testUIntInvalidConversion() {
        #expect(validParams.uint("invalidNumber") == nil)
        #expect(validParams.uint("requestId") == nil)
    }
    
    @Test("UInt missing key")
    func testUIntMissingKey() {
        #expect(validParams.uint("nonExistent") == nil)
        #expect(emptyParams.uint("anyKey") == nil)
    }
    
    // MARK: UInt8
    
    @Test("UInt8 valid conversion")
    func testUInt8ValidConversion() {
        #expect(validParams.uint8("age") == 25)
        #expect(validParams.uint8("int8Max") == 127)
    }
    
    @Test("UInt8 boundary max")
    func testUInt8BoundaryMax() {
        #expect(validParams.uint8("uint8Max") == UInt8.max)
        #expect(validParams.uint8("uint8Max") == 255)
    }
    
    @Test("UInt8 overflow")
    func testUInt8Overflow() {
        // Test overflow (256 > UInt8.max)
        let overflowParams = Params(["value": "256"])
        #expect(overflowParams.uint8("value") == nil)
        
        #expect(validParams.uint8("overflow") == nil)
    }
    
    @Test("UInt8 invalid negative")
    func testUInt8InvalidNegative() {
        #expect(validParams.uint8("negative") == nil)
        #expect(validParams.uint8("int8Min") == nil)
    }
    
    // MARK: UInt16
    
    @Test("UInt16 valid conversion")
    func testUInt16ValidConversion() {
        let params = Params(["value": "1000"])
        #expect(params.uint16("value") == 1000)
        #expect(validParams.uint16("port") == 8080)
    }
    
    @Test("UInt16 boundary max")
    func testUInt16BoundaryMax() {
        #expect(validParams.uint16("uint16Max") == UInt16.max)
        #expect(validParams.uint16("uint16Max") == 65535)
    }
    
    @Test("UInt16 overflow")
    func testUInt16Overflow() {
        // Test overflow
        let overflowParams = Params(["value": "65536"])
        #expect(overflowParams.uint16("value") == nil)
    }
    
    @Test("UInt16 invalid negative")
    func testUInt16InvalidNegative() {
        #expect(validParams.uint16("negative") == nil)
    }
    
    // MARK: UInt32
    
    @Test("UInt32 valid conversion")
    func testUInt32ValidConversion() {
        let params = Params(["value": "100000"])
        #expect(params.uint32("value") == 100000)
        #expect(validParams.uint32("timestamp") == 1234567890)
    }
    
    @Test("UInt32 boundary max")
    func testUInt32BoundaryMax() {
        #expect(validParams.uint32("uint32Max") == UInt32.max)
        #expect(validParams.uint32("uint32Max") == 4294967295)
    }
    
    @Test("UInt32 overflow")
    func testUInt32Overflow() {
        // Test overflow
        let overflowParams = Params(["value": "4294967296"])
        #expect(overflowParams.uint32("value") == nil)
        
        #expect(validParams.uint32("overflow") == nil)
    }
    
    @Test("UInt32 invalid negative")
    func testUInt32InvalidNegative() {
        #expect(validParams.uint32("negative") == nil)
    }
    
    // MARK: UInt64
    
    @Test("UInt64 valid conversion")
    func testUInt64ValidConversion() {
        #expect(validParams.uint64("largeNumber") == 9223372036854775807)
        #expect(validParams.uint64("timestamp") == 1234567890)
    }
    
    @Test("UInt64 boundary max")
    func testUInt64BoundaryMax() {
        #expect(validParams.uint64("uint64Max") == UInt64.max)
        #expect(validParams.uint64("uint64Max") == 18446744073709551615)
    }
    
    @Test("UInt64 overflow")
    func testUInt64Overflow() {
        // Test overflow beyond UInt64.max
        let overflowParams = Params(["value": "18446744073709551616"])
        #expect(overflowParams.uint64("value") == nil)
        
        #expect(validParams.uint64("overflow") == nil)
    }
    
    @Test("UInt64 invalid negative")
    func testUInt64InvalidNegative() {
        #expect(validParams.uint64("negative") == nil)
    }
    
    // MARK: - UUID Accessor
    
    @Test("UUID valid conversion")
    func testUUIDValidConversion() {
        let uuid = validParams.uuid("requestId")
        #expect(uuid != nil)
        #expect(uuid?.uuidString.lowercased() == "550e8400-e29b-41d4-a716-446655440000")
    }
    
    @Test("UUID invalid conversion")
    func testUUIDInvalidConversion() {
        #expect(validParams.uuid("invalidUUID") == nil)
        #expect(validParams.uuid("userId") == nil)
        #expect(validParams.uuid("count") == nil)
    }
    
    @Test("UUID missing key")
    func testUUIDMissingKey() {
        #expect(validParams.uuid("nonExistent") == nil)
        #expect(emptyParams.uuid("anyKey") == nil)
    }
    
    // MARK: - Bool Accessor
    
    @Test("Bool valid true conversion")
    func testBoolValidTrueConversion() {
        #expect(validParams.bool("enabled") == true)
    }
    
    @Test("Bool valid false conversion")
    func testBoolValidFalseConversion() {
        #expect(validParams.bool("disabled") == false)
    }
    
    @Test("Bool case insensitive true")
    func testBoolCaseInsensitiveTrue() {
        let params = Params([
            "upperTrue": "TRUE",
            "mixedTrue": "TrUe",
            "lowerTrue": "true"
        ])
        #expect(params.bool("upperTrue") == true)
        #expect(params.bool("mixedTrue") == true)
        #expect(params.bool("lowerTrue") == true)
    }
    
    @Test("Bool case insensitive false")
    func testBoolCaseInsensitiveFalse() {
        let params = Params([
            "upperFalse": "FALSE",
            "mixedFalse": "FaLsE",
            "lowerFalse": "false"
        ])
        #expect(params.bool("upperFalse") == false)
        #expect(params.bool("mixedFalse") == false)
        #expect(params.bool("lowerFalse") == false)
    }
    
    @Test("Bool numeric true")
    func testBoolNumericTrue() {
        let params = Params(["one": "1"])
        #expect(params.bool("one") == true)
    }
    
    @Test("Bool numeric false")
    func testBoolNumericFalse() {
        let params = Params(["zero": "0"])
        #expect(params.bool("zero") == false)
    }
    
    @Test("Bool invalid conversion")
    func testBoolInvalidConversion() {
        #expect(validParams.bool("invalidBool") == nil)
        #expect(validParams.bool("userId") == nil)
        #expect(validParams.bool("count") == nil)
        
        // Test that other numbers besides 0 and 1 are invalid
        let params = Params([
            "two": "2",
            "negative": "-1",
            "ten": "10"
        ])
        #expect(params.bool("two") == nil)
        #expect(params.bool("negative") == nil)
        #expect(params.bool("ten") == nil)
    }
    
    @Test("Bool missing key")
    func testBoolMissingKey() {
        #expect(validParams.bool("nonExistent") == nil)
        #expect(emptyParams.bool("anyKey") == nil)
    }
    
    // MARK: - Double Accessor
    
    @Test("Double valid conversion")
    func testDoubleValidConversion() {
        #expect(validParams.double("price") == 99.99)
        #expect(validParams.double("count") == 42.0)
    }
    
    @Test("Double from integer")
    func testDoubleFromInteger() {
        #expect(validParams.double("age") == 25.0)
        #expect(validParams.double("negative") == -1.0)
    }
    
    @Test("Double invalid conversion")
    func testDoubleInvalidConversion() {
        #expect(validParams.double("invalidNumber") == nil)
        #expect(validParams.double("userId") == nil)
    }
    
    @Test("Double missing key")
    func testDoubleMissingKey() {
        #expect(validParams.double("nonExistent") == nil)
        #expect(emptyParams.double("anyKey") == nil)
    }
    
    // MARK: - JSONValue Initialization
    
    @Test("JSONValue init with string values")
    func testJSONValueInitWithStringValues() throws {
        let jsonValue = JSONValue.object([
            "name": .string("Alice"),
            "userId": .string("user-456")
        ])
        
        let params = try Params(jsonValue)
        #expect(params.string("name") == "Alice")
        #expect(params.string("userId") == "user-456")
    }
    
    @Test("JSONValue init with int values")
    func testJSONValueInitWithIntValues() throws {
        let jsonValue = JSONValue.object([
            "count": .int(42),
            "age": .int(25)
        ])
        
        let params = try Params(jsonValue)
        #expect(params.string("count") == "42")
        #expect(params.int("count") == 42)
        #expect(params.string("age") == "25")
        #expect(params.int("age") == 25)
    }
    
    @Test("JSONValue init with bool values")
    func testJSONValueInitWithBoolValues() throws {
        let jsonValue = JSONValue.object([
            "enabled": .bool(true),
            "disabled": .bool(false)
        ])
        
        let params = try Params(jsonValue)
        #expect(params.string("enabled") == "true")
        #expect(params.bool("enabled") == true)
        #expect(params.string("disabled") == "false")
        #expect(params.bool("disabled") == false)
    }
    
    @Test("JSONValue init with double values")
    func testJSONValueInitWithDoubleValues() throws {
        let jsonValue = JSONValue.object([
            "price": .double(99.99),
            "rate": .double(0.05)
        ])
        
        let params = try Params(jsonValue)
        #expect(params.string("price") == "99.99")
        #expect(params.double("price") == 99.99)
    }
    
    @Test("JSONValue init with mixed types")
    func testJSONValueInitWithMixedTypes() throws {
        let jsonValue = JSONValue.object([
            "name": .string("Bob"),
            "count": .int(100),
            "enabled": .bool(true),
            "price": .double(49.99)
        ])
        
        let params = try Params(jsonValue)
        #expect(params.string("name") == "Bob")
        #expect(params.int("count") == 100)
        #expect(params.bool("enabled") == true)
        #expect(params.double("price") == 49.99)
    }
    
    @Test("JSONValue init with all integer types")
    func testJSONValueInitWithAllIntegerTypes() throws {
        let jsonValue = JSONValue.object([
            "int8Val": .int8(127),
            "int16Val": .int16(32767),
            "int32Val": .int32(2147483647),
            "int64Val": .int64(9223372036854775807),
            "uint8Val": .uint8(255),
            "uint16Val": .uint16(65535),
            "uint32Val": .uint32(4294967295),
            "uint64Val": .uint64(18446744073709551615)
        ])
        
        let params = try Params(jsonValue)
        #expect(params.int8("int8Val") == 127)
        #expect(params.int16("int16Val") == 32767)
        #expect(params.int32("int32Val") == 2147483647)
        #expect(params.int64("int64Val") == 9223372036854775807)
        #expect(params.uint8("uint8Val") == 255)
        #expect(params.uint16("uint16Val") == 65535)
        #expect(params.uint32("uint32Val") == 4294967295)
        #expect(params.uint64("uint64Val") == 18446744073709551615)
    }
    
    @Test("JSONValue init skips null values")
    func testJSONValueInitSkipsNullValues() throws {
        let jsonValue = JSONValue.object([
            "name": .string("Charlie"),
            "nullValue": .null,
            "age": .int(30)
        ])
        
        let params = try Params(jsonValue)
        #expect(params.string("name") == "Charlie")
        #expect(params.string("nullValue") == nil)
        #expect(params.int("age") == 30)
    }
    
    @Test("JSONValue init skips arrays")
    func testJSONValueInitSkipsArrays() throws {
        let jsonValue = JSONValue.object([
            "name": .string("Dave"),
            "tags": .array([.string("tag1"), .string("tag2")]),
            "age": .int(35)
        ])
        
        let params = try Params(jsonValue)
        #expect(params.string("name") == "Dave")
        #expect(params.string("tags") == nil)
        #expect(params.int("age") == 35)
    }
    
    @Test("JSONValue init skips nested objects")
    func testJSONValueInitSkipsNestedObjects() throws {
        let jsonValue = JSONValue.object([
            "name": .string("Eve"),
            "metadata": .object(["key": .string("value")]),
            "age": .int(40)
        ])
        
        let params = try Params(jsonValue)
        #expect(params.string("name") == "Eve")
        #expect(params.string("metadata") == nil)
        #expect(params.int("age") == 40)
    }
    
    @Test("JSONValue init with empty object")
    func testJSONValueInitWithEmptyObject() throws {
        let jsonValue = JSONValue.object([:])
        
        let params = try Params(jsonValue)
        #expect(params.string("anyKey") == nil)
        #expect(params.int("anyKey") == nil)
    }
    
    @Test("JSONValue init throws on non-object")
    func testJSONValueInitThrowsOnNonObject() throws {
        let arrayValue = JSONValue.array([.string("item1"), .string("item2")])
        
        #expect(throws: MCPError.self) {
            _ = try Params(arrayValue)
        }
        
        let stringValue = JSONValue.string("notAnObject")
        #expect(throws: MCPError.self) {
            _ = try Params(stringValue)
        }
    }
}
