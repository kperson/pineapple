import Testing
import Foundation
import Logging
import JSONValueCoding
@testable import MCP

@Suite("Server Tests")
struct ServerTests {
    
    // MARK: - Test Types
    
    @JSONSchema
    struct SimpleInput: Codable {
        let message: String
        let count: Int
    }
    
    @JSONSchema
    struct SimpleOutput: Codable {
        let result: String
        let processed: Bool
    }
    
    @JSONSchema
    struct FileInput: Codable {
        let path: String
        let recursive: Bool
    }
    
    // MARK: - Helper Methods
    
    func createTestEnvelope(method: String, params: [String: JSONValue] = [:], id: String = "test-1") -> TransportEnvelope {
        TransportEnvelope(
            mcpRequest: Request(id: .string(id), method: method, params: params.isEmpty ? nil : params),
            routePath: "/test"
        )
    }
    
    func createLogger() -> Logger {
        Logger(label: "test-server")
    }
    
    // MARK: - Initialization Tests
    
    @Test("Server initializes with default logger")
    func testServerInitializesWithDefaultLogger() {
        let server = Server()
        #expect(server.logger.label == "mcp-server")
    }
    
    @Test("Server initializes with custom logger")
    func testServerInitializesWithCustomLogger() {
        let customLogger = Logger(label: "custom-logger")
        let server = Server(logger: customLogger)
        #expect(server.logger.label == "custom-logger")
    }
    
    // MARK: - Initialize Method Tests
    
    @Test("Initialize returns capabilities when no features registered")
    func testInitializeReturnsEmptyCapabilities() async throws {
        let server = Server()
        let envelope = createTestEnvelope(method: "initialize")
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        // Verify response structure
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .object(let capabilities)? = result["capabilities"] else {
            #expect(Bool(false), "Expected valid initialize response")
            return
        }
        
        // All capabilities should be nil when no features registered
        #expect(capabilities["tools"] == nil)
        #expect(capabilities["resources"] == nil)
        #expect(capabilities["prompts"] == nil)
    }
    
    @Test("Initialize returns tool capability when tools registered")
    func testInitializeReturnsToolCapability() async throws {
        let server = Server()
            .addTool("test_tool", description: "Test tool", inputType: SimpleInput.self, outputType: SimpleOutput.self) { request in
                SimpleOutput(result: "ok", processed: true)
            }
        
        let envelope = createTestEnvelope(method: "initialize")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .object(let capabilities)? = result["capabilities"] else {
            #expect(Bool(false), "Expected valid initialize response")
            return
        }
        
        #expect(capabilities["tools"] != nil)
        #expect(capabilities["resources"] == nil)
        #expect(capabilities["prompts"] == nil)
    }
    
    @Test("Initialize returns resource capability when resources registered")
    func testInitializeReturnsResourceCapability() async throws {
        let server = Server()
            .addResource("file://test", name: "test", description: "Test resource", mimeType: "text/plain") { request in
                ResourceHandlerResponse(name: "test", data: .text("content"))
            }
        
        let envelope = createTestEnvelope(method: "initialize")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .object(let capabilities)? = result["capabilities"] else {
            #expect(Bool(false), "Expected valid initialize response")
            return
        }
        
        #expect(capabilities["tools"] == nil)
        #expect(capabilities["resources"] != nil)
        #expect(capabilities["prompts"] == nil)
    }
    
    @Test("Initialize returns prompt capability when prompts registered")
    func testInitializeReturnsPromptCapability() async throws {
        let server = Server()
            .addPrompt("test_prompt", description: "Test prompt") { request in
                PromptHandlerResponse(messages: [
                    PromptMessage(role: .user, content: .text("Hello"))
                ])
            }
        
        let envelope = createTestEnvelope(method: "initialize")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .object(let capabilities)? = result["capabilities"] else {
            #expect(Bool(false), "Expected valid initialize response")
            return
        }
        
        #expect(capabilities["tools"] == nil)
        #expect(capabilities["resources"] == nil)
        #expect(capabilities["prompts"] != nil)
    }
    
