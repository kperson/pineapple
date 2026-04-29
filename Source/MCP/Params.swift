import Foundation
import JSONValueCoding

// MARK: - Parameters Container

/// Container for parameters from multiple sources (URL paths, resource URIs, and prompt arguments)
///
/// Params provides named access to parameters extracted from:
/// - **URL paths**: Router path parameters like `/files/{customerId}`
/// - **Resource URIs**: Resource template parameters like `file://{tenant}/docs/{docId}`
/// - **Prompt arguments**: MCP prompt arguments passed as JSON objects
///
/// ## Usage Examples
///
/// ### With Router Paths
/// ```swift
/// // Route: "/files/{customerId}"
/// // URL:   "/files/cust-123"
/// let params = pathPattern.match("/files/cust-123")
/// params?.string("customerId")  // → "cust-123"
/// ```
///
/// ### With Resource URIs
/// ```swift
/// // Pattern: "file://{tenant}/docs/{docId}"
/// // URI:     "file://acme-corp/docs/readme.md"
/// let params = resourcePattern.match("file://acme-corp/docs/readme.md")
/// params?.string("tenant")  // → "acme-corp"
/// params?.string("docId")   // → "readme.md"
/// ```
///
/// ### With Prompt Arguments
/// ```swift
/// // MCP prompts/get request with arguments: { "code": "let x = 1", "language": "swift" }
/// .addPrompt("review") { request in
///     let code = request.arguments.string("code") ?? ""
///     let language = request.arguments.string("language") ?? "unknown"
///     return PromptHandlerResponse(messages: [...])
/// }
/// ```
///
/// ## Type Conversion
///
/// Params provides typed accessors that convert string values:
/// - `string(_:)` - Returns raw string value
/// - `int(_:)` - Converts to Int (platform-dependent size)
/// - **Signed integers**: `int8(_:)`, `int16(_:)`, `int32(_:)`, `int64(_:)`
/// - **Unsigned integers**: `uint(_:)`, `uint8(_:)`, `uint16(_:)`, `uint32(_:)`, `uint64(_:)`
/// - `uuid(_:)` - Parses as UUID
/// - `bool(_:)` - Converts to Bool
/// - `double(_:)` - Converts to Double
///
/// All accessors return optional values (`nil` if parameter not found or conversion fails).
///
/// ### Integer Type Selection
///
/// Choose the appropriate integer type based on your value range:
/// - **Int8**: -128 to 127 (e.g., priority levels, small counts)
/// - **Int16**: -32,768 to 32,767 (e.g., port numbers, years)
/// - **Int32**: ±2.1 billion (e.g., counts, IDs)
/// - **Int64**: ±9.2 quintillion (e.g., timestamps, large counts)
/// - **UInt8**: 0 to 255 (e.g., percentages, byte values)
/// - **UInt16**: 0 to 65,535 (e.g., network ports)
/// - **UInt32**: 0 to 4.3 billion (e.g., unsigned IDs)
/// - **UInt64**: 0 to 18.4 quintillion (e.g., file sizes, large unsigned values)
///
/// ## Multi-Tenant Applications
///
/// Params enables multi-tenant architectures where the same MCP server handles
/// requests for different customers/tenants based on URL path parameters:
///
/// ```swift
/// // Router: "/mcp/{customerId}/tools"
/// let customerId = pathParams.string("customerId")
/// let customerDB = Database.connect(tenant: customerId)
/// ```
public struct Params: Sendable {
    private let values: [String: String]

    /// Initialize with extracted parameter values
    /// - Parameter values: Dictionary mapping parameter names to their string values
    public init(_ values: [String: String]) {
        self.values = values
    }

