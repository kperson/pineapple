import Testing
import Foundation
import Logging
import JSONValueCoding
@testable import MCP

@Suite("Server OpenAI Integration Tests")
struct ServerOpenAITests {

    // MARK: - Test Types

    @JSONSchema
    struct EmptyInput: Codable {}

    @JSONSchema
    struct TimeOutput: Codable {
        let iso8601: String
        let epochSeconds: Double
    }

    @JSONSchema
    struct ScheduleInput: Codable {
        let predicate: String
        let task: String
    }

    @JSONSchema
    struct ScheduleOutput: Codable {
        let id: String
    }

    @JSONSchema
    struct MathInput: Codable {
        let a: Double
        let b: Double
    }

    @JSONSchema
    struct MathOutput: Codable {
        let sum: Double
    }

    // MARK: - openAIToolDefinitions Tests

    @Test("openAIToolDefinitions returns empty array when no tools registered")
    func testOpenAIToolDefinitionsEmpty() {
        let server = Server()
        let definitions = server.openAIToolDefinitions()
        #expect(definitions.isEmpty)
    }

    @Test("openAIToolDefinitions returns correct format for single tool")
    func testOpenAIToolDefinitionsSingleTool() {
        let server = Server()
            .addTool("add_numbers", description: "Adds two numbers", inputType: MathInput.self, outputType: MathOutput.self) { request in
                MathOutput(sum: request.input.a + request.input.b)
            }

        let definitions = server.openAIToolDefinitions()
        #expect(definitions.count == 1)

        let def = definitions[0]
        #expect(def["type"] as? String == "function")

        guard let function = def["function"] as? [String: Any] else {
            #expect(Bool(false), "Expected function dict")
            return
        }

        #expect(function["name"] as? String == "add_numbers")
        #expect(function["description"] as? String == "Adds two numbers")
        #expect(function["strict"] as? Bool == true)

        guard let parameters = function["parameters"] as? [String: Any] else {
            #expect(Bool(false), "Expected parameters dict")
            return
        }

        #expect(parameters["type"] as? String == "object")

        guard let properties = parameters["properties"] as? [String: Any] else {
            #expect(Bool(false), "Expected properties dict")
            return
        }

        #expect(properties["a"] != nil)
        #expect(properties["b"] != nil)
    }

    @Test("openAIToolDefinitions returns multiple tools")
    func testOpenAIToolDefinitionsMultipleTools() {
        let server = Server()
            .addTool("tool_a", description: "First tool", inputType: EmptyInput.self, outputType: TimeOutput.self) { _ in
                TimeOutput(iso8601: "2026-01-01T00:00:00Z", epochSeconds: 0)
            }
            .addTool("tool_b", description: "Second tool", inputType: MathInput.self, outputType: MathOutput.self) { request in
                MathOutput(sum: request.input.a + request.input.b)
            }

        let definitions = server.openAIToolDefinitions()
        #expect(definitions.count == 2)

        let names = definitions.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        #expect(names.contains("tool_a"))
        #expect(names.contains("tool_b"))
    }

    @Test("openAIToolDefinitions includes empty input schema correctly")
    func testOpenAIToolDefinitionsEmptyInputSchema() {
        let server = Server()
            .addTool("no_args", description: "No arguments", inputType: EmptyInput.self, outputType: TimeOutput.self) { _ in
                TimeOutput(iso8601: "now", epochSeconds: 0)
            }

        let definitions = server.openAIToolDefinitions()
        guard let function = definitions.first?["function"] as? [String: Any],
              let parameters = function["parameters"] as? [String: Any] else {
            #expect(Bool(false), "Expected parameters")
            return
        }

        #expect(parameters["type"] as? String == "object")
    }

