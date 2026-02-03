import Testing
import Foundation
@testable import JSONValueCoding

/// Comprehensive tests for JSONValueEncoder and JSONValueDecoder
///
/// Tests the custom Codable implementation that converts Swift types to/from JSONValue.
/// Critical for MCP's dynamic parameter handling and response formatting.
///
/// Tests are organized by type with encoding/decoding/round-trip tests grouped together.
@Suite("JSON Value Coder Tests")
struct JSONValueCoderTests {
    
    // MARK: - Shared Test Data Types
    
    struct TestPerson: Codable, Equatable {
        let name: String
        let age: Int
    }
    
    struct TestPersonWithOptional: Codable, Equatable {
        let name: String
        let age: Int
        let email: String?
    }
    
    struct TestCompany: Codable, Equatable {
        let name: String
        let employees: [TestPerson]
    }
    
    struct TestAddress: Codable, Equatable {
        let street: String
        let city: String
    }
    
    struct TestPersonWithAddress: Codable, Equatable {
        let name: String
        let address: TestAddress
    }
    
    struct TestNumericTypes: Codable, Equatable {
        let int8: Int8
        let int16: Int16
        let int32: Int32
        let int64: Int64
        let uint: UInt
        let uint8: UInt8
        let uint16: UInt16
        let uint32: UInt32
        let uint64: UInt64
    }
    
    enum TestEnum: String, Codable, Equatable {
        case option1
        case option2
        case option3
    }
    
    struct TestWithEnum: Codable, Equatable {
        let name: String
        let status: TestEnum
    }
    
    struct TestWithDictionary: Codable, Equatable {
        let metadata: [String: String]
    }
    
    // MARK: - Primitive Types
    
