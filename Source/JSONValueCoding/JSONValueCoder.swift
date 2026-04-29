import Foundation

/// Encodes Swift `Codable` types to `JSONValue`
///
/// `JSONValueEncoder` provides a bridge between Swift's type-safe `Codable` system
/// and the dynamic `JSONValue` type used throughout the MCP framework.
///
/// ## Usage
///
/// ```swift
/// let encoder = JSONValueEncoder()
/// let person = Person(name: "Alice", age: 30)
/// let jsonValue = try encoder.encode(person)
/// // jsonValue: .object(["name": .string("Alice"), "age": .int(30)])
/// ```
///
/// ## Type Mapping
///
/// - `Bool` → `.bool(Bool)`
/// - `Int`, `Int8`, `Int16`, `Int32`, `Int64` → `.int(Int)`
/// - `UInt`, `UInt8`, `UInt16`, `UInt32`, `UInt64` → `.int(Int)`
/// - `Double`, `Float` → `.double(Double)`
/// - `String` → `.string(String)`
/// - `Decimal` → `.string(String)` (preserves precision)
/// - Arrays → `.array([JSONValue])`
/// - Objects/Structs → `.object([String: JSONValue])`
/// - `nil` → `.null` or omitted (Swift default for optionals)
///
/// ## Thread Safety
///
/// `JSONValueEncoder` is thread-safe and can be used concurrently.
public struct JSONValueEncoder {

    /// User-provided contextual information for use during encoding
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Encodes the given value to a JSONValue
    ///
    /// - Parameter value: The value to encode
    /// - Returns: The encoded JSONValue representation
    /// - Throws: EncodingError if encoding fails
    public func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        // Handle special types that have their own Codable implementations
        // but we want to encode directly to JSONValue cases.
        //
        // `Date` becomes an ISO 8601 string — the default for tool wire
        // formats. The matching JSONSchema (advertised by `Date.jsonSchema`)
        // is `{"type": "string", "format": "date-time"}`.
        if let date = value as? Date {
            return .string(JSONValueDateFormatter.string(from: date))
        } else if let decimal = value as? Decimal {
            return .decimal(decimal)
        } else if let int8 = value as? Int8 {
            return .int8(int8)
        } else if let int16 = value as? Int16 {
            return .int16(int16)
        } else if let int32 = value as? Int32 {
            return .int32(int32)
        } else if let int64 = value as? Int64 {
            return .int64(int64)
        } else if let uint = value as? UInt {
            return .uint(uint)
        } else if let uint8 = value as? UInt8 {
            return .uint8(uint8)
        } else if let uint16 = value as? UInt16 {
            return .uint16(uint16)
        } else if let uint32 = value as? UInt32 {
            return .uint32(uint32)
        } else if let uint64 = value as? UInt64 {
            return .uint64(uint64)
        }

        let encoder = _JSONValueEncoder()
        encoder.userInfo = self.userInfo
        try value.encode(to: encoder)
        return encoder.value ?? .null
    }

    // Specific overloads for numeric types to ensure they use the correct JSONValue case
    public func encode(_ value: Int8) throws -> JSONValue { .int8(value) }
    public func encode(_ value: Int16) throws -> JSONValue { .int16(value) }
    public func encode(_ value: Int32) throws -> JSONValue { .int32(value) }
    public func encode(_ value: Int64) throws -> JSONValue { .int64(value) }
    public func encode(_ value: UInt) throws -> JSONValue { .uint(value) }
    public func encode(_ value: UInt8) throws -> JSONValue { .uint8(value) }
    public func encode(_ value: UInt16) throws -> JSONValue { .uint16(value) }
    public func encode(_ value: UInt32) throws -> JSONValue { .uint32(value) }
    public func encode(_ value: UInt64) throws -> JSONValue { .uint64(value) }
    public func encode(_ value: Decimal) throws -> JSONValue { .decimal(value) }
}

/// Decodes `JSONValue` to Swift `Codable` types
///
/// `JSONValueDecoder` provides a bridge from the dynamic `JSONValue` type
/// to Swift's type-safe `Codable` system.
///
/// ## Usage
///
/// ```swift
/// let decoder = JSONValueDecoder()
/// let jsonValue: JSONValue = .object(["name": .string("Alice"), "age": .int(30)])
/// let person = try decoder.decode(Person.self, from: jsonValue)
/// ```
///
/// ## Numeric Coercion
///
/// The decoder automatically coerces between numeric types:
/// - `.int(42)` can decode to `Int` or `Double`
/// - `.double(42.0)` can decode to `Double` or `Int`
///
/// ## Thread Safety
///
/// `JSONValueDecoder` is thread-safe and can be used concurrently.
public struct JSONValueDecoder {

