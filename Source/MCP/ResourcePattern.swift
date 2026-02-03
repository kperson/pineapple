import Foundation

// MARK: - Resource Pattern Matching

/// Resource URI pattern matcher with parameter extraction for MCP resources
///
/// `ResourcePattern` provides regex-based pattern matching for resource URIs, extracting named
/// parameters from dynamic segments. It's designed for MCP resource definitions where URIs can
/// include scheme, path, filename, and extension components.
///
/// ## Pattern Syntax
///
/// Patterns consist of literal text and parameter placeholders:
/// - **Literal text**: Matches exactly (including special regex characters)
/// - **Parameter placeholders**: `{paramName}` matches any value except `/`
///
/// ## Examples
///
/// ```swift
/// // Simple filename with parameter
/// let pattern = ResourcePattern("{filename}.txt")
/// let params = pattern.match("readme.txt")
/// params?.string("filename")  // → "readme"
///
/// // Path with parameters
/// let pattern = ResourcePattern("docs/{category}/{filename}")
/// let params = pattern.match("docs/guides/tutorial.md")
/// params?.string("category")  // → "guides"
/// params?.string("filename")  // → "tutorial.md"
///
/// // Filename and extension
/// let pattern = ResourcePattern("{filename}.{ext}")
/// let params = pattern.match("document.pdf")
/// params?.string("filename")  // → "document"
/// params?.string("ext")       // → "pdf"
///
/// // URI with scheme
/// let pattern = ResourcePattern("file://{directory}/{filename}")
/// let params = pattern.match("file://docs/readme.md")
/// params?.string("directory")  // → "docs"
/// params?.string("filename")   // → "readme.md"
/// ```
///
/// ## Parameter Matching Rules
///
/// 1. **No slash crossing**: Parameters match `[^/]+` - they capture everything except slashes
/// 2. **Greedy within segment**: Parameters capture the entire segment between slashes
/// 3. **Special characters**: Parameters can capture dots, hyphens, underscores, etc.
/// 4. **Case sensitive**: Literal text matches case-sensitively
///
/// Examples of parameter boundaries:
/// ```swift
/// // ✅ Good: One parameter per path segment
/// ResourcePattern("{dir}/{file}")      // Matches: "docs/readme.md"
/// ResourcePattern("{name}.{ext}")      // Matches: "file.txt"
///
/// // ❌ Won't match paths with subdirectories
/// ResourcePattern("{path}")            // Doesn't match: "dir/subdir/file"
///                                      // (parameter can't cross /)
/// ```
///
/// ## Special Character Handling
///
/// Literal text with regex special characters is automatically escaped:
///
/// ```swift
/// // These work correctly (special chars are escaped)
/// ResourcePattern("file(1).txt")       // Matches: "file(1).txt"
/// ResourcePattern("data[0].json")      // Matches: "data[0].json"
/// ResourcePattern("file?.txt")         // Matches: "file?.txt"
/// ResourcePattern("file*.cpp")         // Matches: "file*.cpp"
/// ResourcePattern("c++/file.cpp")      // Matches: "c++/file.cpp"
/// ```
///
/// ## Multi-Tenant Resources
///
/// ResourcePattern is commonly used for tenant-specific resources:
///
/// ```swift
/// let pattern = ResourcePattern("{tenantId}/files/{category}/{filename}")
/// let params = pattern.match("acme-corp/files/docs/contract.pdf")
/// let tenantId = params?.string("tenantId")  // → "acme-corp"
/// let category = params?.string("category")  // → "docs"
/// let filename = params?.string("filename")  // → "contract.pdf"
/// ```
///
/// ## Comparison with PathPattern
///
/// | Feature | PathPattern | ResourcePattern |
/// |---------|-------------|-----------------|
/// | Use case | HTTP paths | Resource URIs |
/// | Separator | `/` segments | Regex-based |
/// | Special chars | N/A | Supports dots, colons, etc. |
/// | Normalization | Slashes trimmed | Exact matching |
/// | Complexity | Simple splitting | Regex compilation |
///
/// ## Performance
///
/// Pattern compilation (regex creation) happens once in the initializer. The compiled
/// regex is cached and reused for all subsequent `match()` calls.
///
/// ```swift
/// // ✅ Good: Compile once, match many times
/// let pattern = ResourcePattern("{category}/{filename}.{ext}")
/// for uri in resourceURIs {
///     if let params = pattern.match(uri) {
///         // Handle resource
///     }
/// }
///
/// // ❌ Bad: Compiles regex on every iteration
/// for uri in resourceURIs {
///     let pattern = ResourcePattern("{category}/{filename}.{ext}")  // Wasteful!
///     if let params = pattern.match(uri) {
///         // Handle resource
///     }
/// }
/// ```
struct ResourcePattern {
    /// The original pattern string
    let pattern: String
    
    /// Compiled regular expression for matching
    private let regex: NSRegularExpression
    
    /// Extracted parameter names in order of appearance
    let parameterNames: [String]
    