    @Suite("Null")
    struct NullTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            let optional: String? = nil
            let jsonValue = try encoder.encode(optional)
            #expect(jsonValue == .null)
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            let optional = try decoder.decode(String?.self, from: .null)
            #expect(optional == nil)
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let optional: String? = nil
            let encoded = try encoder.encode(optional)
            let decoded = try decoder.decode(String?.self, from: encoded)
            #expect(decoded == nil)
        }
    }
    
    @Suite("Bool")
    struct BoolTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            
            let trueValue = try encoder.encode(true)
            #expect(trueValue == .bool(true))
            
            let falseValue = try encoder.encode(false)
            #expect(falseValue == .bool(false))
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            
            let trueValue = try decoder.decode(Bool.self, from: .bool(true))
            #expect(trueValue == true)
            
            let falseValue = try decoder.decode(Bool.self, from: .bool(false))
            #expect(falseValue == false)
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            for value in [true, false] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(Bool.self, from: encoded)
                #expect(decoded == value)
            }
        }
    }
    
    @Suite("String")
    struct StringTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            
            // Basic string
            let hello = try encoder.encode("hello")
            #expect(hello == .string("hello"))
            
            // Empty string
            let empty = try encoder.encode("")
            #expect(empty == .string(""))
            
            // Unicode
            let unicode = try encoder.encode("Hello 世界 🚀")
            #expect(unicode == .string("Hello 世界 🚀"))
            
            // Special characters
            let special = try encoder.encode("Line 1\nLine 2\tTabbed")
            #expect(special == .string("Line 1\nLine 2\tTabbed"))
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            
            // Basic string
            let hello = try decoder.decode(String.self, from: .string("hello"))
            #expect(hello == "hello")
            
            // Empty string
            let empty = try decoder.decode(String.self, from: .string(""))
            #expect(empty == "")
            
            // Unicode
            let unicode = try decoder.decode(String.self, from: .string("Hello 世界 🚀"))
            #expect(unicode == "Hello 世界 🚀")
            
            // Special characters
            let special = try decoder.decode(String.self, from: .string("Line 1\nLine 2\tTabbed"))
            #expect(special == "Line 1\nLine 2\tTabbed")
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let values = ["hello", "", "Hello 世界 🚀", "Line 1\nLine 2\tTabbed"]
            for value in values {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(String.self, from: encoded)
                #expect(decoded == value)
            }
        }
    }
    
    @Suite("Int")
    struct IntTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            
            let zero = try encoder.encode(0)
            #expect(zero == .int(0))
            
            let maxInt = try encoder.encode(Int.max)
            #expect(maxInt == .int(Int.max))
            
            let minInt = try encoder.encode(Int.min)
            #expect(minInt == .int(Int.min))
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            
            let zero = try decoder.decode(Int.self, from: .int(0))
            #expect(zero == 0)
            
            let positive = try decoder.decode(Int.self, from: .int(42))
            #expect(positive == 42)
            
            let negative = try decoder.decode(Int.self, from: .int(-100))
            #expect(negative == -100)
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let values = [0, Int.max, Int.min, 42, -100]
            for value in values {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(Int.self, from: encoded)
                #expect(decoded == value)
            }
        }
    }
    
    @Suite("Double")
    struct DoubleTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            
            let pi = try encoder.encode(3.14)
            #expect(pi == .double(3.14))
            
            let zero = try encoder.encode(0.0)
            #expect(zero == .double(0.0))
            
            let negative = try encoder.encode(-2.5)
            #expect(negative == .double(-2.5))
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            
            let pi = try decoder.decode(Double.self, from: .double(3.14))
            #expect(pi == 3.14)
            
            let zero = try decoder.decode(Double.self, from: .double(0.0))
            #expect(zero == 0.0)
            
            // Test numeric coercion: Int to Double
            let fromInt = try decoder.decode(Double.self, from: .int(42))
            #expect(fromInt == 42.0)
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let values = [3.14, 0.0, -2.5, Double.infinity, -Double.infinity]
            for value in values {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(Double.self, from: encoded)
                #expect(decoded == value)
            }
        }
    }
    
    @Suite("Float")
    struct FloatTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            
            let floatValue = try encoder.encode(Float(3.14))
            // Float should be converted to Double
            if case .double(let doubleValue) = floatValue {
                #expect(abs(doubleValue - 3.14) < 0.01)
            } else {
                Issue.record("Expected .double, got \(floatValue)")
            }
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let values: [Float] = [3.14, 0.0, -2.5]
            for value in values {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(Float.self, from: encoded)
                #expect(abs(decoded - value) < 0.01)
            }
        }
    }
    
    @Suite("Decimal")
    struct DecimalTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            
            let decimal1 = try encoder.encode(Decimal(string: "123.456")!)
            #expect(decimal1 == .decimal(Decimal(string: "123.456")!))
            
            let zero = try encoder.encode(Decimal(0))
            #expect(zero == .decimal(Decimal(0)))
            
            let negative = try encoder.encode(Decimal(string: "-99.99")!)
            #expect(negative == .decimal(Decimal(string: "-99.99")!))
            
            // Test high precision
            let highPrecision = try encoder.encode(Decimal(string: "3.141592653589793238")!)
            #expect(highPrecision == .decimal(Decimal(string: "3.141592653589793238")!))
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            
            // Direct decimal
            let decimal1 = try decoder.decode(Decimal.self, from: .decimal(Decimal(string: "123.456")!))
            #expect(decimal1 == Decimal(string: "123.456")!)
            
            // Coerce from Int
            let fromInt = try decoder.decode(Decimal.self, from: .int(42))
            #expect(fromInt == Decimal(42))
            
            // Coerce from Double
            let fromDouble = try decoder.decode(Decimal.self, from: .double(3.14))
            let difference = ((fromDouble - Decimal(3.14)) as NSDecimalNumber).doubleValue
            #expect(difference < 0.001 && difference > -0.001)
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let values = [
                Decimal(string: "123.456")!,
                Decimal(0),
                Decimal(string: "-99.99")!,
                Decimal(string: "9999999999999999999999.999999999999")!
            ]
            
            for value in values {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(Decimal.self, from: encoded)
                #expect(decoded == value)
            }
        }
    }
    
    @Suite("Int Types")
    struct IntTypesTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            
            // Int8
            #expect(try encoder.encode(Int8(0)) == .int8(0))
            #expect(try encoder.encode(Int8.max) == .int8(Int8.max))
            #expect(try encoder.encode(Int8.min) == .int8(Int8.min))
            
            // Int16
            #expect(try encoder.encode(Int16(0)) == .int16(0))
            #expect(try encoder.encode(Int16.max) == .int16(Int16.max))
            #expect(try encoder.encode(Int16.min) == .int16(Int16.min))
            
            // Int32
            #expect(try encoder.encode(Int32(0)) == .int32(0))
            #expect(try encoder.encode(Int32.max) == .int32(Int32.max))
            #expect(try encoder.encode(Int32.min) == .int32(Int32.min))
            
            // Int64
            #expect(try encoder.encode(Int64(0)) == .int64(0))
            #expect(try encoder.encode(Int64.max) == .int64(Int64.max))
            #expect(try encoder.encode(Int64.min) == .int64(Int64.min))
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            
            // Int8
            #expect(try decoder.decode(Int8.self, from: .int8(0)) == 0)
            #expect(try decoder.decode(Int8.self, from: .int8(Int8.max)) == Int8.max)
            #expect(try decoder.decode(Int8.self, from: .int8(Int8.min)) == Int8.min)
            
            // Int16
            #expect(try decoder.decode(Int16.self, from: .int16(0)) == 0)
            #expect(try decoder.decode(Int16.self, from: .int16(Int16.max)) == Int16.max)
            #expect(try decoder.decode(Int16.self, from: .int16(Int16.min)) == Int16.min)
            
            // Int32
            #expect(try decoder.decode(Int32.self, from: .int32(0)) == 0)
            #expect(try decoder.decode(Int32.self, from: .int32(Int32.max)) == Int32.max)
            #expect(try decoder.decode(Int32.self, from: .int32(Int32.min)) == Int32.min)
            
            // Int64
            #expect(try decoder.decode(Int64.self, from: .int64(0)) == 0)
            #expect(try decoder.decode(Int64.self, from: .int64(Int64.max)) == Int64.max)
            #expect(try decoder.decode(Int64.self, from: .int64(Int64.min)) == Int64.min)
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            // Int8
            for value: Int8 in [0, Int8.max, Int8.min] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(Int8.self, from: encoded)
                #expect(decoded == value)
            }
            
            // Int16
            for value: Int16 in [0, Int16.max, Int16.min] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(Int16.self, from: encoded)
                #expect(decoded == value)
            }
            
            // Int32
            for value: Int32 in [0, Int32.max, Int32.min] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(Int32.self, from: encoded)
                #expect(decoded == value)
            }
            
            // Int64
            for value: Int64 in [0, Int64.max, Int64.min] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(Int64.self, from: encoded)
                #expect(decoded == value)
            }
        }
    }
    
    @Suite("UInt Types")
    struct UIntTypesTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            
            // UInt
            #expect(try encoder.encode(UInt(0)) == .uint(0))
            #expect(try encoder.encode(UInt.max) == .uint(UInt.max))
            
            // UInt8
            #expect(try encoder.encode(UInt8(0)) == .uint8(0))
            #expect(try encoder.encode(UInt8.max) == .uint8(UInt8.max))
            
            // UInt16
            #expect(try encoder.encode(UInt16(0)) == .uint16(0))
            #expect(try encoder.encode(UInt16.max) == .uint16(UInt16.max))
            
            // UInt32
            #expect(try encoder.encode(UInt32(0)) == .uint32(0))
            #expect(try encoder.encode(UInt32.max) == .uint32(UInt32.max))
            
            // UInt64
            #expect(try encoder.encode(UInt64(0)) == .uint64(0))
            #expect(try encoder.encode(UInt64.max) == .uint64(UInt64.max))
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            
            // UInt
            #expect(try decoder.decode(UInt.self, from: .uint(0)) == 0)
            #expect(try decoder.decode(UInt.self, from: .uint(UInt.max)) == UInt.max)
            
            // UInt8
            #expect(try decoder.decode(UInt8.self, from: .uint8(0)) == 0)
            #expect(try decoder.decode(UInt8.self, from: .uint8(UInt8.max)) == UInt8.max)
            
            // UInt16
            #expect(try decoder.decode(UInt16.self, from: .uint16(0)) == 0)
            #expect(try decoder.decode(UInt16.self, from: .uint16(UInt16.max)) == UInt16.max)
            
            // UInt32
            #expect(try decoder.decode(UInt32.self, from: .uint32(0)) == 0)
            #expect(try decoder.decode(UInt32.self, from: .uint32(UInt32.max)) == UInt32.max)
            
            // UInt64
            #expect(try decoder.decode(UInt64.self, from: .uint64(0)) == 0)
            #expect(try decoder.decode(UInt64.self, from: .uint64(UInt64.max)) == UInt64.max)
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            // UInt
            for value: UInt in [0, UInt.max] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(UInt.self, from: encoded)
                #expect(decoded == value)
            }
            
            // UInt8
            for value: UInt8 in [0, UInt8.max] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(UInt8.self, from: encoded)
                #expect(decoded == value)
            }
            
            // UInt16
            for value: UInt16 in [0, UInt16.max] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(UInt16.self, from: encoded)
                #expect(decoded == value)
            }
            
            // UInt32
            for value: UInt32 in [0, UInt32.max] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(UInt32.self, from: encoded)
                #expect(decoded == value)
            }
            
            // UInt64
            for value: UInt64 in [0, UInt64.max] {
                let encoded = try encoder.encode(value)
                let decoded = try decoder.decode(UInt64.self, from: encoded)
                #expect(decoded == value)
            }
        }
    }
    
    @Suite("All Numeric Types")
    struct AllNumericTypesTests {
        @Test("Encode in struct")
        func encodeInStruct() throws {
            let encoder = JSONValueEncoder()
            let numeric = TestNumericTypes(
                int8: Int8.max,
                int16: Int16.min,
                int32: 0,
                int64: Int64.max,
                uint: 0,
                uint8: UInt8.max,
                uint16: UInt16.max,
                uint32: 0,
                uint64: UInt64.max
            )
            
            let encoded = try encoder.encode(numeric)
            
            if case .object(let dict) = encoded {
                #expect(dict["int8"] == .int8(Int8.max))
                #expect(dict["int16"] == .int16(Int16.min))
                #expect(dict["int32"] == .int32(0))
                #expect(dict["int64"] == .int64(Int64.max))
                #expect(dict["uint"] == .uint(0))
                #expect(dict["uint8"] == .uint8(UInt8.max))
                #expect(dict["uint16"] == .uint16(UInt16.max))
                #expect(dict["uint32"] == .uint32(0))
                #expect(dict["uint64"] == .uint64(UInt64.max))
            } else {
                Issue.record("Expected object, got \(encoded)")
            }
        }
        
        @Test("Decode from struct")
        func decodeFromStruct() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .object([
                "int8": .int8(Int8.max),
                "int16": .int16(Int16.min),
                "int32": .int32(0),
                "int64": .int64(Int64.max),
                "uint": .uint(0),
                "uint8": .uint8(UInt8.max),
                "uint16": .uint16(UInt16.max),
                "uint32": .uint32(0),
                "uint64": .uint64(UInt64.max)
            ])
            
            let decoded = try decoder.decode(TestNumericTypes.self, from: jsonValue)
            
            #expect(decoded.int8 == Int8.max)
            #expect(decoded.int16 == Int16.min)
            #expect(decoded.int32 == 0)
            #expect(decoded.int64 == Int64.max)
            #expect(decoded.uint == 0)
            #expect(decoded.uint8 == UInt8.max)
            #expect(decoded.uint16 == UInt16.max)
            #expect(decoded.uint32 == 0)
            #expect(decoded.uint64 == UInt64.max)
        }
        
        @Test("Round-trip with max values")
        func roundTripMax() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestNumericTypes(
                int8: Int8.max,
                int16: Int16.max,
                int32: Int32.max,
                int64: Int64.max,
                uint: UInt.max,
                uint8: UInt8.max,
                uint16: UInt16.max,
                uint32: UInt32.max,
                uint64: UInt64.max
            )
            
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestNumericTypes.self, from: encoded)
            #expect(decoded == original)
        }
        
        @Test("Round-trip with min values")
        func roundTripMin() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestNumericTypes(
                int8: Int8.min,
                int16: Int16.min,
                int32: Int32.min,
                int64: Int64.min,
                uint: UInt.min,
                uint8: UInt8.min,
                uint16: UInt16.min,
                uint32: UInt32.min,
                uint64: UInt64.min
            )
            
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestNumericTypes.self, from: encoded)
            #expect(decoded == original)
        }
        
        @Test("Round-trip with zero values")
        func roundTripZero() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestNumericTypes(
                int8: 0,
                int16: 0,
                int32: 0,
                int64: 0,
                uint: 0,
                uint8: 0,
                uint16: 0,
                uint32: 0,
                uint64: 0
            )
            
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestNumericTypes.self, from: encoded)
            #expect(decoded == original)
        }
    }
    
    // MARK: - Collection Types
    
    @Suite("Arrays")
    struct ArrayTests {
        @Test("Encode primitives")
        func encodePrimitives() throws {
            let encoder = JSONValueEncoder()
            
            // String array
            let stringArray = try encoder.encode(["a", "b", "c"])
            #expect(stringArray == .array([.string("a"), .string("b"), .string("c")]))
            
            // Int array
            let intArray = try encoder.encode([1, 2, 3])
            #expect(intArray == .array([.int(1), .int(2), .int(3)]))
            
            // Empty array
            let emptyArray = try encoder.encode([String]())
            #expect(emptyArray == .array([]))
        }
        
        @Test("Decode primitives")
        func decodePrimitives() throws {
            let decoder = JSONValueDecoder()
            
            // String array
            let stringArray = try decoder.decode([String].self, from: .array([.string("a"), .string("b"), .string("c")]))
            #expect(stringArray == ["a", "b", "c"])
            
            // Int array
            let intArray = try decoder.decode([Int].self, from: .array([.int(1), .int(2), .int(3)]))
            #expect(intArray == [1, 2, 3])
            
            // Empty array
            let emptyArray = try decoder.decode([String].self, from: .array([]))
            #expect(emptyArray == [])
        }
        
        @Test("Encode objects")
        func encodeObjects() throws {
            let encoder = JSONValueEncoder()
            let people = [
                TestPerson(name: "Alice", age: 30),
                TestPerson(name: "Bob", age: 25)
            ]
            
            let encoded = try encoder.encode(people)
            
            if case .array(let array) = encoded {
                #expect(array.count == 2)
                
                if case .object(let obj1) = array[0] {
                    #expect(obj1["name"] == .string("Alice"))
                    #expect(obj1["age"] == .int(30))
                } else {
                    Issue.record("Expected object at index 0")
                }
                
                if case .object(let obj2) = array[1] {
                    #expect(obj2["name"] == .string("Bob"))
                    #expect(obj2["age"] == .int(25))
                } else {
                    Issue.record("Expected object at index 1")
                }
            } else {
                Issue.record("Expected array, got \(encoded)")
            }
        }
        
        @Test("Decode objects")
        func decodeObjects() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .array([
                .object(["name": .string("Alice"), "age": .int(30)]),
                .object(["name": .string("Bob"), "age": .int(25)])
            ])
            
            let people = try decoder.decode([TestPerson].self, from: jsonValue)
            
            #expect(people.count == 2)
            #expect(people[0] == TestPerson(name: "Alice", age: 30))
            #expect(people[1] == TestPerson(name: "Bob", age: 25))
        }
        
        @Test("Round-trip primitives")
        func roundTripPrimitives() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let stringArray = ["a", "b", "c"]
            let encoded1 = try encoder.encode(stringArray)
            let decoded1 = try decoder.decode([String].self, from: encoded1)
            #expect(decoded1 == stringArray)
            
            let intArray = [1, 2, 3]
            let encoded2 = try encoder.encode(intArray)
            let decoded2 = try decoder.decode([Int].self, from: encoded2)
            #expect(decoded2 == intArray)
        }
        
        @Test("Round-trip objects")
        func roundTripObjects() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = [
                TestPerson(name: "Alice", age: 30),
                TestPerson(name: "Bob", age: 25)
            ]
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode([TestPerson].self, from: encoded)
            #expect(decoded == original)
        }
    }
    
    @Suite("Dictionaries")
    struct DictionaryTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            let testData = TestWithDictionary(metadata: ["key1": "value1", "key2": "value2"])
            
            let encoded = try encoder.encode(testData)
            
            if case .object(let dict) = encoded {
                if case .object(let metadataDict) = dict["metadata"] {
                    #expect(metadataDict["key1"] == .string("value1"))
                    #expect(metadataDict["key2"] == .string("value2"))
                } else {
                    Issue.record("Expected nested object for metadata")
                }
            } else {
                Issue.record("Expected object, got \(encoded)")
            }
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .object([
                "metadata": .object([
                    "key1": .string("value1"),
                    "key2": .string("value2")
                ])
            ])
            
            let decoded = try decoder.decode(TestWithDictionary.self, from: jsonValue)
            #expect(decoded.metadata["key1"] == "value1")
            #expect(decoded.metadata["key2"] == "value2")
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestWithDictionary(metadata: ["key1": "value1", "key2": "value2"])
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestWithDictionary.self, from: encoded)
            #expect(decoded == original)
        }
        
        @Test("Round-trip empty")
        func roundTripEmpty() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestWithDictionary(metadata: [:])
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestWithDictionary.self, from: encoded)
            #expect(decoded.metadata == [:])
        }
    }
    
    // MARK: - Object Types
    
    @Suite("Simple Objects")
    struct SimpleObjectTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            let person = TestPerson(name: "Alice", age: 30)
            
            let encoded = try encoder.encode(person)
            
            if case .object(let dict) = encoded {
                #expect(dict["name"] == .string("Alice"))
                #expect(dict["age"] == .int(30))
            } else {
                Issue.record("Expected object, got \(encoded)")
            }
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .object(["name": .string("Alice"), "age": .int(30)])
            
            let person = try decoder.decode(TestPerson.self, from: jsonValue)
            
            #expect(person == TestPerson(name: "Alice", age: 30))
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestPerson(name: "Alice", age: 30)
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestPerson.self, from: encoded)
            #expect(decoded == original)
        }
    }
    
    @Suite("Objects with Optionals")
    struct OptionalObjectTests {
        @Test("Encode with value present")
        func encodePresent() throws {
            let encoder = JSONValueEncoder()
            let person = TestPersonWithOptional(name: "Alice", age: 30, email: "alice@example.com")
            
            let encoded = try encoder.encode(person)
            
            if case .object(let dict) = encoded {
                #expect(dict["name"] == .string("Alice"))
                #expect(dict["age"] == .int(30))
                #expect(dict["email"] == .string("alice@example.com"))
            } else {
                Issue.record("Expected object, got \(encoded)")
            }
        }
        
        @Test("Encode with value absent")
        func encodeAbsent() throws {
            let encoder = JSONValueEncoder()
            let person = TestPersonWithOptional(name: "Bob", age: 25, email: nil)
            
            let encoded = try encoder.encode(person)
            
            if case .object(let dict) = encoded {
                #expect(dict["name"] == .string("Bob"))
                #expect(dict["age"] == .int(25))
                // Swift Codable omits nil values by default
                #expect(dict["email"] == nil)
            } else {
                Issue.record("Expected object, got \(encoded)")
            }
        }
        
        @Test("Decode with value present")
        func decodePresent() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .object([
                "name": .string("Alice"),
                "age": .int(30),
                "email": .string("alice@example.com")
            ])
            
            let person = try decoder.decode(TestPersonWithOptional.self, from: jsonValue)
            
            #expect(person.name == "Alice")
            #expect(person.age == 30)
            #expect(person.email == "alice@example.com")
        }
        
        @Test("Decode with value absent")
        func decodeAbsent() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .object([
                "name": .string("Bob"),
                "age": .int(25)
            ])
            
            let person = try decoder.decode(TestPersonWithOptional.self, from: jsonValue)
            
            #expect(person.name == "Bob")
            #expect(person.age == 25)
            #expect(person.email == nil)
        }
        
        @Test("Round-trip with value present")
        func roundTripPresent() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestPersonWithOptional(name: "Alice", age: 30, email: "alice@example.com")
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestPersonWithOptional.self, from: encoded)
            #expect(decoded == original)
        }
        
        @Test("Round-trip with value absent")
        func roundTripAbsent() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestPersonWithOptional(name: "Bob", age: 25, email: nil)
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestPersonWithOptional.self, from: encoded)
            #expect(decoded == original)
        }
    }
    
    @Suite("Nested Objects")
    struct NestedObjectTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            let person = TestPersonWithAddress(
                name: "Alice",
                address: TestAddress(street: "123 Main St", city: "Springfield")
            )
            
            let encoded = try encoder.encode(person)
            
            if case .object(let dict) = encoded {
                #expect(dict["name"] == .string("Alice"))
                
                if case .object(let addressDict) = dict["address"] {
                    #expect(addressDict["street"] == .string("123 Main St"))
                    #expect(addressDict["city"] == .string("Springfield"))
                } else {
                    Issue.record("Expected nested object for address")
                }
            } else {
                Issue.record("Expected object, got \(encoded)")
            }
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .object([
                "name": .string("Alice"),
                "address": .object([
                    "street": .string("123 Main St"),
                    "city": .string("Springfield")
                ])
            ])
            
            let person = try decoder.decode(TestPersonWithAddress.self, from: jsonValue)
            
            #expect(person.name == "Alice")
            #expect(person.address.street == "123 Main St")
            #expect(person.address.city == "Springfield")
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestPersonWithAddress(
                name: "Alice",
                address: TestAddress(street: "123 Main St", city: "Springfield")
            )
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestPersonWithAddress.self, from: encoded)
            #expect(decoded == original)
        }
    }
    
    @Suite("Objects with Arrays")
    struct ObjectWithArrayTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            let company = TestCompany(
                name: "TechCorp",
                employees: [
                    TestPerson(name: "Alice", age: 30),
                    TestPerson(name: "Bob", age: 25)
                ]
            )
            
            let encoded = try encoder.encode(company)
            
            if case .object(let dict) = encoded {
                #expect(dict["name"] == .string("TechCorp"))
                
                if case .array(let employees) = dict["employees"] {
                    #expect(employees.count == 2)
                } else {
                    Issue.record("Expected array for employees")
                }
            } else {
                Issue.record("Expected object, got \(encoded)")
            }
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .object([
                "name": .string("TechCorp"),
                "employees": .array([
                    .object(["name": .string("Alice"), "age": .int(30)]),
                    .object(["name": .string("Bob"), "age": .int(25)])
                ])
            ])
            
            let company = try decoder.decode(TestCompany.self, from: jsonValue)
            
            #expect(company.name == "TechCorp")
            #expect(company.employees.count == 2)
            #expect(company.employees[0] == TestPerson(name: "Alice", age: 30))
            #expect(company.employees[1] == TestPerson(name: "Bob", age: 25))
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestCompany(
                name: "TechCorp",
                employees: [
                    TestPerson(name: "Alice", age: 30),
                    TestPerson(name: "Bob", age: 25)
                ]
            )
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestCompany.self, from: encoded)
            #expect(decoded == original)
        }
    }
    
    // MARK: - Special Types
    
    @Suite("Enums")
    struct EnumTests {
        @Test("Encode")
        func encode() throws {
            let encoder = JSONValueEncoder()
            let testData = TestWithEnum(name: "Test", status: .option2)
            
            let encoded = try encoder.encode(testData)
            
            if case .object(let dict) = encoded {
                #expect(dict["name"] == .string("Test"))
                #expect(dict["status"] == .string("option2"))
            } else {
                Issue.record("Expected object, got \(encoded)")
            }
        }
        
        @Test("Decode")
        func decode() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .object([
                "name": .string("Test"),
                "status": .string("option2")
            ])
            
            let decoded = try decoder.decode(TestWithEnum.self, from: jsonValue)
            #expect(decoded.name == "Test")
            #expect(decoded.status == .option2)
        }
        
        @Test("Round-trip")
        func roundTrip() throws {
            let encoder = JSONValueEncoder()
            let decoder = JSONValueDecoder()
            
            let original = TestWithEnum(name: "Test", status: .option2)
            let encoded = try encoder.encode(original)
            let decoded = try decoder.decode(TestWithEnum.self, from: encoded)
            #expect(decoded == original)
        }
    }
    
    // MARK: - Error Handling
    
    @Suite("Error Handling")
    struct ErrorTests {
        @Test("Decode type mismatch")
        func typeMismatch() throws {
            let decoder = JSONValueDecoder()
            
            // Try to decode String as Int
            #expect(throws: DecodingError.self) {
                _ = try decoder.decode(Int.self, from: .string("not a number"))
            }
            
            // Try to decode Int as String
            #expect(throws: DecodingError.self) {
                _ = try decoder.decode(String.self, from: .int(42))
            }
        }
        
        @Test("Decode missing key")
        func missingKey() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .object(["name": .string("Alice")])
            
            // TestPerson requires both name and age
            #expect(throws: DecodingError.self) {
                _ = try decoder.decode(TestPerson.self, from: jsonValue)
            }
        }
        
        @Test("Decode wrong array element type")
        func wrongArrayElement() throws {
            let decoder = JSONValueDecoder()
            let jsonValue: JSONValue = .array([.int(1), .string("not a number"), .int(3)])
            
            #expect(throws: DecodingError.self) {
                _ = try decoder.decode([Int].self, from: jsonValue)
            }
        }
    }
}