    /// User-provided contextual information for use during decoding
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Decodes a value of the given type from a JSONValue
    ///
    /// - Parameters:
    ///   - type: The type to decode
    ///   - jsonValue: The JSONValue to decode from
    /// - Returns: The decoded value
    /// - Throws: DecodingError if decoding fails
    public func decode<T: Decodable>(_ type: T.Type, from jsonValue: JSONValue) throws -> T {
        // Handle special types that have their own Codable implementations
        // but we want to decode directly from JSONValue cases.
        //
        // `Date` is read as an ISO 8601 string. Both `2026-04-28T15:30:00Z`
        // and `2026-04-28T15:30:00.123Z` (fractional seconds) are accepted.
        if T.self == Date.self {
            guard case .string(let str) = jsonValue else {
                throw DecodingError.typeMismatch(Date.self, .init(
                    codingPath: [],
                    debugDescription: "Expected ISO 8601 date-time string for Date, got \(jsonValue)"
                ))
            }
            guard let date = JSONValueDateFormatter.date(from: str) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Could not parse '\(str)' as ISO 8601 date-time"
                ))
            }
            return date as! T
        } else if T.self == Decimal.self {
            return try decode(Decimal.self, from: jsonValue) as! T
        } else if T.self == Int8.self {
            return try decode(Int8.self, from: jsonValue) as! T
        } else if T.self == Int16.self {
            return try decode(Int16.self, from: jsonValue) as! T
        } else if T.self == Int32.self {
            return try decode(Int32.self, from: jsonValue) as! T
        } else if T.self == Int64.self {
            return try decode(Int64.self, from: jsonValue) as! T
        } else if T.self == UInt.self {
            return try decode(UInt.self, from: jsonValue) as! T
        } else if T.self == UInt8.self {
            return try decode(UInt8.self, from: jsonValue) as! T
        } else if T.self == UInt16.self {
            return try decode(UInt16.self, from: jsonValue) as! T
        } else if T.self == UInt32.self {
            return try decode(UInt32.self, from: jsonValue) as! T
        } else if T.self == UInt64.self {
            return try decode(UInt64.self, from: jsonValue) as! T
        }

        let decoder = _JSONValueDecoder(value: jsonValue)
        decoder.userInfo = self.userInfo
        return try T(from: decoder)
    }

    // Specific overloads for numeric types to ensure they decode from the correct JSONValue case
    public func decode(_ type: Int8.Type, from jsonValue: JSONValue) throws -> Int8 {
        guard case .int8(let value) = jsonValue else {
            throw DecodingError.typeMismatch(Int8.self, DecodingError.Context(codingPath: [], debugDescription: "Expected Int8 but found \(jsonValue.typeDescription)"))
        }
        return value
    }

    public func decode(_ type: Int16.Type, from jsonValue: JSONValue) throws -> Int16 {
        guard case .int16(let value) = jsonValue else {
            throw DecodingError.typeMismatch(Int16.self, DecodingError.Context(codingPath: [], debugDescription: "Expected Int16 but found \(jsonValue.typeDescription)"))
        }
        return value
    }

    public func decode(_ type: Int32.Type, from jsonValue: JSONValue) throws -> Int32 {
        guard case .int32(let value) = jsonValue else {
            throw DecodingError.typeMismatch(Int32.self, DecodingError.Context(codingPath: [], debugDescription: "Expected Int32 but found \(jsonValue.typeDescription)"))
        }
        return value
    }

    public func decode(_ type: Int64.Type, from jsonValue: JSONValue) throws -> Int64 {
        guard case .int64(let value) = jsonValue else {
            throw DecodingError.typeMismatch(Int64.self, DecodingError.Context(codingPath: [], debugDescription: "Expected Int64 but found \(jsonValue.typeDescription)"))
        }
        return value
    }

    public func decode(_ type: UInt.Type, from jsonValue: JSONValue) throws -> UInt {
        guard case .uint(let value) = jsonValue else {
            throw DecodingError.typeMismatch(UInt.self, DecodingError.Context(codingPath: [], debugDescription: "Expected UInt but found \(jsonValue.typeDescription)"))
        }
        return value
    }

    public func decode(_ type: UInt8.Type, from jsonValue: JSONValue) throws -> UInt8 {
        guard case .uint8(let value) = jsonValue else {
            throw DecodingError.typeMismatch(UInt8.self, DecodingError.Context(codingPath: [], debugDescription: "Expected UInt8 but found \(jsonValue.typeDescription)"))
        }
        return value
    }

    public func decode(_ type: UInt16.Type, from jsonValue: JSONValue) throws -> UInt16 {
        guard case .uint16(let value) = jsonValue else {
            throw DecodingError.typeMismatch(UInt16.self, DecodingError.Context(codingPath: [], debugDescription: "Expected UInt16 but found \(jsonValue.typeDescription)"))
        }
        return value
    }

    public func decode(_ type: UInt32.Type, from jsonValue: JSONValue) throws -> UInt32 {
        guard case .uint32(let value) = jsonValue else {
            throw DecodingError.typeMismatch(UInt32.self, DecodingError.Context(codingPath: [], debugDescription: "Expected UInt32 but found \(jsonValue.typeDescription)"))
        }
        return value
    }

    public func decode(_ type: UInt64.Type, from jsonValue: JSONValue) throws -> UInt64 {
        guard case .uint64(let value) = jsonValue else {
            throw DecodingError.typeMismatch(UInt64.self, DecodingError.Context(codingPath: [], debugDescription: "Expected UInt64 but found \(jsonValue.typeDescription)"))
        }
        return value
    }

    public func decode(_ type: Decimal.Type, from jsonValue: JSONValue) throws -> Decimal {
        switch jsonValue {
        case .decimal(let value): return value
        case .int(let int): return Decimal(int)
        case .int8(let int8): return Decimal(Int(int8))
        case .int16(let int16): return Decimal(Int(int16))
        case .int32(let int32): return Decimal(Int(int32))
        case .int64(let int64): return Decimal(int64)
        case .uint(let uint): return Decimal(uint)
        case .uint8(let uint8): return Decimal(UInt(uint8))
        case .uint16(let uint16): return Decimal(UInt(uint16))
        case .uint32(let uint32): return Decimal(UInt(uint32))
        case .uint64(let uint64): return Decimal(uint64)
        case .double(let double): return Decimal(double)
        default:
            throw DecodingError.typeMismatch(Decimal.self, DecodingError.Context(codingPath: [], debugDescription: "Expected Decimal but found \(jsonValue.typeDescription)"))
        }
    }
}