    @Test("Initialize returns all capabilities when all features registered")
    func testInitializeReturnsAllCapabilities() async throws {
        let server = Server()
            .addTool("test_tool", description: "Test", inputType: SimpleInput.self, outputType: SimpleOutput.self) { _ in
                SimpleOutput(result: "ok", processed: true)
            }
            .addResource("file://test", name: "test", description: "Test", mimeType: "text/plain") { _ in
                ResourceHandlerResponse(name: "test", data: .text("content"))
            }
            .addPrompt("test_prompt", description: "Test") { _ in
                PromptHandlerResponse(messages: [])
            }
        
        let envelope = createTestEnvelope(method: "initialize")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .object(let capabilities)? = result["capabilities"] else {
            #expect(Bool(false), "Expected valid initialize response")
            return
        }
        
        #expect(capabilities["tools"] != nil)
        #expect(capabilities["resources"] != nil)
        #expect(capabilities["prompts"] != nil)
    }
    
    // MARK: - Tool Registration Tests
    
    @Test("Add tool returns self for chaining")
    func testAddToolReturnsServer() {
        let server = Server()
        let result = server.addTool("test", description: "Test", inputType: SimpleInput.self, outputType: SimpleOutput.self) { _ in
            SimpleOutput(result: "ok", processed: true)
        }
        #expect(result === server)
    }
    
    @Test("Add tool with rich content returns self for chaining")
    func testAddToolWithRichContentReturnsServer() {
        let server = Server()
        let result = server.addTool("test", description: "Test", inputType: SimpleInput.self) { _ in
            ToolHandlerResponse.text("result")
        }
        #expect(result === server)
    }
    
    @Test("Multiple tools can be registered")
    func testMultipleToolsCanBeRegistered() async throws {
        let server = Server()
            .addTool("tool1", description: "First", inputType: SimpleInput.self, outputType: SimpleOutput.self) { _ in
                SimpleOutput(result: "tool1", processed: true)
            }
            .addTool("tool2", description: "Second", inputType: SimpleInput.self, outputType: SimpleOutput.self) { _ in
                SimpleOutput(result: "tool2", processed: true)
            }
        
        let envelope = createTestEnvelope(method: "tools/list")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let tools)? = result["tools"] else {
            #expect(Bool(false), "Expected valid tools/list response")
            return
        }
        
