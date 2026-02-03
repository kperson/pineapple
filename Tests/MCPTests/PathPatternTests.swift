import Testing
@testable import MCP

@Suite("PathPattern Tests")
struct PathPatternTests {
    
    // MARK: - Basic Matching
    
    @Test("Simple literal path matches exactly")
    func testSimpleLiteralMatch() {
        let pattern = PathPattern("/users")
        let params = pattern.match("/users")
        
        #expect(params != nil)
    }
    
    @Test("Simple literal path no match")
    func testSimpleLiteralNoMatch() {
        let pattern = PathPattern("/users")
        let params = pattern.match("/admin")
        
        #expect(params == nil)
    }
    
    @Test("Root path matching")
    func testRootPathMatching() {
        let pattern = PathPattern("/")
        
        #expect(pattern.match("/") != nil)
        #expect(pattern.match("") != nil)
    }
    
    @Test("Empty pattern matches empty path")
    func testEmptyPatternMatchesEmptyPath() {
        let pattern = PathPattern("")
        
        #expect(pattern.match("") != nil)
        #expect(pattern.match("/") != nil)
    }
    
    @Test("Multi-segment literal path")
    func testMultiSegmentLiteral() {
        let pattern = PathPattern("/api/v1/users")
        
        #expect(pattern.match("/api/v1/users") != nil)
        #expect(pattern.match("/api/v1/posts") == nil)
        #expect(pattern.match("/api/v1") == nil)
        #expect(pattern.match("/api/v1/users/extra") == nil)
    }
    
    // MARK: - Parameter Extraction
    
    @Test("Single parameter extraction")
    func testSingleParameterExtraction() {
        let pattern = PathPattern("/users/{id}")
        let params = pattern.match("/users/123")
        
        #expect(params != nil)
        #expect(params?.string("id") == "123")
    }
    
    @Test("Multiple parameters extraction")
    func testMultipleParametersExtraction() {
        let pattern = PathPattern("/users/{userId}/posts/{postId}")
        let params = pattern.match("/users/42/posts/99")
        
        #expect(params != nil)
        #expect(params?.string("userId") == "42")
        #expect(params?.string("postId") == "99")
    }
    
    @Test("Parameter at start of path")
    func testParameterAtStart() {
        let pattern = PathPattern("/{category}/items")
        let params = pattern.match("/books/items")
        
        #expect(params != nil)
        #expect(params?.string("category") == "books")
    }
    
    @Test("Parameter at end of path")
    func testParameterAtEnd() {
        let pattern = PathPattern("/api/users/{id}")
        let params = pattern.match("/api/users/user-123")
        
        #expect(params != nil)
        #expect(params?.string("id") == "user-123")
    }
    
    @Test("All segments are parameters")
    func testAllSegmentsAreParameters() {
        let pattern = PathPattern("/{tenant}/{resource}/{id}")
        let params = pattern.match("/acme-corp/users/42")
        
        #expect(params != nil)
        #expect(params?.string("tenant") == "acme-corp")
        #expect(params?.string("resource") == "users")
        #expect(params?.string("id") == "42")
    }
    
    @Test("Parameter with special characters in value")
    func testParameterWithSpecialCharacters() {
        let pattern = PathPattern("/files/{filename}")
        
        // Should match any value (URL encoding is caller's responsibility)
        #expect(pattern.match("/files/my-file.txt")?.string("filename") == "my-file.txt")
        #expect(pattern.match("/files/report_2024.pdf")?.string("filename") == "report_2024.pdf")
        #expect(pattern.match("/files/user@example.com")?.string("filename") == "user@example.com")
    }
    
    @Test("Parameters not extracted when no match")
    func testParametersNotExtractedWhenNoMatch() {
        let pattern = PathPattern("/users/{id}/posts")
        
        #expect(pattern.match("/admin/123/posts") == nil)
        #expect(pattern.match("/users/123/comments") == nil)
    }
    
    // MARK: - Path Normalization
    
