import Testing
import Foundation
@testable import MCP

@Suite("ResourcePattern Tests")
struct ResourcePatternTests {
    
    // MARK: - Basic URI Matching
    
    @Test("Simple literal URI matches exactly")
    func testSimpleLiteralURI() {
        let pattern = ResourcePattern("file://document.txt")
        
        #expect(pattern.match("file://document.txt") != nil)
        #expect(pattern.match("file://other.txt") == nil)
    }
    
    @Test("URI without scheme")
    func testURIWithoutScheme() {
        let pattern = ResourcePattern("documents/readme.md")
        
        #expect(pattern.match("documents/readme.md") != nil)
        #expect(pattern.match("documents/other.md") == nil)
    }
    
    @Test("URI with multiple path segments")
    func testURIWithMultipleSegments() {
        let pattern = ResourcePattern("file:///users/docs/readme.txt")
        
        #expect(pattern.match("file:///users/docs/readme.txt") != nil)
        #expect(pattern.match("file:///users/docs/other.txt") == nil)
    }
    
    // MARK: - Single Parameter Extraction
    
    @Test("Single parameter in filename")
    func testSingleParameterInFilename() {
        let pattern = ResourcePattern("file://{filename}")
        let params = pattern.match("file://document.txt")
        
        #expect(params != nil)
        #expect(params?.string("filename") == "document.txt")
    }
    
    @Test("Parameter with file extension")
    func testParameterWithExtension() {
        let pattern = ResourcePattern("{filename}.txt")
        let params = pattern.match("readme.txt")
        
        #expect(params != nil)
        #expect(params?.string("filename") == "readme")
    }
    
    @Test("Parameter in path")
    func testParameterInPath() {
        let pattern = ResourcePattern("docs/{filename}")
        let params = pattern.match("docs/readme.md")
        
        #expect(params != nil)
        #expect(params?.string("filename") == "readme.md")
    }
    
    @Test("Parameter with URI scheme")
    func testParameterWithScheme() {
        let pattern = ResourcePattern("file://{filename}")
        let params = pattern.match("file://document.txt")
        
        // Parameters don't cross slashes - this is correct behavior
        #expect(params != nil)
        #expect(params?.string("filename") == "document.txt")
    }
    
    // MARK: - Multiple Parameter Extraction
    
    @Test("Multiple parameters in path")
    func testMultipleParametersInPath() {
        let pattern = ResourcePattern("{category}/{filename}")
        let params = pattern.match("documents/readme.md")
        
        #expect(params != nil)
        #expect(params?.string("category") == "documents")
        #expect(params?.string("filename") == "readme.md")
    }
    
    @Test("Parameter in filename and extension")
    func testParameterInFilenameAndExtension() {
        let pattern = ResourcePattern("{filename}.{ext}")
        let params = pattern.match("readme.md")
        
        #expect(params != nil)
        #expect(params?.string("filename") == "readme")
        #expect(params?.string("ext") == "md")
    }
    
    @Test("Multiple parameters with scheme")
    func testMultipleParametersWithScheme() {
        let pattern = ResourcePattern("file://{directory}/{filename}.{ext}")
        let params = pattern.match("file://docs/readme.md")
        
        #expect(params != nil)
        #expect(params?.string("directory") == "docs")
        #expect(params?.string("filename") == "readme")
        #expect(params?.string("ext") == "md")
    }
    
    @Test("Three parameters in complex path")
    func testThreeParametersComplexPath() {
        let pattern = ResourcePattern("{tenant}/files/{category}/{filename}")
        let params = pattern.match("acme-corp/files/documents/contract.pdf")
        
        #expect(params != nil)
        #expect(params?.string("tenant") == "acme-corp")
        #expect(params?.string("category") == "documents")
        #expect(params?.string("filename") == "contract.pdf")
    }
    
    // MARK: - Special Characters in Literals
    
    @Test("Dots in literal URI")
    func testDotsInLiteral() {
        let pattern = ResourcePattern("file.v2.txt")
        
        #expect(pattern.match("file.v2.txt") != nil)
        #expect(pattern.match("file_v2_txt") == nil)
    }
    
    @Test("Parentheses in literal")
    func testParenthesesInLiteral() {
        let pattern = ResourcePattern("file(1).txt")
        
        #expect(pattern.match("file(1).txt") != nil)
        #expect(pattern.match("file1.txt") == nil)
    }
    
    @Test("Brackets in literal")
    func testBracketsInLiteral() {
        let pattern = ResourcePattern("data[0].json")
        
        #expect(pattern.match("data[0].json") != nil)
        #expect(pattern.match("data0.json") == nil)
    }
    
    @Test("Plus signs in literal")
    func testPlusSignsInLiteral() {
        let pattern = ResourcePattern("c++/file.cpp")
        
        #expect(pattern.match("c++/file.cpp") != nil)
        #expect(pattern.match("c/file.cpp") == nil)
    }
    
    @Test("Question marks in literal")
    func testQuestionMarksInLiteral() {
        let pattern = ResourcePattern("file?.txt")
        
        #expect(pattern.match("file?.txt") != nil)
        #expect(pattern.match("file.txt") == nil)
    }
    
    @Test("Asterisks in literal")
    func testAsterisksInLiteral() {
        let pattern = ResourcePattern("file*.txt")
        
        #expect(pattern.match("file*.txt") != nil)
        #expect(pattern.match("file.txt") == nil)
    }
    