    /// Initialize from a JSONValue (for prompt arguments)
    /// - Parameter jsonValue: JSONValue containing an object with flat key-value pairs
    /// - Throws: MCPError if jsonValue is not an object
    ///
    /// Converts JSONValue primitives to strings:
    /// - `.string(s)` → `s`
    /// - `.int(i)` → `String(i)`
    /// - `.bool(b)` → `String(b)`
    /// - `.double(d)` → `String(d)`
    /// - Arrays and nested objects are ignored (flat parameters only)
    ///
    /// Example:
    /// ```swift
    /// // JSONValue: { "code": "let x = 1", "lineCount": 10, "strict": true }
    /// let params = try Params(jsonValue)
    /// params.string("code")      // → "let x = 1"
    /// params.int("lineCount")    // → 10
    /// params.bool("strict")      // → true
    /// ```
    public init(_ jsonValue: JSONValue) throws {
        guard case .object(let dict) = jsonValue else {
            throw MCPError(code: .invalidParams, message: "Expected object for parameters")
        }

        var stringValues: [String: String] = [:]
        for (key, value) in dict {
            switch value {
            case .string(let s):
                stringValues[key] = s
            case .int(let i):
                stringValues[key] = String(i)
            case .int8(let i):
                stringValues[key] = String(i)
            case .int16(let i):
                stringValues[key] = String(i)
            case .int32(let i):
                stringValues[key] = String(i)
            case .int64(let i):
                stringValues[key] = String(i)
            case .uint(let u):
                stringValues[key] = String(u)
            case .uint8(let u):
                stringValues[key] = String(u)
            case .uint16(let u):
                stringValues[key] = String(u)
            case .uint32(let u):
                stringValues[key] = String(u)
            case .uint64(let u):
                stringValues[key] = String(u)
            case .bool(let b):
                stringValues[key] = String(b)
            case .double(let d):
                stringValues[key] = String(d)
            case .decimal(let d):
                stringValues[key] = String(describing: d)
            case .null:
                // Skip null values
                continue
            case .array, .object:
                // Skip arrays and nested objects (flat parameters only)
                continue
            }
        }
        self.values = stringValues
    }

    /// Access a string parameter by name using subscript syntax
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: String value or nil if not found
    ///
    /// Example:
    /// ```swift
    /// let customerId = pathParams["customerId"]
    /// ```
    public subscript(key: String) -> String? {
        return values[key]
    }

    /// Get a string parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: String value or nil if not found
    ///
    /// Example:
    /// ```swift
    /// let userId = pathParams.string("userId")
    /// ```
    public func string(_ key: String) -> String? {
        return values[key]
    }

    /// Get an integer parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: Integer value or nil if not found or not convertible to Int
    ///
    /// Example:
    /// ```swift
    /// let page = pathParams.int("page") ?? 1
    /// ```
    public func int(_ key: String) -> Int? {
        guard let stringValue = values[key] else { return nil }
        return Int(stringValue)
    }

    // MARK: - Signed Integer Accessors

    /// Get an Int8 parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: Int8 value or nil if not found or not convertible to Int8
    ///
    /// Example:
    /// ```swift
    /// let priority = pathParams.int8("priority")  // Range: -128 to 127
    /// ```
    public func int8(_ key: String) -> Int8? {
        guard let stringValue = values[key] else { return nil }
        return Int8(stringValue)
    }

    /// Get an Int16 parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: Int16 value or nil if not found or not convertible to Int16
    ///
    /// Example:
    /// ```swift
    /// let port = pathParams.int16("port")  // Range: -32,768 to 32,767
    /// ```
    public func int16(_ key: String) -> Int16? {
        guard let stringValue = values[key] else { return nil }
        return Int16(stringValue)
    }

    /// Get an Int32 parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: Int32 value or nil if not found or not convertible to Int32
    ///
    /// Example:
    /// ```swift
    /// let count = pathParams.int32("count")  // Range: -2,147,483,648 to 2,147,483,647
    /// ```
    public func int32(_ key: String) -> Int32? {
        guard let stringValue = values[key] else { return nil }
        return Int32(stringValue)
    }

