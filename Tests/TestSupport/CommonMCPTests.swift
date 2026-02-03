import Foundation
import Testing
import MCP
import SimpleMathServer

/// Common test suite for MCP adapters
///
/// This struct provides a reusable test suite that can be used to test any
/// MCP adapter (Hummingbird HTTP, Lambda, Stdio, etc.) by providing a closure
/// that processes MCP requests and returns responses.
///
/// ## Usage
///
/// ```swift
/// let mcpTests = CommonMCPTests { path, body in
///     // Process MCP request and return response
///     // Implementation varies by adapter:
///     // - HTTP: Make HTTP request
///     // - Lambda: Invoke handler with mock API Gateway event
///     // - Stdio: Use mock input/output
///     return try await processRequest(path: path, body: body)
/// }
///
/// // Run all tests
/// try await mcpTests.testToolsList()
/// try await mcpTests.testToolsCall()
/// // ... etc
/// ```
///
/// ## Design
///
/// This approach uses composition instead of inheritance, which works better
/// with Swift Testing. Each test target creates an instance of this struct
/// and provides its own `makeRequest` implementation.
public struct CommonMCPTests {
    
    /// Closure that processes an MCP request and returns the response
    ///
    /// The implementation of this closure varies by adapter type:
    /// - **HTTP (Hummingbird)**: Makes HTTP POST request
    /// - **Lambda**: Creates mock API Gateway event and invokes handler
    /// - **Stdio**: Uses mock input/output streams
    ///
    /// - Parameters:
    ///   - path: The MCP route path (e.g., "/math")
    ///   - body: The MCP JSON-RPC request body as Data
    /// - Returns: The MCP JSON-RPC response body as Data
    public let makeRequest: (_ path: String, _ body: Data) async throws -> Data
    
    /// Create a new common test suite with a request handler
    ///
    /// - Parameter makeRequest: Closure that processes MCP requests
    public init(makeRequest: @escaping (_ path: String, _ body: Data) async throws -> Data) {
        self.makeRequest = makeRequest
    }
    
    // MARK: - Helper Methods
    