    // MARK: - Special Characters in Parameters
    
    @Test("Parameter captures dots")
    func testParameterCapturesDots() {
        let pattern = ResourcePattern("{filename}")
        let params = pattern.match("readme.v2.final.txt")
        
        #expect(params != nil)
        #expect(params?.string("filename") == "readme.v2.final.txt")
    }
    
    @Test("Parameter captures hyphens and underscores")
    func testParameterCapturesHyphensAndUnderscores() {
        let pattern = ResourcePattern("{filename}")
        let params = pattern.match("my-file_name.txt")
        
        #expect(params != nil)
        #expect(params?.string("filename") == "my-file_name.txt")
    }
    
    @Test("Parameter with special chars between literals")
    func testParameterBetweenLiterals() {
        let pattern = ResourcePattern("prefix-{name}-suffix.txt")
        let params = pattern.match("prefix-my_file-suffix.txt")
        
        #expect(params != nil)
        #expect(params?.string("name") == "my_file")
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty pattern matches empty string")
    func testEmptyPattern() {
        let pattern = ResourcePattern("")
        
        #expect(pattern.match("") != nil)
        #expect(pattern.match("anything") == nil)
    }
    
    @Test("Pattern with no parameters")
    func testPatternWithNoParameters() {
        let pattern = ResourcePattern("static/file.txt")
        
        #expect(pattern.match("static/file.txt") != nil)
        #expect(pattern.parameterNames.isEmpty)
    }
    
    @Test("Pattern with only parameter")
    func testPatternOnlyParameter() {
        let pattern = ResourcePattern("{value}")
        let params = pattern.match("anything")
        
        #expect(params != nil)
        #expect(params?.string("value") == "anything")
    }
    
    @Test("URI with URL encoding")
    func testURIWithURLEncoding() {
        let pattern = ResourcePattern("{filename}")
        let params = pattern.match("my%20file.txt")
        
        // Pattern should match the encoded URI as-is
        // Decoding is caller's responsibility
        #expect(params != nil)
        #expect(params?.string("filename") == "my%20file.txt")
    }
    
    @Test("Case sensitive matching")
    func testCaseSensitiveMatching() {
        let pattern = ResourcePattern("File.TXT")
        
        #expect(pattern.match("File.TXT") != nil)
        #expect(pattern.match("file.txt") == nil)
    }
    
    // MARK: - Parameter Boundaries
    
    @Test("Parameter doesn't cross slashes")
    func testParameterDoesNotCrossSlashes() {
        let pattern = ResourcePattern("docs/{filename}")
        
        // Parameter should match segment, not cross into path
        #expect(pattern.match("docs/readme.txt") != nil)
        #expect(pattern.match("docs/subdir/readme.txt") == nil)
    }
    
    @Test("Multiple slashes in URI")
    func testMultipleSlashesInURI() {
        let pattern = ResourcePattern("file:///{dir}/{filename}")
        let params = pattern.match("file:///users/file.txt")
        
        // Parameters don't cross slashes
        #expect(params != nil)
        #expect(params?.string("dir") == "users")
        #expect(params?.string("filename") == "file.txt")
    }
    
    // MARK: - Complex Patterns
    
    @Test("Full URI with scheme, host, and path parameters")
    func testFullURIPattern() {
        let pattern = ResourcePattern("{scheme}://{host}/{endpoint}")
        let params = pattern.match("https://example.com/users")
        
        // Parameters don't cross slashes - each param matches one segment
        #expect(params != nil)
        #expect(params?.string("scheme") == "https")
        #expect(params?.string("host") == "example.com")
        #expect(params?.string("endpoint") == "users")
    }
    
    @Test("Mixed literals and parameters")
    func testMixedLiteralsAndParameters() {
        let pattern = ResourcePattern("api/v1/{resource}/{id}/details.json")
        let params = pattern.match("api/v1/users/123/details.json")
        
        #expect(params != nil)
        #expect(params?.string("resource") == "users")
        #expect(params?.string("id") == "123")
    }
    
    @Test("Parameter names extracted in order")
    func testParameterNamesOrder() {
        let pattern = ResourcePattern("{first}/{second}/{third}")
        
        #expect(pattern.parameterNames.count == 3)
        #expect(pattern.parameterNames[0] == "first")
        #expect(pattern.parameterNames[1] == "second")
        #expect(pattern.parameterNames[2] == "third")
    }
    
    // MARK: - Equatable Support
    
    @Test("Identical patterns are equal")
    func testIdenticalPatternsEqual() {
        let pattern1 = ResourcePattern("file://{filename}")
        let pattern2 = ResourcePattern("file://{filename}")
        
        #expect(pattern1 == pattern2)
    }
    
    @Test("Different patterns are not equal")
    func testDifferentPatternsNotEqual() {
        let pattern1 = ResourcePattern("file://{filename}")
        let pattern2 = ResourcePattern("file://{name}")
        let pattern3 = ResourcePattern("docs/{filename}")
        
        #expect(pattern1 != pattern2) // Different param names
        #expect(pattern1 != pattern3) // Different literals
    }
    
    @Test("Pattern equality includes parameter names")
    func testPatternEqualityIncludesParamNames() {
        let pattern1 = ResourcePattern("{a}/{b}")
        let pattern2 = ResourcePattern("{x}/{y}")
        
        // Same structure, different param names
        #expect(pattern1 != pattern2)
    }
}
