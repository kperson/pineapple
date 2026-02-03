import Testing
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import MCP
import MCPHummingbird
import TestSupport
import SimpleMathServer

/// Tests for MCPHummingbird adapter using SimpleMathServer
///
/// These tests verify that the Hummingbird HTTP adapter correctly translates
/// between HTTP requests and MCP protocol, using the common HTTP test suite.
@Suite("Hummingbird Adapter Tests")
struct HummingbirdAdapterTests {
    
    // MARK: - Test Setup
    
    /// Creates a Hummingbird app with SimpleMathServer for testing
    ///
    /// ## Testing Mode
    ///
    /// This app is configured for testing with `port: 0` (ephemeral port), but **no actual
    /// HTTP server is started**. Instead, Hummingbird's `.test()` framework routes requests
    /// in-memory directly to the router, bypassing the network layer entirely.
    ///
    /// This means:
    /// - ✅ No port conflicts between tests
    /// - ✅ No server startup/shutdown overhead
    /// - ✅ Fast, reliable, isolated tests
    /// - ✅ Tests run in parallel without interference
    ///
    /// The test flow is: `TestClient → Router → Handler → Response` (all in-process)
    ///
    /// For real HTTP server usage, see `MCPExample` which uses `app.run()` instead.
    func createTestApp() -> Application<RouterResponder<BasicRequestContext>> {
        let server = createSimpleMathServer()
        let adapter = HummingbirdAdapter()
        let router = HummingbirdRouter()
        router.addServer(path: "/math", server: server)
        
        return adapter.createApp(
            router: router,
            configuration: .init(address: .hostname("localhost", port: 0)) // Port unused in test mode
        )
    }
    
    /// Makes an HTTP request to the Hummingbird test server
    ///
    /// Uses Hummingbird's `app.test(.router)` framework to route requests in-memory
    /// without starting a real HTTP server. The `client` is a mock that talks directly
    /// to the router, not over the network.
    func makeRequest(app: Application<RouterResponder<BasicRequestContext>>, path: String, body: Data) async throws -> Data {
        return try await app.test(.router) { client in
            let response = try await client.execute(
                uri: path,
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(data: body)
            )
            
            guard response.status == .ok else {
                throw TestError.networkError("HTTP status \(response.status.code)")
            }
            
            // Response body is a ByteBuffer, convert to Data
            return Data(buffer: response.body)
        }
    }
    
    // MARK: - Common HTTP Tests
    
    @Test("Initialize returns capabilities")
    func testInitialize() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testInitialize()
    }
    
    @Test("Tools list returns add_numbers")
    func testToolsList() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testToolsList()
    }
    
    @Test("Tools call executes add_numbers with doubles")
    func testToolsCall() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testToolsCall()
    }
    
    @Test("Tools call executes add_numbers with integers")
    func testToolsCallWithIntegers() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testToolsCallWithIntegers()
    }
    
    @Test("Tools call returns error for nonexistent tool")
    func testToolsCallNonexistentTool() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testToolsCallNonexistentTool()
    }
    
    @Test("Resources list returns pi constant")
    func testResourcesList() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testResourcesList()
    }
    
    @Test("Resources read returns pi value")
    func testResourcesRead() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testResourcesRead()
    }
    
    @Test("Resources read returns error for nonexistent resource")
    func testResourcesReadNonexistent() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testResourcesReadNonexistent()
    }
    
    @Test("Prompts list returns explain_math")
    func testPromptsList() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testPromptsList()
    }
    
    @Test("Prompts get generates explanation prompt")
    func testPromptsGet() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testPromptsGet()
    }
    
    @Test("Prompts get returns error for missing argument")
    func testPromptsGetMissingArgument() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        try await commonTests.testPromptsGetMissingArgument()
    }
    
    // MARK: - Hummingbird-Specific Tests
    
    @Test("CORS headers are present in response")
    func testCORSHeaders() async throws {
        let app = createTestApp()
        
        try await app.test(.router) { client in
            let body = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "method": "tools/list",
                "id": "1"
            ])
            
            let response = try await client.execute(
                uri: "/math",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(data: body)
            )
            
            // Check CORS headers
            let allowOrigin = response.headers[.init("Access-Control-Allow-Origin")!]
            #expect(allowOrigin == "*", "Should have Access-Control-Allow-Origin: *")
            
            // Note: Hummingbird might not set all CORS headers on every response,
            // but at minimum Allow-Origin should be present
        }
    }
    
    @Test("Content-Type header is application/json")
    func testContentTypeHeader() async throws {
        let app = createTestApp()
        
        try await app.test(.router) { client in
            let body = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "method": "tools/list",
                "id": "1"
            ])
            
            let response = try await client.execute(
                uri: "/math",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(data: body)
            )
            
            let contentType = response.headers[.contentType]
            #expect(contentType == "application/json", "Should have Content-Type: application/json")
        }
    }
    
    @Test("Invalid JSON returns error")
    func testInvalidJSON() async throws {
        let app = createTestApp()
        
        try await app.test(.router) { client in
            let invalidJSON = "{ invalid json }".data(using: .utf8)!
            
            let response = try await client.execute(
                uri: "/math",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(data: invalidJSON)
            )
            
            // Invalid JSON causes a decoding error, which results in 500 Internal Server Error
            // This is expected behavior for the HTTP transport layer
            #expect(response.status == .internalServerError, "Should return 500 for invalid JSON")
        }
    }
    
    @Test("Multiple sequential requests work correctly")
    func testMultipleRequests() async throws {
        let app = createTestApp()
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(app: app, path: path, body: body)
        }
        
        // Make multiple requests in sequence
        try await commonTests.testToolsList()
        try await commonTests.testResourcesList()
        try await commonTests.testPromptsList()
        try await commonTests.testToolsCall()
    }
}