    /// Creates an MCP JSON-RPC request
    func createMCPRequest(method: String, params: [String: Any]? = nil, id: String = "1") throws -> Data {
        var request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "id": id
        ]
        if let params = params {
            request["params"] = params
        }
        return try JSONSerialization.data(withJSONObject: request)
    }
    
    /// Parses an MCP response and extracts the result
    func parseResponse(_ data: Data) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let json = json else {
            throw TestError.invalidResponse("Response is not a JSON object")
        }
        return json
    }
    
    /// Extracts the result from an MCP response
    func extractResult(_ response: [String: Any]) throws -> [String: Any] {
        guard let result = response["result"] as? [String: Any] else {
            // Check if there's an error instead
            if let error = response["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? -1
                let message = error["message"] as? String ?? "Unknown error"
                throw TestError.mcpError(code: code, message: message)
            }
            throw TestError.invalidResponse("No result in response")
        }
        return result
    }
    
    // MARK: - Initialize Tests
    
    public func testInitialize() async throws {
        let body = try createMCPRequest(method: "initialize")
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        let result = try extractResult(response)
        
        // Verify capabilities are present
        guard let capabilities = result["capabilities"] as? [String: Any] else {
            throw TestError.invalidResponse("No capabilities in initialize response")
        }
        
        // SimpleMathServer has all three capabilities
        #expect(capabilities["tools"] != nil, "Should have tools capability")
        #expect(capabilities["resources"] != nil, "Should have resources capability")
        #expect(capabilities["prompts"] != nil, "Should have prompts capability")
    }
    
    // MARK: - Tool Tests
    
    public func testToolsList() async throws {
        let body = try createMCPRequest(method: "tools/list")
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        let result = try extractResult(response)
        
        guard let tools = result["tools"] as? [[String: Any]] else {
            throw TestError.invalidResponse("No tools array in response")
        }
        
        #expect(tools.count == 1, "Should have exactly 1 tool")
        
        let addNumbersTool = tools[0]
        #expect(addNumbersTool["name"] as? String == "add_numbers")
        #expect(addNumbersTool["description"] as? String == "Adds two numbers together and returns the sum")
        
        // Verify input schema
        guard let inputSchema = addNumbersTool["inputSchema"] as? [String: Any] else {
            throw TestError.invalidResponse("No inputSchema in tool")
        }
        #expect(inputSchema["type"] as? String == "object")
        
        guard let properties = inputSchema["properties"] as? [String: Any] else {
            throw TestError.invalidResponse("No properties in inputSchema")
        }
        #expect(properties["a"] != nil, "Should have 'a' property")
        #expect(properties["b"] != nil, "Should have 'b' property")
        
        guard let required = inputSchema["required"] as? [String] else {
            throw TestError.invalidResponse("No required array in inputSchema")
        }
        #expect(required.contains("a"), "Should require 'a'")
        #expect(required.contains("b"), "Should require 'b'")
    }
    
    public func testToolsCall() async throws {
        let params: [String: Any] = [
            "name": "add_numbers",
            "arguments": [
                "a": 5.5,
                "b": 3.2
            ]
        ]
        let body = try createMCPRequest(method: "tools/call", params: params)
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        let result = try extractResult(response)
        
        // The result should have content array
        guard let content = result["content"] as? [[String: Any]] else {
            throw TestError.invalidResponse("No content array in result")
        }
        
        #expect(content.count == 1, "Should have 1 content item")
        
        let firstContent = content[0]
        #expect(firstContent["type"] as? String == "text")
        
        guard let text = firstContent["text"] as? String else {
            throw TestError.invalidResponse("No text in content")
        }
        
        // Parse the JSON result
        let outputData = text.data(using: .utf8)!
        let output = try JSONSerialization.jsonObject(with: outputData) as! [String: Any]
        let sum = output["sum"] as! Double
        
        #expect(abs(sum - 8.7) < 0.001, "Sum should be 8.7")
    }
    
    public func testToolsCallWithIntegers() async throws {
        let params: [String: Any] = [
            "name": "add_numbers",
            "arguments": [
                "a": 10,
                "b": 20
            ]
        ]
        let body = try createMCPRequest(method: "tools/call", params: params)
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        let result = try extractResult(response)
        
        guard let content = result["content"] as? [[String: Any]],
              let text = content[0]["text"] as? String else {
            throw TestError.invalidResponse("Invalid content structure")
        }
        
        let outputData = text.data(using: .utf8)!
        let output = try JSONSerialization.jsonObject(with: outputData) as! [String: Any]
        let sum = output["sum"] as! Double
        
        #expect(sum == 30.0, "Sum should be 30.0")
    }
    
    public func testToolsCallNonexistentTool() async throws {
        let params: [String: Any] = [
            "name": "nonexistent_tool",
            "arguments": [:]
        ]
        let body = try createMCPRequest(method: "tools/call", params: params)
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        
        // Should have an error, not a result
        guard let error = response["error"] as? [String: Any] else {
            throw TestError.invalidResponse("Expected error for nonexistent tool")
        }
        
        let message = error["message"] as? String ?? ""
        #expect(message.contains("not found") || message.contains("Tool"), "Error message should mention tool not found")
    }
    
    // MARK: - Resource Tests
    
    public func testResourcesList() async throws {
        let body = try createMCPRequest(method: "resources/list")
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        let result = try extractResult(response)
        
        guard let resources = result["resources"] as? [[String: Any]] else {
            throw TestError.invalidResponse("No resources array in response")
        }
        
        #expect(resources.count == 1, "Should have exactly 1 resource")
        
        let piResource = resources[0]
        #expect(piResource["uri"] as? String == "math://constants/pi")
        #expect(piResource["name"] as? String == "pi_constant")
        #expect(piResource["mimeType"] as? String == "text/plain")
        
        let description = piResource["description"] as? String ?? ""
        #expect(description.contains("pi") || description.contains("π"), "Description should mention pi")
    }
    
    public func testResourcesRead() async throws {
        let params: [String: Any] = [
            "uri": "math://constants/pi"
        ]
        let body = try createMCPRequest(method: "resources/read", params: params)
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        let result = try extractResult(response)
        
        guard let contents = result["contents"] as? [[String: Any]] else {
            throw TestError.invalidResponse("No contents array in result")
        }
        
        #expect(contents.count == 1, "Should have 1 content item")
        
        let piContent = contents[0]
        #expect(piContent["uri"] as? String == "math://constants/pi")
        #expect(piContent["mimeType"] as? String == "text/plain")
        #expect(piContent["text"] as? String == "3.14159")
    }
    
    public func testResourcesReadNonexistent() async throws {
        let params: [String: Any] = [
            "uri": "math://constants/nonexistent"
        ]
        let body = try createMCPRequest(method: "resources/read", params: params)
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        
        // Should have an error
        guard let error = response["error"] as? [String: Any] else {
            throw TestError.invalidResponse("Expected error for nonexistent resource")
        }
        
        let message = error["message"] as? String ?? ""
        #expect(message.contains("not found") || message.contains("Resource"), "Error should mention resource not found")
    }
    
    // MARK: - Prompt Tests
    
    public func testPromptsList() async throws {
        let body = try createMCPRequest(method: "prompts/list")
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        let result = try extractResult(response)
        
        guard let prompts = result["prompts"] as? [[String: Any]] else {
            throw TestError.invalidResponse("No prompts array in response")
        }
        
        #expect(prompts.count == 1, "Should have exactly 1 prompt")
        
        let explainPrompt = prompts[0]
        #expect(explainPrompt["name"] as? String == "explain_math")
        
        let description = explainPrompt["description"] as? String ?? ""
        #expect(description.contains("explain") || description.contains("math"), "Description should mention explaining math")
        
        // Verify arguments
        guard let arguments = explainPrompt["arguments"] as? [[String: Any]] else {
            throw TestError.invalidResponse("No arguments array in prompt")
        }
        
        #expect(arguments.count == 1, "Should have 1 argument")
        
        let conceptArg = arguments[0]
        #expect(conceptArg["name"] as? String == "concept")
        #expect(conceptArg["required"] as? Bool == true)
    }
    
    public func testPromptsGet() async throws {
        let params: [String: Any] = [
            "name": "explain_math",
            "arguments": [
                "concept": "derivatives"
            ]
        ]
        let body = try createMCPRequest(method: "prompts/get", params: params)
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        let result = try extractResult(response)
        
        guard let messages = result["messages"] as? [[String: Any]] else {
            throw TestError.invalidResponse("No messages array in result")
        }
        
        #expect(messages.count == 1, "Should have 1 message")
        
        let message = messages[0]
        #expect(message["role"] as? String == "user")
        
        guard let content = message["content"] as? [String: Any] else {
            throw TestError.invalidResponse("No content in message")
        }
        
        #expect(content["type"] as? String == "text")
        
        let text = content["text"] as? String ?? ""
        #expect(text.contains("derivatives"), "Prompt should contain the concept")
        #expect(text.contains("explain"), "Prompt should ask to explain")
    }
    
    public func testPromptsGetMissingArgument() async throws {
        let params: [String: Any] = [
            "name": "explain_math",
            "arguments": [:] // Missing required 'concept' argument
        ]
        let body = try createMCPRequest(method: "prompts/get", params: params)
        let responseData = try await makeRequest("/math", body)
        let response = try parseResponse(responseData)
        
        // Should have an error
        guard let error = response["error"] as? [String: Any] else {
            throw TestError.invalidResponse("Expected error for missing argument")
        }
        
        let message = error["message"] as? String ?? ""
        #expect(message.contains("concept") || message.contains("argument"), "Error should mention missing argument")
    }
}

// MARK: - Test Errors

public enum TestError: Error, CustomStringConvertible {
    case invalidResponse(String)
    case mcpError(code: Int, message: String)
    case networkError(String)
    
    public var description: String {
        switch self {
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .mcpError(let code, let message):
            return "MCP error \(code): \(message)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}
