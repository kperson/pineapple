import Foundation

// MARK: - Path Pattern Matching

/// URL path pattern matcher with parameter extraction
///
/// `PathPattern` provides compile-time pattern matching for URL paths, extracting named parameters
/// from dynamic path segments. It's designed for routing HTTP requests in the MCP framework.
///
/// ## Pattern Syntax
///
/// Patterns consist of literal segments and parameter placeholders:
/// - **Literal segments**: Match exactly (e.g., `users`, `api`, `v1`)
/// - **Parameter placeholders**: `{paramName}` matches any value and extracts it
///
/// ## Examples
///
/// ```swift
/// // Simple literal path
/// let pattern = PathPattern("/api/users")
/// pattern.match("/api/users")  // → Params (empty)
/// pattern.match("/api/posts")  // → nil
///
/// // Single parameter
/// let pattern = PathPattern("/users/{id}")
/// let params = pattern.match("/users/123")
/// params?.string("id")  // → "123"
///
/// // Multiple parameters
/// let pattern = PathPattern("/users/{userId}/posts/{postId}")
/// let params = pattern.match("/users/alice/posts/hello-world")
/// params?.string("userId")  // → "alice"
/// params?.string("postId")  // → "hello-world"
///
/// // Mixed literals and parameters
/// let pattern = PathPattern("/{tenant}/api/v1/{resource}")
/// let params = pattern.match("/acme-corp/api/v1/users")
/// params?.string("tenant")    // → "acme-corp"
/// params?.string("resource")  // → "users"
/// ```
struct PathPattern {
    /// Parsed path segments (literals and parameters)
    private let segments: [PathSegment]
    
    /// Creates a path pattern from a URL path template
    ///
    /// The pattern is parsed immediately and segments are cached for efficient matching.
    ///
    /// - Parameter pattern: URL path pattern with optional `{paramName}` placeholders
    ///
    /// ## Examples
    ///
    /// ```swift
    /// PathPattern("/users")                    // Literal path
    /// PathPattern("/users/{id}")               // Single parameter
    /// PathPattern("/users/{id}/posts/{postId}") // Multiple parameters
    /// PathPattern("/{tenant}/api/{resource}")  // Multi-tenant pattern
    /// ```
    ///
    /// ## Pattern Normalization
    ///
    /// - Leading/trailing slashes are removed
    /// - Multiple consecutive slashes are collapsed
    /// - Empty segments are ignored
    ///
    /// All of these create identical patterns:
    /// ```swift
    /// PathPattern("users/{id}")
    /// PathPattern("/users/{id}")
    /// PathPattern("//users//{id}//")
    /// ```
    init(_ pattern: String) {
        // Remove leading/trailing slashes and split into segments
        let cleanPattern = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if cleanPattern.isEmpty {
            self.segments = []
        } else {
            self.segments = cleanPattern.split(separator: "/").map { segment in
                let segmentString = String(segment)
                if segmentString.hasPrefix("{") && segmentString.hasSuffix("}") {
                    let paramName = String(segmentString.dropFirst().dropLast())
                    return .parameter(paramName)
                } else {
                    return .literal(segmentString)
                }
            }
        }
    }
    
    /// Attempts to match a URL path against this pattern
    ///
    /// If the path matches the pattern, returns a `Params` object containing extracted
    /// parameter values. If the path doesn't match, returns `nil`.
    ///
    /// - Parameter urlPath: The URL path to match
    /// - Returns: Extracted parameters if matched, or `nil` if no match
    ///
    /// ## Matching Rules
    ///
    /// 1. Path and pattern must have the same number of segments
    /// 2. Literal segments must match exactly (case-sensitive)
    /// 3. Parameter segments match any value and extract it
    ///
    /// ## Examples
    ///
    /// ```swift
    /// let pattern = PathPattern("/users/{id}/posts/{postId}")
    ///
    /// // Matches
    /// let params = pattern.match("/users/123/posts/456")
    /// params?.string("id")      // → "123"
    /// params?.string("postId")  // → "456"
    ///
    /// // No match - wrong literal segment
    /// pattern.match("/admin/123/posts/456")  // → nil
    ///
    /// // No match - wrong segment count
    /// pattern.match("/users/123")            // → nil
    /// pattern.match("/users/123/posts/456/extra")  // → nil
    /// ```
    ///
    /// ## Path Normalization
    ///
    /// Paths are normalized before matching:
    /// ```swift
    /// let pattern = PathPattern("/users/{id}")
    ///
    /// // All of these match
    /// pattern.match("/users/123")   // → id: "123"
    /// pattern.match("users/123")    // → id: "123"
    /// pattern.match("//users/123/") // → id: "123"
    /// ```
    func match(_ urlPath: String) -> Params? {
        // Remove leading/trailing slashes and split into components
        let cleanPath = urlPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathComponents: [String]
        
        if cleanPath.isEmpty {
            pathComponents = []
        } else {
            pathComponents = cleanPath.split(separator: "/").map(String.init)
        }
        
        // Must have same number of segments
        guard pathComponents.count == segments.count else { return nil }
        
        var extractedValues: [String: String] = [:]

        for (component, segment) in zip(pathComponents, segments) {
            switch segment {
            case .literal(let expected):
                guard component == expected else { return nil }
            case .parameter(let key):
                extractedValues[key] = component
            }
        }

        return Params(extractedValues)
    }
}

// MARK: - Equatable

extension PathPattern: Equatable {
    /// Two patterns are equal if they have the same segments
    ///
    /// This allows pattern comparison for testing and deduplication:
    /// ```swift
    /// PathPattern("/users/{id}") == PathPattern("/users/{id}")    // true
    /// PathPattern("/users/{id}") == PathPattern("/users/{name}")  // false
    /// PathPattern("/users/{id}") == PathPattern("/admin/{id}")    // false
    ///
    /// // Normalized patterns are equal
    /// PathPattern("users/{id}") == PathPattern("/users/{id}/")    // true
    /// ```
    static func == (lhs: PathPattern, rhs: PathPattern) -> Bool {
        return lhs.segments == rhs.segments
    }
}

// MARK: - Internal Types

/// A single segment of a path pattern
private enum PathSegment: Equatable {
    /// Literal segment that must match exactly
    case literal(String)
    /// Parameter placeholder that captures the segment value
    case parameter(String)
}