    /// Get an Int64 parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: Int64 value or nil if not found or not convertible to Int64
    ///
    /// Example:
    /// ```swift
    /// let timestamp = pathParams.int64("timestamp")
    /// ```
    public func int64(_ key: String) -> Int64? {
        guard let stringValue = values[key] else { return nil }
        return Int64(stringValue)
    }

    // MARK: - Unsigned Integer Accessors

    /// Get a UInt parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: UInt value or nil if not found or not convertible to UInt
    ///
    /// Example:
    /// ```swift
    /// let count = pathParams.uint("count")
    /// ```
    public func uint(_ key: String) -> UInt? {
        guard let stringValue = values[key] else { return nil }
        return UInt(stringValue)
    }

    /// Get a UInt8 parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: UInt8 value or nil if not found or not convertible to UInt8
    ///
    /// Example:
    /// ```swift
    /// let age = pathParams.uint8("age")  // Range: 0 to 255
    /// ```
    public func uint8(_ key: String) -> UInt8? {
        guard let stringValue = values[key] else { return nil }
        return UInt8(stringValue)
    }

    /// Get a UInt16 parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: UInt16 value or nil if not found or not convertible to UInt16
    ///
    /// Example:
    /// ```swift
    /// let port = pathParams.uint16("port")  // Range: 0 to 65,535
    /// ```
    public func uint16(_ key: String) -> UInt16? {
        guard let stringValue = values[key] else { return nil }
        return UInt16(stringValue)
    }

    /// Get a UInt32 parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: UInt32 value or nil if not found or not convertible to UInt32
    ///
    /// Example:
    /// ```swift
    /// let id = pathParams.uint32("id")  // Range: 0 to 4,294,967,295
    /// ```
    public func uint32(_ key: String) -> UInt32? {
        guard let stringValue = values[key] else { return nil }
        return UInt32(stringValue)
    }

    /// Get a UInt64 parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: UInt64 value or nil if not found or not convertible to UInt64
    ///
    /// Example:
    /// ```swift
    /// let fileSize = pathParams.uint64("bytes")  // Range: 0 to 18,446,744,073,709,551,615
    /// ```
    public func uint64(_ key: String) -> UInt64? {
        guard let stringValue = values[key] else { return nil }
        return UInt64(stringValue)
    }

    // MARK: - Other Type Accessors

    /// Get a UUID parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: UUID value or nil if not found or not a valid UUID string
    ///
    /// Example:
    /// ```swift
    /// if let requestId = pathParams.uuid("requestId") {
    ///     // Use UUID
    /// }
    /// ```
    public func uuid(_ key: String) -> UUID? {
        guard let stringValue = values[key] else { return nil }
        return UUID(uuidString: stringValue)
    }

    /// Get a boolean parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: Boolean value or nil if not found or not convertible to Bool
    ///
    /// Supports the following formats (case-insensitive):
    /// - "true" / "TRUE" / "True" → true
    /// - "false" / "FALSE" / "False" → false
    /// - "1" → true
    /// - "0" → false
    ///
    /// Example:
    /// ```swift
    /// let isEnabled = pathParams.bool("enabled") ?? false
    /// ```
    public func bool(_ key: String) -> Bool? {
        guard let stringValue = values[key] else { return nil }
        
        // Check for numeric representations
        switch stringValue {
        case "1":
            return true
        case "0":
            return false
        default:
            break
        }
        
        // Check for case-insensitive "true" and "false"
        let lowercased = stringValue.lowercased()
        switch lowercased {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    /// Get a double parameter by name
    ///
    /// - Parameter key: Parameter name from the path/URI definition
    /// - Returns: Double value or nil if not found or not convertible to Double
    ///
    /// Example:
    /// ```swift
    /// let latitude = pathParams.double("lat")
    /// let longitude = pathParams.double("lng")
    /// ```
    public func double(_ key: String) -> Double? {
        guard let stringValue = values[key] else { return nil }
        return Double(stringValue)
    }
}