        #expect(tools.count == 2)
    }
    
    // MARK: - Tools List Tests
    
    @Test("Tools list returns empty array when no tools registered")
    func testToolsListReturnsEmptyArray() async throws {
        let server = Server()
        let envelope = createTestEnvelope(method: "tools/list")
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let tools)? = result["tools"] else {
            #expect(Bool(false), "Expected valid tools/list response")
            return
        }
        
        #expect(tools.isEmpty)
    }
    
    @Test("Tools list returns registered tools")
    func testToolsListReturnsRegisteredTools() async throws {
        let server = Server()
            .addTool("echo_tool", description: "Echoes input", inputType: SimpleInput.self, outputType: SimpleOutput.self) { _ in
                SimpleOutput(result: "echo", processed: true)
            }
        
        let envelope = createTestEnvelope(method: "tools/list")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let tools)? = result["tools"],
              case .object(let tool)? = tools.first else {
            #expect(Bool(false), "Expected valid tools/list response with tools")
            return
        }
        
        #expect(tools.count == 1)
        #expect(tool["name"]?.string == "echo_tool")
        #expect(tool["description"]?.string == "Echoes input")
        #expect(tool["inputSchema"] != nil)
        #expect(tool["outputSchema"] != nil)
    }
    
    @Test("Tools list includes input and output schemas")
    func testToolsListIncludesSchemas() async throws {
        let server = Server()
            .addTool("test_tool", description: "Test", inputType: SimpleInput.self, outputType: SimpleOutput.self) { _ in
                SimpleOutput(result: "ok", processed: true)
            }
        
        let envelope = createTestEnvelope(method: "tools/list")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let tools)? = result["tools"],
              case .object(let tool)? = tools.first,
              case .object(let inputSchema)? = tool["inputSchema"],
              case .object(let outputSchema)? = tool["outputSchema"] else {
            #expect(Bool(false), "Expected schemas in tool definition")
            return
        }
        
        // Verify input schema has expected properties
        #expect(inputSchema["type"]?.string == "object")
        if case .object(let properties)? = inputSchema["properties"] {
            #expect(properties["message"] != nil)
            #expect(properties["count"] != nil)
        }
        
        // Verify output schema
        #expect(outputSchema["type"]?.string == "object")
        if case .object(let properties)? = outputSchema["properties"] {
            #expect(properties["result"] != nil)
            #expect(properties["processed"] != nil)
        }
    }
    
    // MARK: - Tools Call Tests
    
    @Test("Tool call executes handler with typed input")
    func testToolCallExecutesHandlerWithTypedInput() async throws {
        var capturedInput: SimpleInput?
        
        let server = Server()
            .addTool("process", description: "Process data", inputType: SimpleInput.self, outputType: SimpleOutput.self) { request in
                capturedInput = request.input
                return SimpleOutput(result: "processed: \(request.input.message)", processed: true)
            }
        
        let envelope = createTestEnvelope(
            method: "tools/call",
            params: [
                "name": .string("process"),
                "arguments": .object([
                    "message": .string("hello"),
                    "count": .int(42)
                ])
            ]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        // Verify handler was called with correct input
        #expect(capturedInput?.message == "hello")
        #expect(capturedInput?.count == 42)
        
        // Verify response contains result
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"] else {
            #expect(Bool(false), "Expected valid tool call response")
            return
        }
        
        #expect(result["content"] != nil)
    }
    
    @Test("Tool call returns structured content for typed output")
    func testToolCallReturnsStructuredContent() async throws {
        let server = Server()
            .addTool("get_data", description: "Get data", inputType: SimpleInput.self, outputType: SimpleOutput.self) { request in
                SimpleOutput(result: "data_\(request.input.message)", processed: true)
            }
        
        let envelope = createTestEnvelope(
            method: "tools/call",
            params: [
                "name": .string("get_data"),
                "arguments": .object([
                    "message": .string("test"),
                    "count": .int(1)
                ])
            ]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .object(let structuredContent)? = result["structuredContent"] else {
            #expect(Bool(false), "Expected structured content in response")
            return
        }
        
        #expect(structuredContent["result"]?.string == "data_test")
        #expect(structuredContent["processed"]?.bool == true)
    }
    
    @Test("Tool call with rich content returns content array")
    func testToolCallWithRichContentReturnsContentArray() async throws {
        let server = Server()
            .addTool("generate", description: "Generate content", inputType: SimpleInput.self) { request in
                ToolHandlerResponse.text("Generated: \(request.input.message)")
            }
        
        let envelope = createTestEnvelope(
            method: "tools/call",
            params: [
                "name": .string("generate"),
                "arguments": .object([
                    "message": .string("hello"),
                    "count": .int(1)
                ])
            ]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let content)? = result["content"],
              case .object(let firstContent)? = content.first else {
            #expect(Bool(false), "Expected content array in response")
            return
        }
        
        #expect(content.count == 1)
        #expect(firstContent["type"]?.string == "text")
        #expect(firstContent["text"]?.string == "Generated: hello")
    }
    
    @Test("Tool call passes path parameters to handler")
    func testToolCallPassesPathParametersToHandler() async throws {
        var capturedPathParams: Params?
        
        let server = Server()
            .addTool("customer_tool", description: "Customer tool", inputType: SimpleInput.self, outputType: SimpleOutput.self) { request in
                capturedPathParams = request.pathParams
                let customerId = request.pathParams?.string("customerId") ?? "unknown"
                return SimpleOutput(result: "customer: \(customerId)", processed: true)
            }
        
        let pathParams = try Params(.object([
            "customerId": .string("cust-123"),
            "region": .string("us-west")
        ]))
        
        let envelope = createTestEnvelope(
            method: "tools/call",
            params: [
                "name": .string("customer_tool"),
                "arguments": .object([
                    "message": .string("test"),
                    "count": .int(1)
                ])
            ]
        )
        
        let _: JSONValue = try await server.handleRequest(envelope, pathParams: pathParams, logger: createLogger())
        
        #expect(capturedPathParams?.string("customerId") == "cust-123")
        #expect(capturedPathParams?.string("region") == "us-west")
    }
    
    @Test("Tool call with nil path parameters works")
    func testToolCallWithNilPathParametersWorks() async throws {
        var capturedPathParams: Params?
        
        let server = Server()
            .addTool("simple_tool", description: "Simple tool", inputType: SimpleInput.self, outputType: SimpleOutput.self) { request in
                capturedPathParams = request.pathParams
                return SimpleOutput(result: "ok", processed: true)
            }
        
        let envelope = createTestEnvelope(
            method: "tools/call",
            params: [
                "name": .string("simple_tool"),
                "arguments": .object([
                    "message": .string("test"),
                    "count": .int(1)
                ])
            ]
        )
        
        let _: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        #expect(capturedPathParams == nil)
    }
    
    @Test("Tool call returns error for invalid tool name")
    func testToolCallReturnsErrorForInvalidToolName() async throws {
        let server = Server()
            .addTool("valid_tool", description: "Valid", inputType: SimpleInput.self, outputType: SimpleOutput.self) { _ in
                SimpleOutput(result: "ok", processed: true)
            }
        
        let envelope = createTestEnvelope(
            method: "tools/call",
            params: [
                "name": .string("nonexistent_tool"),
                "arguments": .object([
                    "message": .string("test"),
                    "count": .int(1)
                ])
            ]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let error)? = obj["error"],
              case .string(let message)? = error["message"] else {
            #expect(Bool(false), "Expected error response")
            return
        }
        
        #expect(message == "Tool not found")
    }
    
    @Test("Tool call returns error for missing tool name")
    func testToolCallReturnsErrorForMissingToolName() async throws {
        let server = Server()
        
        let envelope = createTestEnvelope(
            method: "tools/call",
            params: [
                "arguments": .object([
                    "message": .string("test"),
                    "count": .int(1)
                ])
            ]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let error)? = obj["error"] else {
            #expect(Bool(false), "Expected error response")
            return
        }
        
        #expect(error["message"]?.string == "Invalid params")
    }
    
    @Test("Tool call returns error for invalid input type")
    func testToolCallReturnsErrorForInvalidInputType() async throws {
        let server = Server()
            .addTool("strict_tool", description: "Strict", inputType: SimpleInput.self, outputType: SimpleOutput.self) { _ in
                SimpleOutput(result: "ok", processed: true)
            }
        
        let envelope = createTestEnvelope(
            method: "tools/call",
            params: [
                "name": .string("strict_tool"),
                "arguments": .object([
                    "wrong_field": .string("value")
                ])
            ]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        // Should return error response due to decoding failure
        guard case .object(let obj) = response,
              case .object = obj["error"] else {
            #expect(Bool(false), "Expected error response for invalid input")
            return
        }
    }
    
    // MARK: - Resource Registration Tests
    
    @Test("Add resource returns self for chaining")
    func testAddResourceReturnsServer() {
        let server = Server()
        let result = server.addResource("file://test", name: "test", description: "Test", mimeType: "text/plain") { _ in
            ResourceHandlerResponse(name: "test", data: .text("content"))
        }
        #expect(result === server)
    }
    
    @Test("Multiple resources can be registered")
    func testMultipleResourcesCanBeRegistered() async throws {
        let server = Server()
            .addResource("file://docs", name: "docs", description: "Docs", mimeType: "text/plain") { _ in
                ResourceHandlerResponse(name: "docs", data: .text("content"))
            }
            .addResource("file://images/{id}", name: "images", description: "Images", mimeType: "image/png") { _ in
                ResourceHandlerResponse(name: "image", data: .text("data"))
            }
        
        let listEnvelope = createTestEnvelope(method: "resources/list")
        let listResponse: JSONValue = try await server.handleRequest(listEnvelope, pathParams: nil, logger: createLogger())
        
        let templatesEnvelope = createTestEnvelope(method: "resources/templates/list")
        let templatesResponse: JSONValue = try await server.handleRequest(templatesEnvelope, pathParams: nil, logger: createLogger())
        
        // Should have 1 static resource and 1 template
        guard case .object(let listObj) = listResponse,
              case .object(let listResult)? = listObj["result"],
              case .array(let resources)? = listResult["resources"] else {
            #expect(Bool(false), "Expected resources list")
            return
        }
        
        guard case .object(let templatesObj) = templatesResponse,
              case .object(let templatesResult)? = templatesObj["result"],
              case .array(let templates)? = templatesResult["resourceTemplates"] else {
            #expect(Bool(false), "Expected resource templates")
            return
        }
        
        #expect(resources.count == 1)
        #expect(templates.count == 1)
    }
    
    // MARK: - Resources List Tests
    
    @Test("Resources list returns empty array when no resources registered")
    func testResourcesListReturnsEmptyArray() async throws {
        let server = Server()
        let envelope = createTestEnvelope(method: "resources/list")
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let resources)? = result["resources"] else {
            #expect(Bool(false), "Expected valid resources/list response")
            return
        }
        
        #expect(resources.isEmpty)
    }
    
    @Test("Resources list returns only static resources")
    func testResourcesListReturnsOnlyStaticResources() async throws {
        let server = Server()
            .addResource("file://static", name: "static", description: "Static", mimeType: "text/plain") { _ in
                ResourceHandlerResponse(name: "static", data: .text("content"))
            }
            .addResource("file://{id}", name: "dynamic", description: "Dynamic", mimeType: "text/plain") { _ in
                ResourceHandlerResponse(name: "dynamic", data: .text("content"))
            }
        
        let envelope = createTestEnvelope(method: "resources/list")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let resources)? = result["resources"] else {
            #expect(Bool(false), "Expected resources list")
            return
        }
        
        #expect(resources.count == 1)
        
        if case .object(let resource)? = resources.first {
            #expect(resource["uri"]?.string == "file://static")
            #expect(resource["name"]?.string == "static")
        }
    }
    
    // MARK: - Resources Templates List Tests
    
    @Test("Resources templates list returns empty array when no templates registered")
    func testResourcesTemplatesListReturnsEmptyArray() async throws {
        let server = Server()
        let envelope = createTestEnvelope(method: "resources/templates/list")
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let templates)? = result["resourceTemplates"] else {
            #expect(Bool(false), "Expected valid templates list response")
            return
        }
        
        #expect(templates.isEmpty)
    }
    
    @Test("Resources templates list returns only templated resources")
    func testResourcesTemplatesListReturnsOnlyTemplatedResources() async throws {
        let server = Server()
            .addResource("file://static", name: "static", description: "Static", mimeType: "text/plain") { _ in
                ResourceHandlerResponse(name: "static", data: .text("content"))
            }
            .addResource("file://{customerId}/docs/{docId}", name: "docs", description: "Customer docs", mimeType: "text/plain") { _ in
                ResourceHandlerResponse(name: "doc", data: .text("content"))
            }
        
        let envelope = createTestEnvelope(method: "resources/templates/list")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let templates)? = result["resourceTemplates"] else {
            #expect(Bool(false), "Expected templates list")
            return
        }
        
        #expect(templates.count == 1)
        
        if case .object(let template)? = templates.first {
            #expect(template["uriTemplate"]?.string == "file://{customerId}/docs/{docId}")
            #expect(template["name"]?.string == "docs")
        }
    }
    
    // MARK: - Resources Read Tests
    
    @Test("Resource read returns content for static resource")
    func testResourceReadReturnsContentForStaticResource() async throws {
        let server = Server()
            .addResource("file://readme.md", name: "readme", description: "Readme", mimeType: "text/markdown") { _ in
                ResourceHandlerResponse(name: "readme", data: .text("# Hello World"))
            }
        
        let envelope = createTestEnvelope(
            method: "resources/read",
            params: ["uri": .string("file://readme.md")]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let contents)? = result["contents"],
              case .object(let content)? = contents.first else {
            #expect(Bool(false), "Expected resource content")
            return
        }
        
        #expect(content["uri"]?.string == "file://readme.md")
        #expect(content["mimeType"]?.string == "text/markdown")
        #expect(content["text"]?.string == "# Hello World")
    }
    
    @Test("Resource read extracts parameters from URI")
    func testResourceReadExtractsParametersFromURI() async throws {
        var capturedParams: Params?
        
        let server = Server()
            .addResource("file://{category}/{filename}", name: "files", description: "Files", mimeType: "text/plain") { request in
                capturedParams = request.resourceParams
                let category = request.resourceParams.string("category") ?? "unknown"
                let filename = request.resourceParams.string("filename") ?? "unknown"
                return ResourceHandlerResponse(name: filename, data: .text("Category: \(category), File: \(filename)"))
            }
        
        let envelope = createTestEnvelope(
            method: "resources/read",
            params: ["uri": .string("file://docs/readme.txt")]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        #expect(capturedParams?.string("category") == "docs")
        #expect(capturedParams?.string("filename") == "readme.txt")
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let contents)? = result["contents"],
              case .object(let content)? = contents.first else {
            #expect(Bool(false), "Expected resource content")
            return
        }
        
        #expect(content["text"]?.string == "Category: docs, File: readme.txt")
    }
    
    @Test("Resource read passes path parameters to handler")
    func testResourceReadPassesPathParametersToHandler() async throws {
        var capturedPathParams: Params?
        var capturedResourceParams: Params?
        
        let server = Server()
            .addResource("data://{itemId}", name: "data", description: "Data", mimeType: "application/json") { request in
                capturedPathParams = request.pathParams
                capturedResourceParams = request.resourceParams
                let customerId = request.pathParams?.string("customerId") ?? "unknown"
                let itemId = request.resourceParams.string("itemId") ?? "unknown"
                return ResourceHandlerResponse(name: itemId, data: .text("Customer: \(customerId), Item: \(itemId)"))
            }
        
        let pathParams = try Params(.object([
            "customerId": .string("cust-456")
        ]))
        
        let envelope = createTestEnvelope(
            method: "resources/read",
            params: ["uri": .string("data://item-789")]
        )
        
        let _: JSONValue = try await server.handleRequest(envelope, pathParams: pathParams, logger: createLogger())
        
        #expect(capturedPathParams?.string("customerId") == "cust-456")
        #expect(capturedResourceParams?.string("itemId") == "item-789")
    }
    
    @Test("Resource read returns error for nonexistent resource")
    func testResourceReadReturnsErrorForNonexistentResource() async throws {
        let server = Server()
            .addResource("file://exists", name: "exists", description: "Exists", mimeType: "text/plain") { _ in
                ResourceHandlerResponse(name: "exists", data: .text("content"))
            }
        
        let envelope = createTestEnvelope(
            method: "resources/read",
            params: ["uri": .string("file://nonexistent")]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let error)? = obj["error"],
              case .string(let message)? = error["message"] else {
            #expect(Bool(false), "Expected error response")
            return
        }
        
        #expect(message == "Resource not found")
    }
    
    @Test("Resource read returns error for missing URI parameter")
    func testResourceReadReturnsErrorForMissingURI() async throws {
        let server = Server()
        
        let envelope = createTestEnvelope(
            method: "resources/read",
            params: [:]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let error)? = obj["error"] else {
            #expect(Bool(false), "Expected error response")
            return
        }
        
        #expect(error["message"]?.string == "Invalid params")
    }
    
    // MARK: - Prompt Registration Tests
    
    @Test("Add prompt returns self for chaining")
    func testAddPromptReturnsServer() {
        let server = Server()
        let result = server.addPrompt("test", description: "Test") { _ in
            PromptHandlerResponse(messages: [])
        }
        #expect(result === server)
    }
    
    @Test("Multiple prompts can be registered")
    func testMultiplePromptsCanBeRegistered() async throws {
        let server = Server()
            .addPrompt("prompt1", description: "First") { _ in
                PromptHandlerResponse(messages: [])
            }
            .addPrompt("prompt2", description: "Second") { _ in
                PromptHandlerResponse(messages: [])
            }
        
        let envelope = createTestEnvelope(method: "prompts/list")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let prompts)? = result["prompts"] else {
            #expect(Bool(false), "Expected prompts list")
            return
        }
        
        #expect(prompts.count == 2)
    }
    
    // MARK: - Prompts List Tests
    
    @Test("Prompts list returns empty array when no prompts registered")
    func testPromptsListReturnsEmptyArray() async throws {
        let server = Server()
        let envelope = createTestEnvelope(method: "prompts/list")
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let prompts)? = result["prompts"] else {
            #expect(Bool(false), "Expected valid prompts/list response")
            return
        }
        
        #expect(prompts.isEmpty)
    }
    
    @Test("Prompts list returns registered prompts with arguments")
    func testPromptsListReturnsRegisteredPromptsWithArguments() async throws {
        let server = Server()
            .addPrompt(
                "code_review",
                description: "Review code",
                arguments: [
                    PromptArgument(name: "code", description: "Code to review", required: true),
                    PromptArgument(name: "language", description: "Programming language", required: false)
                ]
            ) { _ in
                PromptHandlerResponse(messages: [])
            }
        
        let envelope = createTestEnvelope(method: "prompts/list")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let prompts)? = result["prompts"],
              case .object(let prompt)? = prompts.first else {
            #expect(Bool(false), "Expected prompts list")
            return
        }
        
        #expect(prompt["name"]?.string == "code_review")
        #expect(prompt["description"]?.string == "Review code")
        
        if case .array(let args)? = prompt["arguments"] {
            #expect(args.count == 2)
            
            if case .object(let arg1)? = args.first {
                #expect(arg1["name"]?.string == "code")
                #expect(arg1["required"]?.bool == true)
            }
        }
    }
    
    // MARK: - Prompts Get Tests
    
    @Test("Prompt get executes handler and returns messages")
    func testPromptGetExecutesHandlerAndReturnsMessages() async throws {
        let server = Server()
            .addPrompt("greeting", description: "Generate greeting") { request in
                let name = request.arguments.string("name") ?? "stranger"
                return PromptHandlerResponse(messages: [
                    PromptMessage(role: .assistant, content: .text("You are a friendly assistant")),
                    PromptMessage(role: .user, content: .text("Hello, \(name)!"))
                ])
            }
        
        let envelope = createTestEnvelope(
            method: "prompts/get",
            params: [
                "name": .string("greeting"),
                "arguments": .object([
                    "name": .string("Alice")
                ])
            ]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let result)? = obj["result"],
              case .array(let messages)? = result["messages"] else {
            #expect(Bool(false), "Expected prompt messages")
            return
        }
        
        #expect(messages.count == 2)
        
        if case .object(let msg1)? = messages.first {
            #expect(msg1["role"]?.string == "assistant")
        }
        
        if case .object(let msg2)? = messages.last {
            #expect(msg2["role"]?.string == "user")
            if case .object(let content)? = msg2["content"] {
                #expect(content["text"]?.string == "Hello, Alice!")
            }
        }
    }
    
    @Test("Prompt get passes path parameters to handler")
    func testPromptGetPassesPathParametersToHandler() async throws {
        var capturedPathParams: Params?
        
        let server = Server()
            .addPrompt("customer_prompt", description: "Customer prompt") { request in
                capturedPathParams = request.pathParams
                let customerId = request.pathParams?.string("customerId") ?? "unknown"
                return PromptHandlerResponse(messages: [
                    PromptMessage(role: .user, content: .text("Customer: \(customerId)"))
                ])
            }
        
        let pathParams = try Params(.object([
            "customerId": .string("cust-999")
        ]))
        
        let envelope = createTestEnvelope(
            method: "prompts/get",
            params: [
                "name": .string("customer_prompt"),
                "arguments": .object([:])
            ]
        )
        
        let _: JSONValue = try await server.handleRequest(envelope, pathParams: pathParams, logger: createLogger())
        
        #expect(capturedPathParams?.string("customerId") == "cust-999")
    }
    
    @Test("Prompt get returns error for nonexistent prompt")
    func testPromptGetReturnsErrorForNonexistentPrompt() async throws {
        let server = Server()
            .addPrompt("existing", description: "Existing") { _ in
                PromptHandlerResponse(messages: [])
            }
        
        let envelope = createTestEnvelope(
            method: "prompts/get",
            params: [
                "name": .string("nonexistent"),
                "arguments": .object([:])
            ]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let error)? = obj["error"],
              case .string(let message)? = error["message"] else {
            #expect(Bool(false), "Expected error response")
            return
        }
        
        #expect(message == "Prompt not found")
    }
    
    @Test("Prompt get returns error for missing prompt name")
    func testPromptGetReturnsErrorForMissingPromptName() async throws {
        let server = Server()
        
        let envelope = createTestEnvelope(
            method: "prompts/get",
            params: [
                "arguments": .object([:])
            ]
        )
        
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let error)? = obj["error"] else {
            #expect(Bool(false), "Expected error response")
            return
        }
        
        #expect(error["message"]?.string == "Invalid params")
    }
    
    // MARK: - Method Not Found Tests
    
    @Test("Unknown method returns method not found error")
    func testUnknownMethodReturnsMethodNotFoundError() async throws {
        let server = Server()
        
        let envelope = createTestEnvelope(method: "unknown/method")
        let response: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        guard case .object(let obj) = response,
              case .object(let error)? = obj["error"],
              case .int(let code)? = error["code"],
              case .string(let message)? = error["message"] else {
            #expect(Bool(false), "Expected error response")
            return
        }
        
        #expect(code == -32601) // Method not found error code
        #expect(message == "Method not found")
    }
    
    // MARK: - Logger Context Tests
    
    @Test("Tool handler receives request-scoped logger")
    func testToolHandlerReceivesRequestScopedLogger() async throws {
        var capturedLogger: Logger?
        
        let server = Server()
            .addTool("logging_tool", description: "Test logger", inputType: SimpleInput.self, outputType: SimpleOutput.self) { request in
                capturedLogger = request.logger
                return SimpleOutput(result: "ok", processed: true)
            }
        
        let envelope = createTestEnvelope(
            method: "tools/call",
            params: [
                "name": .string("logging_tool"),
                "arguments": .object([
                    "message": .string("test"),
                    "count": .int(1)
                ])
            ],
            id: "request-123"
        )
        
        let _: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        #expect(capturedLogger != nil)
        // Logger should have request metadata
        #expect(capturedLogger?.handler.metadata["mcpRequestId"] != nil)
        #expect(capturedLogger?.handler.metadata["mcpMethod"] != nil)
    }
    
    @Test("Prompt handler receives request-scoped logger")
    func testPromptHandlerReceivesRequestScopedLogger() async throws {
        var capturedLogger: Logger?
        
        let server = Server()
            .addPrompt("logging_prompt", description: "Test logger") { request in
                capturedLogger = request.logger
                return PromptHandlerResponse(messages: [])
            }
        
        let envelope = createTestEnvelope(
            method: "prompts/get",
            params: [
                "name": .string("logging_prompt"),
                "arguments": .object([:])
            ],
            id: "prompt-request-456"
        )
        
        let _: JSONValue = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger())
        
        #expect(capturedLogger != nil)
        #expect(capturedLogger?.handler.metadata["mcpRequestId"] != nil)
        #expect(capturedLogger?.handler.metadata["mcpMethod"] != nil)
    }
    
    // MARK: - Data Response Tests
    
    @Test("Handle request returns Data")
    func testHandleRequestReturnsData() async throws {
        let server = Server()
        
        let envelope = createTestEnvelope(method: "initialize")
        let data = try await server.handleRequest(envelope, pathParams: nil, logger: createLogger()) as Data
        
        #expect(!data.isEmpty)
        
        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["result"] != nil)
    }
}