// MARK: - Internal Encoder Implementation

/// Shared storage for building up JSONValue during encoding
private final class EncoderStorage: @unchecked Sendable {
    var value: JSONValue?
}

private final class _JSONValueEncoder: Encoder, @unchecked Sendable {
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any]

    // Use shared storage so nested containers can update parent's value
    let storage: EncoderStorage

    var value: JSONValue? {
        get { storage.value }
        set { storage.value = newValue }
    }

    init(codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey: Any] = [:], storage: EncoderStorage = EncoderStorage()) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.storage = storage
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let container = JSONValueKeyedEncodingContainer<Key>(encoder: self)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        JSONValueUnkeyedEncodingContainer(encoder: self)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        JSONValueSingleValueEncodingContainer(encoder: self)
    }
}

// MARK: - Internal Decoder Implementation

private final class _JSONValueDecoder: Decoder, @unchecked Sendable {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    let value: JSONValue

    init(value: JSONValue, codingPath: [CodingKey] = []) {
        self.value = value
        self.codingPath = codingPath
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        guard case .object(let dict) = value else {
            throw DecodingError.typeMismatch(
                [String: JSONValue].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected object but found \(value.typeDescription)"
                )
            )
        }
        let container = JSONValueKeyedDecodingContainer<Key>(decoder: self, dict: dict)
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let array) = value else {
            throw DecodingError.typeMismatch(
                [JSONValue].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected array but found \(value.typeDescription)"
                )
            )
        }
        return JSONValueUnkeyedDecodingContainer(decoder: self, array: array)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        JSONValueSingleValueDecodingContainer(decoder: self, value: value)
    }
}

// MARK: - Helper Extensions

private extension JSONValue {
    var typeDescription: String {
        switch self {
        case .null: return "null"
        case .bool: return "bool"
        case .int: return "int"
        case .int8: return "int8"
        case .int16: return "int16"
        case .int32: return "int32"
        case .int64: return "int64"
        case .uint: return "uint"
        case .uint8: return "uint8"
        case .uint16: return "uint16"
        case .uint32: return "uint32"
        case .uint64: return "uint64"
        case .double: return "double"
        case .decimal: return "decimal"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }

    // Helper to extract Int64 value from any integer case
    func asInt64() -> Int64? {
        switch self {
        case .int(let v): return Int64(v)
        case .int8(let v): return Int64(v)
        case .int16(let v): return Int64(v)
        case .int32(let v): return Int64(v)
        case .int64(let v): return v
        case .uint(let v): return v <= Int64.max ? Int64(v) : nil
        case .uint8(let v): return Int64(v)
        case .uint16(let v): return Int64(v)
        case .uint32(let v): return Int64(v)
        case .uint64(let v): return v <= UInt64(Int64.max) ? Int64(v) : nil
        case .double(let v): return Int64(v)
        default: return nil
        }
    }

    // Helper to extract UInt64 value from any integer case
    func asUInt64() -> UInt64? {
        switch self {
        case .int(let v): return v >= 0 ? UInt64(v) : nil
        case .int8(let v): return v >= 0 ? UInt64(v) : nil
        case .int16(let v): return v >= 0 ? UInt64(v) : nil
        case .int32(let v): return v >= 0 ? UInt64(v) : nil
        case .int64(let v): return v >= 0 ? UInt64(v) : nil
        case .uint(let v): return UInt64(v)
        case .uint8(let v): return UInt64(v)
        case .uint16(let v): return UInt64(v)
        case .uint32(let v): return UInt64(v)
        case .uint64(let v): return v
        case .double(let v): return v >= 0 ? UInt64(v) : nil
        default: return nil
        }
    }
}

/// CodingKey for array indices in coding paths
private struct JSONValueIndexKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = Int(stringValue)
    }

    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "Index \(intValue)"
    }
}