    @Test("openAIToolDefinitions parameters are JSONSerialization-compatible")
    func testOpenAIToolDefinitionsSerializable() throws {
        let server = Server()
            .addTool("test_tool", description: "Test", inputType: MathInput.self, outputType: MathOutput.self) { request in
                MathOutput(sum: request.input.a + request.input.b)
            }

        let definitions = server.openAIToolDefinitions()

        // Should be serializable to JSON without error
        let data = try JSONSerialization.data(withJSONObject: definitions)
        #expect(!data.isEmpty)

        // Round-trip: deserialize back
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(parsed?.count == 1)
        #expect((parsed?[0]["function"] as? [String: Any])?["name"] as? String == "test_tool")
    }

    // MARK: - executeTool Tests

    @Test("executeTool executes tool and returns result")
    func testExecuteToolReturnsResult() async throws {
        let server = Server()
            .addTool("add", description: "Add numbers", inputType: MathInput.self, outputType: MathOutput.self) { request in
                MathOutput(sum: request.input.a + request.input.b)
            }

        let result = try await server.executeTool(name: "add", argumentsJSON: #"{"a": 3.5, "b": 2.5}"#)

        // Result should be JSON text containing the sum
        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["sum"] as? Double == 6.0)
    }

    @Test("executeTool throws for nonexistent tool")
    func testExecuteToolThrowsForNonexistentTool() async throws {
        let server = Server()

        do {
            _ = try await server.executeTool(name: "nonexistent", argumentsJSON: "{}")
            #expect(Bool(false), "Should have thrown")
        } catch let error as MCPError {
            #expect(error.message.contains("not found"))
        }
    }

    @Test("executeTool handles empty arguments")
    func testExecuteToolHandlesEmptyArguments() async throws {
        let server = Server()
            .addTool("get_time", description: "Get time", inputType: EmptyInput.self, outputType: TimeOutput.self) { _ in
                TimeOutput(iso8601: "2026-03-19T00:00:00Z", epochSeconds: 1774070400)
            }

        let result = try await server.executeTool(name: "get_time", argumentsJSON: "{}")

        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["iso8601"] as? String == "2026-03-19T00:00:00Z")
        #expect(json["epochSeconds"] as? Double == 1774070400)
    }

    @Test("executeTool handles integer arguments")
    func testExecuteToolHandlesIntegerArguments() async throws {
        let server = Server()
            .addTool("add", description: "Add", inputType: MathInput.self, outputType: MathOutput.self) { request in
                MathOutput(sum: request.input.a + request.input.b)
            }

        let result = try await server.executeTool(name: "add", argumentsJSON: #"{"a": 10, "b": 20}"#)

        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["sum"] as? Double == 30.0)
    }

    @Test("executeTool handles string fields")
    func testExecuteToolHandlesStringFields() async throws {
        let server = Server()
            .addTool("schedule", description: "Schedule task", inputType: ScheduleInput.self, outputType: ScheduleOutput.self) { request in
                #expect(request.input.predicate == "unix_epoch_time >= 1000")
                #expect(request.input.task == "takeAPicture")
                return ScheduleOutput(id: "task-123")
            }

        let result = try await server.executeTool(
            name: "schedule",
            argumentsJSON: #"{"predicate": "unix_epoch_time >= 1000", "task": "takeAPicture"}"#
        )

        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["id"] as? String == "task-123")
    }

    @Test("executeTool works with rich content handler")
    func testExecuteToolWithRichContentHandler() async throws {
        let server = Server()
            .addTool("greet", description: "Greet", inputType: ScheduleInput.self) { request in
                ToolHandlerResponse.text("Hello from \(request.input.task)!")
            }

        let result = try await server.executeTool(
            name: "greet",
            argumentsJSON: #"{"predicate": "always", "task": "greeter"}"#
        )

        #expect(result == "Hello from greeter!")
    }

    @Test("executeTool handles malformed JSON gracefully")
    func testExecuteToolHandlesMalformedJSON() async throws {
        let server = Server()
            .addTool("no_args", description: "No args", inputType: EmptyInput.self, outputType: TimeOutput.self) { _ in
                TimeOutput(iso8601: "now", epochSeconds: 0)
            }

        // Malformed JSON falls back to empty object, which should work for EmptyInput
        let result = try await server.executeTool(name: "no_args", argumentsJSON: "not json at all")
        #expect(!result.isEmpty)
    }
}