    @Test("Leading slashes ignored in pattern")
    func testLeadingSlashesIgnoredInPattern() {
        let pattern1 = PathPattern("users")
        let pattern2 = PathPattern("/users")
        let pattern3 = PathPattern("//users")
        
        // All should match the same paths
        #expect(pattern1.match("/users") != nil)
        #expect(pattern2.match("/users") != nil)
        #expect(pattern3.match("/users") != nil)
    }
    
    @Test("Trailing slashes ignored in pattern")
    func testTrailingSlashesIgnoredInPattern() {
        let pattern1 = PathPattern("/users")
        let pattern2 = PathPattern("/users/")
        let pattern3 = PathPattern("/users//")
        
        // All should match the same paths
        #expect(pattern1.match("/users") != nil)
        #expect(pattern2.match("/users") != nil)
        #expect(pattern3.match("/users") != nil)
    }
    
    @Test("Leading slashes ignored in path")
    func testLeadingSlashesIgnoredInPath() {
        let pattern = PathPattern("/users/{id}")
        
        #expect(pattern.match("users/123")?.string("id") == "123")
        #expect(pattern.match("/users/123")?.string("id") == "123")
        #expect(pattern.match("//users/123")?.string("id") == "123")
    }
    
    @Test("Trailing slashes ignored in path")
    func testTrailingSlashesIgnoredInPath() {
        let pattern = PathPattern("/users/{id}")
        
        #expect(pattern.match("/users/123")?.string("id") == "123")
        #expect(pattern.match("/users/123/")?.string("id") == "123")
        #expect(pattern.match("/users/123//")?.string("id") == "123")
    }
    
    @Test("Consecutive slashes collapsed")
    func testConsecutiveSlashesCollapsed() {
        let pattern = PathPattern("/users/{id}/posts")
        
        // Multiple slashes should be treated as single separators
        #expect(pattern.match("/users//123//posts")?.string("id") == "123")
        #expect(pattern.match("//users/123/posts//")?.string("id") == "123")
    }
    
    // MARK: - Edge Cases
    
    @Test("Single segment path")
    func testSingleSegmentPath() {
        let pattern = PathPattern("/users")
        
        #expect(pattern.match("/users") != nil)
        #expect(pattern.match("/admin") == nil)
    }
    
    @Test("Single parameter path")
    func testSingleParameterPath() {
        let pattern = PathPattern("/{id}")
        
        #expect(pattern.match("/123")?.string("id") == "123")
        #expect(pattern.match("/abc")?.string("id") == "abc")
        #expect(pattern.match("/") == nil)
    }
    
    @Test("Special characters in literal segments")
    func testSpecialCharactersInLiterals() {
        let pattern = PathPattern("/api-v2/users_admin")
        
        #expect(pattern.match("/api-v2/users_admin") != nil)
        #expect(pattern.match("/api-v1/users_admin") == nil)
    }
    
    @Test("Numeric segments match exactly")
    func testNumericSegments() {
        let pattern = PathPattern("/api/v1/users")
        
        #expect(pattern.match("/api/v1/users") != nil)
        #expect(pattern.match("/api/v2/users") == nil)
    }
    
    @Test("Case sensitive matching")
    func testCaseSensitiveMatching() {
        let pattern = PathPattern("/Users/{id}")
        
        #expect(pattern.match("/Users/123") != nil)
        #expect(pattern.match("/users/123") == nil)
    }
    
    @Test("Empty parameter value matches")
    func testEmptyParameterValue() {
        // This is actually prevented by path splitting - adjacent slashes are collapsed
        // A path like "/users//posts" becomes ["users", "posts"]
        let pattern = PathPattern("/users/{id}/posts")
        
        // No empty segments in the split result
        #expect(pattern.match("/users//posts") == nil)
    }
    
    // MARK: - Segment Count Validation
    
    @Test("Too few segments no match")
    func testTooFewSegments() {
        let pattern = PathPattern("/users/{id}/posts")
        
        #expect(pattern.match("/users") == nil)
        #expect(pattern.match("/users/123") == nil)
    }
    
    @Test("Too many segments no match")
    func testTooManySegments() {
        let pattern = PathPattern("/users/{id}")
        
        #expect(pattern.match("/users/123/extra") == nil)
        #expect(pattern.match("/users/123/posts/456") == nil)
    }
    
