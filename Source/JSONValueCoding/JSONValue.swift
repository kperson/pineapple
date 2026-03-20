import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    
    case null
    case bool(Bool)
    case int(Int)
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case uint(UInt)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case double(Double)
    case decimal(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
    
    public init(_ dict: [String: Any]) {
        var jsonDict: [String: JSONValue] = [:]
        for (key, value) in dict {
            if let jsonValue = value as? JSONValue {
                jsonDict[key] = jsonValue
            } else if let string = value as? String {
                jsonDict[key] = .string(string)
            } else if let int = value as? Int {
                jsonDict[key] = .int(int)
            } else if let double = value as? Double {
                jsonDict[key] = .double(double)
            } else if let bool = value as? Bool {
                jsonDict[key] = .bool(bool)
            } else if let array = value as? [String] {
                jsonDict[key] = .array(array.map { .string($0) })
            } else if let nestedDict = value as? [String: Any] {
                jsonDict[key] = JSONValue(nestedDict)
            } else {
                jsonDict[key] = .null
            }
        }
        self = .object(jsonDict)
    }
    
    /// Adds a "description" key to an object-type JSONValue.
    /// Used by the @JSONSchema macro to attach descriptions to nested type references.
    public static func withDescription(_ schema: JSONValue, _ description: String) -> JSONValue {
        guard case .object(var dict) = schema else { return schema }
        dict["description"] = .string(description)
        return .object(dict)
    }

    // MARK: - Accessor Properties
    
    /// Returns true if this value is null
    public var isNull: Bool {
        if case .null = self {
            return true
        } else {
            return false
        }
    }
    
    /// Returns the bool value if this is a bool, nil otherwise
    public var bool: Bool? {
        if case .bool(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the int value if this is an int, nil otherwise
    public var int: Int? {
        if case .int(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the int8 value if this is an int8, nil otherwise
    public var int8: Int8? {
        if case .int8(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the int16 value if this is an int16, nil otherwise
    public var int16: Int16? {
        if case .int16(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the int32 value if this is an int32, nil otherwise
    public var int32: Int32? {
        if case .int32(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the int64 value if this is an int64, nil otherwise
    public var int64: Int64? {
        if case .int64(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the uint value if this is a uint, nil otherwise
    public var uint: UInt? {
        if case .uint(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the uint8 value if this is a uint8, nil otherwise
    public var uint8: UInt8? {
        if case .uint8(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the uint16 value if this is a uint16, nil otherwise
    public var uint16: UInt16? {
        if case .uint16(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the uint32 value if this is a uint32, nil otherwise
    public var uint32: UInt32? {
        if case .uint32(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the uint64 value if this is a uint64, nil otherwise
    public var uint64: UInt64? {
        if case .uint64(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the double value if this is a double, nil otherwise
    public var double: Double? {
        if case .double(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the decimal value if this is a decimal, nil otherwise
    public var decimal: Decimal? {
        if case .decimal(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the string value if this is a string, nil otherwise
    public var string: String? {
        if case .string(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the array value if this is an array, nil otherwise
    public var array: [JSONValue]? {
        if case .array(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    /// Returns the object value if this is an object, nil otherwise
    public var object: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        } else {
            return nil
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let int8 = try? container.decode(Int8.self) {
            self = .int8(int8)
        } else if let int16 = try? container.decode(Int16.self) {
            self = .int16(int16)
        } else if let int32 = try? container.decode(Int32.self) {
            self = .int32(int32)
        } else if let int64 = try? container.decode(Int64.self) {
            self = .int64(int64)
        } else if let uint = try? container.decode(UInt.self) {
            self = .uint(uint)
        } else if let uint8 = try? container.decode(UInt8.self) {
            self = .uint8(uint8)
        } else if let uint16 = try? container.decode(UInt16.self) {
            self = .uint16(uint16)
        } else if let uint32 = try? container.decode(UInt32.self) {
            self = .uint32(uint32)
        } else if let uint64 = try? container.decode(UInt64.self) {
            self = .uint64(uint64)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let decimal = try? container.decode(Decimal.self) {
            self = .decimal(decimal)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid JSON value"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int8(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int16(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int32(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int64(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .uint(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .uint8(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .uint16(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .uint32(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .uint64(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .decimal(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let value):
            var container = encoder.container(keyedBy: DynamicJSONKey.self)
            for (key, jsonValue) in value {
                let codingKey = DynamicJSONKey(stringValue: key)!
                try container.encode(jsonValue, forKey: codingKey)
            }
        }
    }
}

private struct DynamicJSONKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