    /// Creates a resource pattern from a URI template
    ///
    /// The pattern is compiled immediately and the regex is cached for efficient matching.
    ///
    /// - Parameter pattern: URI pattern with optional `{paramName}` placeholders
    ///
    /// ## Examples
    ///
    /// ```swift
    /// ResourcePattern("file.txt")                  // Literal URI
    /// ResourcePattern("{filename}.txt")            // Single parameter
    /// ResourcePattern("{name}.{ext}")              // Multiple parameters
    /// ResourcePattern("docs/{category}/{file}")    // Path with parameters
    /// ResourcePattern("file://{path}/{filename}")  // URI with scheme
    /// ```
    ///
    /// ## Parameter Extraction
    ///
    /// Parameters are extracted in the order they appear:
    /// ```swift
    /// let pattern = ResourcePattern("{a}/{b}/{c}")
    /// pattern.parameterNames  // → ["a", "b", "c"]
    /// ```
    ///
    /// ## Special Character Handling
    ///
    /// Literal text is automatically escaped to handle regex special characters:
    /// - Parentheses: `file(1).txt`
    /// - Brackets: `data[0].json`
    /// - Dots: `file.v2.txt`
    /// - Plus: `c++/file.cpp`
    /// - Question marks: `file?.txt`
    /// - Asterisks: `file*.cpp`
    ///
    /// ## Implementation Note
    ///
    /// The implementation uses force unwraps (`try!`) when creating the parameter extraction
    /// regex because the pattern is hardcoded and guaranteed to be valid. The final regex
    /// compilation could theoretically fail with malformed input, but such patterns would
    /// simply fail to match (not crash).
    init(_ pattern: String) {
        self.pattern = pattern
        
        // Extract parameter names from the pattern
        var names: [String] = []
        var regexPattern = pattern
        
        // Replace {paramName} with capture groups
        // This regex is hardcoded and safe - it finds {paramName} placeholders
        let paramRegex = try! NSRegularExpression(pattern: "\\{([^}]+)\\}")
        let matches = paramRegex.matches(in: regexPattern, range: NSRange(regexPattern.startIndex..., in: regexPattern))
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            let paramRange = Range(match.range(at: 1), in: regexPattern)!
            let paramName = String(regexPattern[paramRange])
            names.insert(paramName, at: 0)
            
            let fullRange = Range(match.range(at: 0), in: regexPattern)!
            regexPattern.replaceSubrange(fullRange, with: "CAPTURE_GROUP_PLACEHOLDER")
        }
        
        // Escape special regex characters in literal text
        regexPattern = NSRegularExpression.escapedPattern(for: regexPattern)
        
        // Restore our capture groups (matches everything except /)
        regexPattern = regexPattern.replacingOccurrences(of: "CAPTURE_GROUP_PLACEHOLDER", with: "([^/]+)")
        
        // Anchor the pattern to match the entire string
        regexPattern = "^" + regexPattern + "$"
        
        self.parameterNames = names
        
        // Compile final regex - uses try! because we control the pattern construction
        // Malformed user input will create a non-matching regex, not crash
        self.regex = try! NSRegularExpression(pattern: regexPattern)
    }
    
    /// Attempts to match a resource URI against this pattern
    ///
    /// If the URI matches the pattern, returns a `Params` object containing extracted
    /// parameter values. If the URI doesn't match, returns `nil`.
    ///
    /// - Parameter uri: The resource URI to match
    /// - Returns: Extracted parameters if matched, or `nil` if no match
    ///
    /// ## Matching Rules
    ///
    /// 1. URI must match the entire pattern (anchored with ^ and $)
    /// 2. Literal text must match exactly (case-sensitive)
    /// 3. Parameters match `[^/]+` (everything except slashes)
    ///
    /// ## Examples
    ///
    /// ```swift
    /// let pattern = ResourcePattern("docs/{category}/{filename}.{ext}")
    ///
    /// // Matches
    /// let params = pattern.match("docs/guides/tutorial.md")
    /// params?.string("category")  // → "guides"
    /// params?.string("filename")  // → "tutorial"
    /// params?.string("ext")       // → "md"
    ///
    /// // No match - wrong literal prefix
    /// pattern.match("files/guides/tutorial.md")  // → nil
    ///
    /// // No match - missing extension
    /// pattern.match("docs/guides/tutorial")      // → nil
    ///
    /// // No match - too many path segments
    /// pattern.match("docs/guides/subdir/tutorial.md")  // → nil
    /// // (parameter can't cross slashes)
    /// ```
    ///
    /// ## Special Cases
    ///
    /// ```swift
    /// // Parameters capture special characters (except /)
    /// let pattern = ResourcePattern("{filename}")
    /// pattern.match("my-file_v2.final.txt")?.string("filename")
    /// // → "my-file_v2.final.txt"
    ///
    /// // URL encoding is preserved (decoding is caller's responsibility)
    /// pattern.match("my%20file.txt")?.string("filename")
    /// // → "my%20file.txt"
    ///
    /// // Empty pattern matches only empty string
    /// ResourcePattern("").match("")      // → Params (empty)
    /// ResourcePattern("").match("any")   // → nil
    /// ```
    func match(_ uri: String) -> Params? {
        let range = NSRange(uri.startIndex..., in: uri)
        guard let match = regex.firstMatch(in: uri, range: range) else { return nil }
        
        var extractedValues: [String: String] = [:]
        
        // Extract captured groups
        for (index, paramName) in parameterNames.enumerated() {
            let captureRange = match.range(at: index + 1)
            if captureRange.location != NSNotFound,
               let range = Range(captureRange, in: uri) {
                extractedValues[paramName] = String(uri[range])
            }
        }
        
        return Params(extractedValues)
    }
}

// MARK: - Equatable

extension ResourcePattern: Equatable {
    /// Two patterns are equal if they have the same pattern string and parameter names
    ///
    /// This allows pattern comparison for testing and deduplication:
    /// ```swift
    /// ResourcePattern("{name}.txt") == ResourcePattern("{name}.txt")    // true
    /// ResourcePattern("{name}.txt") == ResourcePattern("{file}.txt")    // false
    /// ResourcePattern("{name}.txt") == ResourcePattern("{name}.pdf")    // false
    /// ```
    static func == (lhs: ResourcePattern, rhs: ResourcePattern) -> Bool {
        return lhs.pattern == rhs.pattern && lhs.parameterNames == rhs.parameterNames
    }
}