private struct JSONValueKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey] { encoder.codingPath }
    let encoder: _JSONValueEncoder
    private var dict: [String: JSONValue] = [:]

    init(encoder: _JSONValueEncoder) {
        self.encoder = encoder
        encoder.value = .object([:])
    }
    
    mutating func encodeNil(forKey key: Key) throws {
        dict[key.stringValue] = .null
        encoder.value = .object(dict)
    }
    
    mutating func encode(_ value: Bool, forKey key: Key) throws {
        dict[key.stringValue] = .bool(value)
        encoder.value = .object(dict)
    }
    
    mutating func encode(_ value: String, forKey key: Key) throws {
        dict[key.stringValue] = .string(value)
        encoder.value = .object(dict)
    }
    
    mutating func encode(_ value: Double, forKey key: Key) throws {
        dict[key.stringValue] = .double(value)
        encoder.value = .object(dict)
    }
    
    mutating func encode(_ value: Float, forKey key: Key) throws {
        dict[key.stringValue] = .double(Double(value))
        encoder.value = .object(dict)
    }
    
    mutating func encode(_ value: Int, forKey key: Key) throws {
        dict[key.stringValue] = .int(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        dict[key.stringValue] = .int8(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        dict[key.stringValue] = .int16(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        dict[key.stringValue] = .int32(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        dict[key.stringValue] = .int64(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        dict[key.stringValue] = .uint(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        dict[key.stringValue] = .uint8(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        dict[key.stringValue] = .uint16(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        dict[key.stringValue] = .uint32(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        dict[key.stringValue] = .uint64(value)
        encoder.value = .object(dict)
    }

    mutating func encode(_ value: Decimal, forKey key: Key) throws {
        dict[key.stringValue] = .decimal(value)
        encoder.value = .object(dict)
    }

    mutating func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        if let date = value as? Date {
            dict[key.stringValue] = .string(JSONValueDateFormatter.string(from: date))
            encoder.value = .object(dict)
            return
        }
        let subEncoder = _JSONValueEncoder()
        subEncoder.codingPath = encoder.codingPath + [key]
        subEncoder.userInfo = encoder.userInfo
        try value.encode(to: subEncoder)
        dict[key.stringValue] = subEncoder.value ?? .null
        encoder.value = .object(dict)
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let nestedEncoder = _JSONValueEncoder()
        nestedEncoder.codingPath = encoder.codingPath + [key]
        nestedEncoder.userInfo = encoder.userInfo

        // Create a reference-capturing container that will update our dict when done
        let container = JSONValueKeyedEncodingContainer<NestedKey>(encoder: nestedEncoder)

        // Store a placeholder - the nested container will update nestedEncoder.value
        // We capture the nestedEncoder so we can extract its value later via the encoder reference
        dict[key.stringValue] = .object([:])
        encoder.value = .object(dict)

        return KeyedEncodingContainer(container)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let nestedEncoder = _JSONValueEncoder()
        nestedEncoder.codingPath = encoder.codingPath + [key]
        nestedEncoder.userInfo = encoder.userInfo

        // Similar to nestedContainer - the nested container will update nestedEncoder.value
        dict[key.stringValue] = .array([])
        encoder.value = .object(dict)

        return JSONValueUnkeyedEncodingContainer(encoder: nestedEncoder)
    }
    
    mutating func superEncoder() -> Encoder {
        _JSONValueEncoder()
    }
    
    mutating func superEncoder(forKey key: Key) -> Encoder {
        _JSONValueEncoder()
    }
}

private struct JSONValueUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey] { encoder.codingPath }
    var count: Int { array.count }
    let encoder: _JSONValueEncoder
    private var array: [JSONValue] = []
    
    init(encoder: _JSONValueEncoder) {
        self.encoder = encoder
        encoder.value = .array([])
    }
    
    mutating func encodeNil() throws {
        array.append(.null)
        encoder.value = .array(array)
    }
    
    mutating func encode(_ value: Bool) throws {
        array.append(.bool(value))
        encoder.value = .array(array)
    }
    
    mutating func encode(_ value: String) throws {
        array.append(.string(value))
        encoder.value = .array(array)
    }
    
    mutating func encode(_ value: Double) throws {
        array.append(.double(value))
        encoder.value = .array(array)
    }
    
    mutating func encode(_ value: Float) throws {
        array.append(.double(Double(value)))
        encoder.value = .array(array)
    }
    
    mutating func encode(_ value: Int) throws {
        array.append(.int(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: Int8) throws {
        array.append(.int8(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: Int16) throws {
        array.append(.int16(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: Int32) throws {
        array.append(.int32(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: Int64) throws {
        array.append(.int64(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: UInt) throws {
        array.append(.uint(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: UInt8) throws {
        array.append(.uint8(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: UInt16) throws {
        array.append(.uint16(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: UInt32) throws {
        array.append(.uint32(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: UInt64) throws {
        array.append(.uint64(value))
        encoder.value = .array(array)
    }

    mutating func encode(_ value: Decimal) throws {
        array.append(.decimal(value))
        encoder.value = .array(array)
    }

    mutating func encode<T>(_ value: T) throws where T: Encodable {
        if let date = value as? Date {
            array.append(.string(JSONValueDateFormatter.string(from: date)))
            encoder.value = .array(array)
            return
        }
        let subEncoder = _JSONValueEncoder()
        try value.encode(to: subEncoder)
        array.append(subEncoder.value ?? .null)
        encoder.value = .array(array)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let nestedEncoder = _JSONValueEncoder()
        let container = JSONValueKeyedEncodingContainer<NestedKey>(encoder: nestedEncoder)
        return KeyedEncodingContainer(container)
    }
    
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let nestedEncoder = _JSONValueEncoder()
        return JSONValueUnkeyedEncodingContainer(encoder: nestedEncoder)
    }
    
    mutating func superEncoder() -> Encoder {
        _JSONValueEncoder()
    }
}

private struct JSONValueSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey] { encoder.codingPath }
    let encoder: _JSONValueEncoder
    
    init(encoder: _JSONValueEncoder) {
        self.encoder = encoder
    }
    
    mutating func encodeNil() throws {
        encoder.value = .null
    }
    
    mutating func encode(_ value: Bool) throws {
        encoder.value = .bool(value)
    }
    
    mutating func encode(_ value: String) throws {
        encoder.value = .string(value)
    }
    
    mutating func encode(_ value: Double) throws {
        encoder.value = .double(value)
    }
    
    mutating func encode(_ value: Float) throws {
        encoder.value = .double(Double(value))
    }
    
    mutating func encode(_ value: Int) throws {
        encoder.value = .int(value)
    }

    mutating func encode(_ value: Int8) throws {
        encoder.value = .int8(value)
    }

    mutating func encode(_ value: Int16) throws {
        encoder.value = .int16(value)
    }

    mutating func encode(_ value: Int32) throws {
        encoder.value = .int32(value)
    }

    mutating func encode(_ value: Int64) throws {
        encoder.value = .int64(value)
    }

    mutating func encode(_ value: UInt) throws {
        encoder.value = .uint(value)
    }

    mutating func encode(_ value: UInt8) throws {
        encoder.value = .uint8(value)
    }

    mutating func encode(_ value: UInt16) throws {
        encoder.value = .uint16(value)
    }

    mutating func encode(_ value: UInt32) throws {
        encoder.value = .uint32(value)
    }

    mutating func encode(_ value: UInt64) throws {
        encoder.value = .uint64(value)
    }

    mutating func encode(_ value: Decimal) throws {
        encoder.value = .decimal(value)
    }

    mutating func encode<T>(_ value: T) throws where T: Encodable {
        if let date = value as? Date {
            encoder.value = .string(JSONValueDateFormatter.string(from: date))
            return
        }
        try value.encode(to: encoder)
    }
}

private struct JSONValueKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey] { decoder.codingPath }
    var allKeys: [Key] { dict.keys.compactMap { Key(stringValue: $0) } }
    let decoder: _JSONValueDecoder
    let dict: [String: JSONValue]
    
    init(decoder: _JSONValueDecoder, dict: [String: JSONValue]) {
        self.decoder = decoder
        self.dict = dict
    }
    
    func contains(_ key: Key) -> Bool {
        dict[key.stringValue] != nil
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = dict[key.stringValue] else { return true }
        return value == .null
    }
    
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'. Available keys: \(dict.keys.sorted().joined(separator: ", "))"
                )
            )
        }
        guard case .bool(let bool) = value else {
            throw DecodingError.typeMismatch(
                Bool.self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected Bool for key '\(key.stringValue)' but found \(value.typeDescription)"
                )
            )
        }
        return bool
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'. Available keys: \(dict.keys.sorted().joined(separator: ", "))"
                )
            )
        }
        guard case .string(let string) = value else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected String for key '\(key.stringValue)' but found \(value.typeDescription)"
                )
            )
        }
        return string
    }
    
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        switch value {
        case .double(let double): return double
        case .int(let int): return Double(int)
        default:
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected Double for key '\(key.stringValue)' but found \(value.typeDescription)"
                )
            )
        }
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        return Float(try decode(Double.self, forKey: key))
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let int64 = value.asInt64(), let result = Int(exactly: int64) {
            return result
        }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected Int for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let int64 = value.asInt64(), let result = Int8(exactly: int64) {
            return result
        }
        throw DecodingError.typeMismatch(
            Int8.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected Int8 for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let int64 = value.asInt64(), let result = Int16(exactly: int64) {
            return result
        }
        throw DecodingError.typeMismatch(
            Int16.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected Int16 for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let int64 = value.asInt64(), let result = Int32(exactly: int64) {
            return result
        }
        throw DecodingError.typeMismatch(
            Int32.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected Int32 for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let int64 = value.asInt64() {
            return int64
        }
        throw DecodingError.typeMismatch(
            Int64.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected Int64 for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let uint64 = value.asUInt64(), let result = UInt(exactly: uint64) {
            return result
        }
        throw DecodingError.typeMismatch(
            UInt.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected UInt for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let uint64 = value.asUInt64(), let result = UInt8(exactly: uint64) {
            return result
        }
        throw DecodingError.typeMismatch(
            UInt8.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected UInt8 for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let uint64 = value.asUInt64(), let result = UInt16(exactly: uint64) {
            return result
        }
        throw DecodingError.typeMismatch(
            UInt16.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected UInt16 for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let uint64 = value.asUInt64(), let result = UInt32(exactly: uint64) {
            return result
        }
        throw DecodingError.typeMismatch(
            UInt32.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected UInt32 for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        if let uint64 = value.asUInt64() {
            return uint64
        }
        throw DecodingError.typeMismatch(
            UInt64.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected UInt64 for key '\(key.stringValue)' but found \(value.typeDescription)"
            )
        )
    }

    func decode(_ type: Decimal.Type, forKey key: Key) throws -> Decimal {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        switch value {
        case .decimal(let decimal): return decimal
        case .int(let int): return Decimal(int)
        case .int8(let int8): return Decimal(Int(int8))
        case .int16(let int16): return Decimal(Int(int16))
        case .int32(let int32): return Decimal(Int(int32))
        case .int64(let int64): return Decimal(int64)
        case .uint(let uint): return Decimal(uint)
        case .uint8(let uint8): return Decimal(UInt(uint8))
        case .uint16(let uint16): return Decimal(UInt(uint16))
        case .uint32(let uint32): return Decimal(UInt(uint32))
        case .uint64(let uint64): return Decimal(uint64)
        case .double(let double): return Decimal(double)
        case .string(let string):
            if let decimal = Decimal(string: string) {
                return decimal
            }
            fallthrough
        default:
            throw DecodingError.typeMismatch(
                Decimal.self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected Decimal for key '\(key.stringValue)' but found \(value.typeDescription)"
                )
            )
        }
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        // Date is handled here too — `Foundation.Date` round-trips as an
        // ISO 8601 string in tool wire format. Numeric values are rejected
        // explicitly so we don't silently accept Foundation's default
        // reference-date encoding.
        if T.self == Date.self {
            guard case .string(let str) = value else {
                throw DecodingError.typeMismatch(Date.self, .init(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected ISO 8601 date-time string for Date, got \(value)"
                ))
            }
            guard let date = JSONValueDateFormatter.date(from: str) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath + [key],
                    debugDescription: "Could not parse '\(str)' as ISO 8601 date-time"
                ))
            }
            return date as! T
        }
        let subDecoder = _JSONValueDecoder(value: value, codingPath: decoder.codingPath + [key])
        subDecoder.userInfo = decoder.userInfo
        return try T(from: subDecoder)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        guard case .object(let nestedDict) = value else {
            throw DecodingError.typeMismatch(
                [String: JSONValue].self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected object for key '\(key.stringValue)' but found \(value.typeDescription)"
                )
            )
        }
        let nestedDecoder = _JSONValueDecoder(value: value, codingPath: decoder.codingPath + [key])
        nestedDecoder.userInfo = decoder.userInfo
        let container = JSONValueKeyedDecodingContainer<NestedKey>(decoder: nestedDecoder, dict: nestedDict)
        return KeyedDecodingContainer(container)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        guard let value = dict[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "No value associated with key '\(key.stringValue)'"
                )
            )
        }
        guard case .array(let array) = value else {
            throw DecodingError.typeMismatch(
                [JSONValue].self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Expected array for key '\(key.stringValue)' but found \(value.typeDescription)"
                )
            )
        }
        let nestedDecoder = _JSONValueDecoder(value: value, codingPath: decoder.codingPath + [key])
        nestedDecoder.userInfo = decoder.userInfo
        return JSONValueUnkeyedDecodingContainer(decoder: nestedDecoder, array: array)
    }
    
    func superDecoder() throws -> Decoder {
        _JSONValueDecoder(value: .null)
    }
    
    func superDecoder(forKey key: Key) throws -> Decoder {
        let value = dict[key.stringValue] ?? .null
        return _JSONValueDecoder(value: value)
    }
}

private struct JSONValueUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    var codingPath: [CodingKey] { decoder.codingPath }
    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }
    var currentIndex: Int = 0
    let decoder: _JSONValueDecoder
    let array: [JSONValue]
    
    init(decoder: _JSONValueDecoder, array: [JSONValue]) {
        self.decoder = decoder
        self.array = array
    }
    
    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return true }
        let value = array[currentIndex]
        if value == .null {
            currentIndex += 1
            return true
        }
        return false
    }
    
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        guard !isAtEnd, case .bool(let bool) = array[currentIndex] else {
            throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected bool"))
        }
        currentIndex += 1
        return bool
    }
    
    mutating func decode(_ type: String.Type) throws -> String {
        guard !isAtEnd, case .string(let string) = array[currentIndex] else {
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected string"))
        }
        currentIndex += 1
        return string
    }
    
    mutating func decode(_ type: Double.Type) throws -> Double {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Unexpected end of array"))
        }
        let value = array[currentIndex]
        currentIndex += 1
        switch value {
        case .double(let double): return double
        case .int(let int): return Double(int)
        default: throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected number"))
        }
    }
    
    mutating func decode(_ type: Float.Type) throws -> Float {
        return Float(try decode(Double.self))
    }
    
    mutating func decode(_ type: Int.Type) throws -> Int {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Unexpected end of array"))
        }
        let value = array[currentIndex]
        currentIndex += 1
        switch value {
        case .int(let int): return int
        case .double(let double): return Int(double)
        default: throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected number"))
        }
    }

    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        guard !isAtEnd, case .int8(let int8) = array[currentIndex] else {
            throw DecodingError.typeMismatch(Int8.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int8"))
        }
        currentIndex += 1
        return int8
    }

    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        guard !isAtEnd, case .int16(let int16) = array[currentIndex] else {
            throw DecodingError.typeMismatch(Int16.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int16"))
        }
        currentIndex += 1
        return int16
    }

    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        guard !isAtEnd, case .int32(let int32) = array[currentIndex] else {
            throw DecodingError.typeMismatch(Int32.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int32"))
        }
        currentIndex += 1
        return int32
    }

    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        guard !isAtEnd, case .int64(let int64) = array[currentIndex] else {
            throw DecodingError.typeMismatch(Int64.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int64"))
        }
        currentIndex += 1
        return int64
    }

    mutating func decode(_ type: UInt.Type) throws -> UInt {
        guard !isAtEnd, case .uint(let uint) = array[currentIndex] else {
            throw DecodingError.typeMismatch(UInt.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt"))
        }
        currentIndex += 1
        return uint
    }

    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        guard !isAtEnd, case .uint8(let uint8) = array[currentIndex] else {
            throw DecodingError.typeMismatch(UInt8.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt8"))
        }
        currentIndex += 1
        return uint8
    }

    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        guard !isAtEnd, case .uint16(let uint16) = array[currentIndex] else {
            throw DecodingError.typeMismatch(UInt16.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt16"))
        }
        currentIndex += 1
        return uint16
    }

    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        guard !isAtEnd, case .uint32(let uint32) = array[currentIndex] else {
            throw DecodingError.typeMismatch(UInt32.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt32"))
        }
        currentIndex += 1
        return uint32
    }

    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        guard !isAtEnd, case .uint64(let uint64) = array[currentIndex] else {
            throw DecodingError.typeMismatch(UInt64.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt64"))
        }
        currentIndex += 1
        return uint64
    }

    mutating func decode(_ type: Decimal.Type) throws -> Decimal {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Decimal.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Unexpected end of array"))
        }
        let value = array[currentIndex]
        currentIndex += 1
        switch value {
        case .decimal(let decimal): return decimal
        case .int(let int): return Decimal(int)
        case .int8(let int8): return Decimal(Int(int8))
        case .int16(let int16): return Decimal(Int(int16))
        case .int32(let int32): return Decimal(Int(int32))
        case .int64(let int64): return Decimal(int64)
        case .uint(let uint): return Decimal(uint)
        case .uint8(let uint8): return Decimal(UInt(uint8))
        case .uint16(let uint16): return Decimal(UInt(uint16))
        case .uint32(let uint32): return Decimal(UInt(uint32))
        case .uint64(let uint64): return Decimal(uint64)
        case .double(let double): return Decimal(double)
        default: throw DecodingError.typeMismatch(Decimal.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Decimal"))
        }
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                T.self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unexpected end of array at index \(currentIndex)"
                )
            )
        }
        let value = array[currentIndex]
        if T.self == Date.self {
            guard case .string(let str) = value else {
                throw DecodingError.typeMismatch(Date.self, .init(
                    codingPath: codingPath,
                    debugDescription: "Expected ISO 8601 date-time string for Date, got \(value)"
                ))
            }
            guard let date = JSONValueDateFormatter.date(from: str) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath,
                    debugDescription: "Could not parse '\(str)' as ISO 8601 date-time"
                ))
            }
            currentIndex += 1
            return date as! T
        }
        let indexKey = JSONValueIndexKey(intValue: currentIndex)!
        let subDecoder = _JSONValueDecoder(value: value, codingPath: decoder.codingPath + [indexKey])
        subDecoder.userInfo = decoder.userInfo
        currentIndex += 1
        return try T(from: subDecoder)
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                [String: JSONValue].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unexpected end of array at index \(currentIndex)"
                )
            )
        }
        guard case .object(let dict) = array[currentIndex] else {
            throw DecodingError.typeMismatch(
                [String: JSONValue].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected object at index \(currentIndex) but found \(array[currentIndex].typeDescription)"
                )
            )
        }
        let value = array[currentIndex]
        let indexKey = JSONValueIndexKey(intValue: currentIndex)!
        let nestedDecoder = _JSONValueDecoder(value: value, codingPath: decoder.codingPath + [indexKey])
        nestedDecoder.userInfo = decoder.userInfo
        currentIndex += 1
        let container = JSONValueKeyedDecodingContainer<NestedKey>(decoder: nestedDecoder, dict: dict)
        return KeyedDecodingContainer(container)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                [JSONValue].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unexpected end of array at index \(currentIndex)"
                )
            )
        }
        guard case .array(let nestedArray) = array[currentIndex] else {
            throw DecodingError.typeMismatch(
                [JSONValue].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected array at index \(currentIndex) but found \(array[currentIndex].typeDescription)"
                )
            )
        }
        let value = array[currentIndex]
        let indexKey = JSONValueIndexKey(intValue: currentIndex)!
        let nestedDecoder = _JSONValueDecoder(value: value, codingPath: decoder.codingPath + [indexKey])
        nestedDecoder.userInfo = decoder.userInfo
        currentIndex += 1
        return JSONValueUnkeyedDecodingContainer(decoder: nestedDecoder, array: nestedArray)
    }
    
    mutating func superDecoder() throws -> Decoder {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Decoder.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Unexpected end of array"))
        }
        let value = array[currentIndex]
        currentIndex += 1
        return _JSONValueDecoder(value: value)
    }
}