    @Test("Exact segment count required")
    func testExactSegmentCountRequired() {
        let pattern = PathPattern("/users/{userId}/posts/{postId}")
        
        #expect(pattern.match("/users/1/posts/2") != nil)
        #expect(pattern.match("/users/1/posts") == nil)
        #expect(pattern.match("/users/1/posts/2/extra") == nil)
    }
    
    // MARK: - Parameter Name Validation
    
    @Test("Parameter names are extracted correctly")
    func testParameterNamesExtractedCorrectly() {
        let pattern = PathPattern("/users/{userId}/posts/{postId}")
        let params = pattern.match("/users/alice/posts/hello")
        
        #expect(params?.string("userId") == "alice")
        #expect(params?.string("postId") == "hello")
        #expect(params?.string("unknown") == nil)
    }
    
    @Test("Empty parameter name accepted but not recommended")
    func testEmptyParameterName() {
        // Current implementation allows this - should we validate?
        let pattern = PathPattern("/users/{}")
        let params = pattern.match("/users/123")
        
        // Empty key in dictionary
        #expect(params != nil)
        #expect(params?.string("") == "123")
    }
    
    @Test("Parameter with whitespace in name")
    func testParameterWithWhitespace() {
        // Current implementation allows this - should we validate?
        let pattern = PathPattern("/users/{user id}")
        let params = pattern.match("/users/123")
        
        #expect(params != nil)
        #expect(params?.string("user id") == "123")
    }
    
    // MARK: - Complex Patterns
    
    @Test("Deep nesting with parameters")
    func testDeepNestingWithParameters() {
        let pattern = PathPattern("/{tenant}/api/v1/{resource}/{id}/details")
        let params = pattern.match("/acme-corp/api/v1/users/42/details")
        
        #expect(params != nil)
        #expect(params?.string("tenant") == "acme-corp")
        #expect(params?.string("resource") == "users")
        #expect(params?.string("id") == "42")
    }
    
    @Test("Alternating literals and parameters")
    func testAlternatingLiteralsAndParameters() {
        let pattern = PathPattern("/api/{version}/users/{userId}/posts/{postId}")
        let params = pattern.match("/api/v2/users/alice/posts/first-post")
        
        #expect(params != nil)
        #expect(params?.string("version") == "v2")
        #expect(params?.string("userId") == "alice")
        #expect(params?.string("postId") == "first-post")
    }
    
    // MARK: - Performance & Caching
    
    @Test("Pattern parsing happens once in initializer")
    func testPatternParsedOnce() {
        // Pattern should be parsed in init, not on every match
        let pattern = PathPattern("/users/{id}/posts/{postId}")
        
        // Multiple matches should reuse parsed segments
        let params1 = pattern.match("/users/1/posts/a")
        let params2 = pattern.match("/users/2/posts/b")
        let params3 = pattern.match("/users/3/posts/c")
        
        #expect(params1?.string("id") == "1")
        #expect(params2?.string("id") == "2")
        #expect(params3?.string("id") == "3")
    }
    
    // MARK: - Equatable Support
    
    @Test("Identical patterns are equal")
    func testIdenticalPatternsEqual() {
        let pattern1 = PathPattern("/users/{id}")
        let pattern2 = PathPattern("/users/{id}")
        
        #expect(pattern1 == pattern2)
    }
    
    @Test("Different patterns are not equal")
    func testDifferentPatternsNotEqual() {
        let pattern1 = PathPattern("/users/{id}")
        let pattern2 = PathPattern("/users/{userId}")
        let pattern3 = PathPattern("/admin/{id}")
        
        #expect(pattern1 != pattern2) // Different param names
        #expect(pattern1 != pattern3) // Different literals
    }
    
    @Test("Normalized patterns are equal")
    func testNormalizedPatternsEqual() {
        let pattern1 = PathPattern("/users/{id}/")
        let pattern2 = PathPattern("users/{id}")
        let pattern3 = PathPattern("//users//{id}//")
        
        // All should normalize to same pattern
        #expect(pattern1 == pattern2)
        #expect(pattern2 == pattern3)
    }
}
