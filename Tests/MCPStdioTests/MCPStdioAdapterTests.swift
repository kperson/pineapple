import Testing
import Foundation
import Logging
import TestSupport
import SimpleMathServer
@testable import MCP
@testable import MCPStdio

/// Tests for MCPStdio adapter using SimpleMathServer
///
/// These tests verify that the Stdio adapter correctly processes MCP requests
/// by using mock input/output instead of actual stdin/stdout.
@Suite("Stdio Adapter Tests")
struct MCPStdioAdapterTests {
    
    // MARK: - Test Helpers
    
    /// Wraps the common test pattern into a reusable closure
    ///
    /// This creates mock input/output, runs the adapter, and returns the response.
    func makeRequest(path: String = "/math", body: Data) async throws -> Data {
        // Decode MCP request
        guard let requestString = String(data: body, encoding: .utf8) else {
            throw TestError.networkError("Failed to decode request as UTF-8")
        }
        
        // Create server and router
        let server = createSimpleMathServer()
        let router = StdioRouter()
        router.addServer(path: "/math", server: server)
        
        // Create mock I/O
        let input = MockInputReader(lines: [requestString])
        let output = MockOutputWriter()
        
        // Create adapter with mocks
        let adapter = StdioAdapter(
            router: router,
            inputReader: input,
            outputWriter: output
        )
        
        // Run adapter (will process one line and exit when input ends)
        try await adapter.run(mcpPath: path)
        
        // Verify we got output
        let lines = await output.writtenLines
        guard lines.count > 0 else {
            throw TestError.networkError("No output written")
        }
        
        // Return the first response
        guard let responseData = lines[0].data(using: .utf8) else {
            throw TestError.networkError("Failed to decode response as UTF-8")
        }
        
        return responseData
    }
    
    // MARK: - Common HTTP Tests
    
    @Test("Initialize returns capabilities")
    func testInitialize() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testInitialize()
    }
    
    @Test("Tools list returns add_numbers tool")
    func testToolsList() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testToolsList()
    }
    
    @Test("Tools call executes add_numbers")
    func testToolsCall() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testToolsCall()
    }
    
    @Test("Tools call with integers")
    func testToolsCallWithIntegers() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testToolsCallWithIntegers()
    }
    
    @Test("Tools call nonexistent tool returns error")
    func testToolsCallNonexistentTool() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testToolsCallNonexistentTool()
    }
    
    @Test("Resources list returns pi constant")
    func testResourcesList() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testResourcesList()
    }
    
    @Test("Resources read returns pi value")
    func testResourcesRead() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testResourcesRead()
    }
    
    @Test("Resources read nonexistent returns error")
    func testResourcesReadNonexistent() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testResourcesReadNonexistent()
    }
    
    @Test("Prompts list returns explain_math")
    func testPromptsList() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testPromptsList()
    }
    
    @Test("Prompts get generates math explanation")
    func testPromptsGet() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testPromptsGet()
    }
    
    @Test("Prompts get with missing argument returns error")
    func testPromptsGetMissingArgument() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testPromptsGetMissingArgument()
    }
    
    // MARK: - Stdio-Specific Tests
    
    @Test("Multiple requests are processed in sequence")
    func testMultipleRequests() async throws {
        // Create server
        let server = createSimpleMathServer()
        let router = StdioRouter()
        router.addServer(path: "/math", server: server)
        
        // Create mock I/O with multiple requests
        let input = MockInputReader(lines: [
            #"{"jsonrpc":"2.0","id":"1","method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":"2","method":"resources/list"}"#,
            #"{"jsonrpc":"2.0","id":"3","method":"prompts/list"}"#
        ])
        let output = MockOutputWriter()
        
        // Create and run adapter
        let adapter = StdioAdapter(
            router: router,
            inputReader: input,
            outputWriter: output
        )
        
        try await adapter.run(mcpPath: "/math")
        
        // Verify all three responses
        let lines = await output.writtenLines
        #expect(lines.count == 3)
        
        // Parse each response and verify it has the expected ID
        for (index, line) in lines.enumerated() {
            let data = line.data(using: .utf8)!
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let id = json["id"] as! String
            #expect(id == "\(index + 1)")
        }
    }
    
    @Test("Middleware can access environment variables")
    func testMiddlewareEnvironment() async throws {
        // Create server
        let server = createSimpleMathServer()
        let router = StdioRouter()
        router.addServer(path: "/math", server: server)
        
        // Create adapter with middleware
        let input = MockInputReader(lines: [
            #"{"jsonrpc":"2.0","id":"1","method":"tools/list"}"#
        ])
        let output = MockOutputWriter()
        
        let adapter = StdioAdapter(
            router: router,
            inputReader: input,
            outputWriter: output
        )
        
        var envWasCalled = false
        let envMiddleware = PreRequestMiddlewareHelpers.from { 
            (context: StdioMCPContext, envelope: TransportEnvelope) in
            envWasCalled = true
            #expect(context.environment.count > 0)  // Should have env vars
            #expect(context.processId > 0)  // Should have valid PID
            #expect(context.routePath == "/math")
            return .passthrough
        }
        
        adapter.usePreRequestMiddleware(envMiddleware)
        
        try await adapter.run(mcpPath: "/math")
        
        // Verify middleware was called
        #expect(envWasCalled)
        let lines = await output.writtenLines
        #expect(lines.count == 1)
    }
    
    @Test("Parse errors are returned as error responses")
    func testParseError() async throws {
        // Create server
        let server = createSimpleMathServer()
        let router = StdioRouter()
        router.addServer(path: "/math", server: server)
        
        // Create mock I/O with invalid JSON
        let input = MockInputReader(lines: [
            "{ invalid json }"
        ])
        let output = MockOutputWriter()
        
        // Create and run adapter
        let adapter = StdioAdapter(
            router: router,
            inputReader: input,
            outputWriter: output
        )
        
        try await adapter.run(mcpPath: "/math")
        
        // Verify error response was written
        let lines = await output.writtenLines
        #expect(lines.count == 1)
        
        let data = lines[0].data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        // Should have error field
        #expect(json["error"] != nil)
        
        let error = json["error"] as! [String: Any]
        let code = error["code"] as! Int
        #expect(code == -32700)  // Parse error code
    }
    
    @Test("Middleware rejection returns error immediately")
    func testMiddlewareRejection() async throws {
        // Create server
        let server = createSimpleMathServer()
        let router = StdioRouter()
        router.addServer(path: "/math", server: server)
        
        // Create adapter with rejecting middleware
        let input = MockInputReader(lines: [
            #"{"jsonrpc":"2.0","id":"1","method":"tools/list"}"#
        ])
        let output = MockOutputWriter()
        
        let adapter = StdioAdapter(
            router: router,
            inputReader: input,
            outputWriter: output
        )
        
        let rejectMiddleware = PreRequestMiddlewareHelpers.from {
            (context: StdioMCPContext, envelope: TransportEnvelope) in
            return .reject(MCPError(code: .invalidRequest, message: "Unauthorized"))
        }
        
        adapter.usePreRequestMiddleware(rejectMiddleware)
        
        try await adapter.run(mcpPath: "/math")
        
        // Verify error response
        let lines = await output.writtenLines
        #expect(lines.count == 1)
        
        let data = lines[0].data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        let error = json["error"] as! [String: Any]
        let message = error["message"] as! String
        #expect(message == "Unauthorized")
    }
}