private struct JSONValueSingleValueDecodingContainer: SingleValueDecodingContainer {
    var codingPath: [CodingKey] { decoder.codingPath }
    let decoder: _JSONValueDecoder
    let value: JSONValue
    
    init(decoder: _JSONValueDecoder, value: JSONValue) {
        self.decoder = decoder
        self.value = value
    }
    
    func decodeNil() -> Bool {
        value == .null
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .bool(let bool) = value else {
            throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Bool but found \(value.typeDescription)"))
        }
        return bool
    }
    
    func decode(_ type: String.Type) throws -> String {
        guard case .string(let string) = value else {
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected String but found \(value.typeDescription)"))
        }
        return string
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        switch value {
        case .double(let double): return double
        case .int(let int): return Double(int)
        default: throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Double but found \(value.typeDescription)"))
        }
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        return Float(try decode(Double.self))
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        switch value {
        case .int(let int): return int
        case .double(let double): return Int(double)
        default: throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int but found \(value.typeDescription)"))
        }
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        guard case .int8(let int8) = value else {
            throw DecodingError.typeMismatch(Int8.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int8 but found \(value.typeDescription)"))
        }
        return int8
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        guard case .int16(let int16) = value else {
            throw DecodingError.typeMismatch(Int16.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int16 but found \(value.typeDescription)"))
        }
        return int16
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        guard case .int32(let int32) = value else {
            throw DecodingError.typeMismatch(Int32.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int32 but found \(value.typeDescription)"))
        }
        return int32
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        guard case .int64(let int64) = value else {
            throw DecodingError.typeMismatch(Int64.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Int64 but found \(value.typeDescription)"))
        }
        return int64
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        guard case .uint(let uint) = value else {
            throw DecodingError.typeMismatch(UInt.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt but found \(value.typeDescription)"))
        }
        return uint
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        guard case .uint8(let uint8) = value else {
            throw DecodingError.typeMismatch(UInt8.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt8 but found \(value.typeDescription)"))
        }
        return uint8
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        guard case .uint16(let uint16) = value else {
            throw DecodingError.typeMismatch(UInt16.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt16 but found \(value.typeDescription)"))
        }
        return uint16
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        guard case .uint32(let uint32) = value else {
            throw DecodingError.typeMismatch(UInt32.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt32 but found \(value.typeDescription)"))
        }
        return uint32
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        guard case .uint64(let uint64) = value else {
            throw DecodingError.typeMismatch(UInt64.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected UInt64 but found \(value.typeDescription)"))
        }
        return uint64
    }

    func decode(_ type: Decimal.Type) throws -> Decimal {
        switch value {
        case .decimal(let decimal): return decimal
        case .int(let int): return Decimal(int)
        case .int8(let int8): return Decimal(Int(int8))
        case .int16(let int16): return Decimal(Int(int16))
        case .int32(let int32): return Decimal(Int(int32))
        case .int64(let int64): return Decimal(int64)
        case .uint(let uint): return Decimal(uint)
        case .uint8(let uint8): return Decimal(UInt(uint8))
        case .uint16(let uint16): return Decimal(UInt(uint16))
        case .uint32(let uint32): return Decimal(UInt(uint32))
        case .uint64(let uint64): return Decimal(uint64)
        case .double(let double): return Decimal(double)
        default: throw DecodingError.typeMismatch(Decimal.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected Decimal but found \(value.typeDescription)"))
        }
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        if T.self == Date.self {
            guard case .string(let str) = value else {
                throw DecodingError.typeMismatch(Date.self, .init(
                    codingPath: codingPath,
                    debugDescription: "Expected ISO 8601 date-time string for Date, got \(value)"
                ))
            }
            guard let date = JSONValueDateFormatter.date(from: str) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath,
                    debugDescription: "Could not parse '\(str)' as ISO 8601 date-time"
                ))
            }
            return date as! T
        }
        return try T(from: decoder)
    }
}
