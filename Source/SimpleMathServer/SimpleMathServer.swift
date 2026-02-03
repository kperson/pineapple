import MCP
import Foundation

/// Input type for the add_numbers tool
///
/// Takes two numbers and returns their sum.
@JSONSchema
public struct AddNumbersInput: Codable {
    /// First number to add
    public let a: Double
    
    /// Second number to add
    public let b: Double
    
    public init(a: Double, b: Double) {
        self.a = a
        self.b = b
    }
}

/// Output type for the add_numbers tool
///
/// Contains the sum of two numbers.
@JSONSchema
public struct AddNumbersOutput: Codable {
    /// The sum of the two input numbers
    public let sum: Double
    
    public init(sum: Double) {
        self.sum = sum
    }
}

/// Creates a simple math server for testing and demonstration purposes
///
/// This server provides basic mathematical operations and constants, making it
/// ideal for testing MCP adapters (Lambda, Hummingbird, Stdio) and demonstrating
/// the MCP protocol with minimal complexity.
///
/// ## Features
///
/// **Tool: `add_numbers`**
/// - Adds two numbers together
/// - Input: `{ "a": 5.0, "b": 3.0 }`
/// - Output: `{ "sum": 8.0 }`
///
/// **Resource: `math://constants/pi`**
/// - Returns the value of pi (3.14159)
/// - URI: `math://constants/pi`
/// - Content-Type: `text/plain`
///
/// **Prompt: `explain_math`**
/// - Generates a prompt to explain a mathematical concept
/// - Argument: `concept` (required) - The math concept to explain
/// - Returns: A message asking for an explanation of the concept
///
/// ## Example Usage
///
/// ```swift
/// // Create the server
/// let server = createSimpleMathServer()
///
/// // Use with Hummingbird HTTP adapter
/// let app = MCPHummingbird.App { adapter, router in
///     router.addServer(path: "/math", server: server)
/// }
/// try await app.run()
///
/// // Use with Lambda adapter
/// let mcpApp = MCPLambda.App { adapter, router in
///     router.addServer(path: "/math", server: server)
/// }
/// let lambdaApp = LambdaApp()
///     .addMCP(key: "math", mcpApp: mcpApp)
/// lambdaApp.run(handlerKey: "math")
///
/// // Use with Stdio adapter
/// let stdioApp = MCPStdio.App { adapter, router in
///     router.addServer(path: "/math", server: server)
/// }
/// try await stdioApp.run(path: "/math")
/// ```
///
/// ## Testing
///
/// This server is designed to be used in adapter tests:
///
/// ```swift
/// func testAdapterWithSimpleMathServer() async throws {
///     let server = createSimpleMathServer()
///     // Test tool call
///     let result = try await callTool(server, "add_numbers", input: AddNumbersInput(a: 2, b: 3))
///     #expect(result.sum == 5.0)
/// }
/// ```
///
/// - Returns: A configured MCP Server instance
public func createSimpleMathServer() -> Server {
    Server()
        .addTool(
            "add_numbers",
            description: "Adds two numbers together and returns the sum",
            inputType: AddNumbersInput.self,
            outputType: AddNumbersOutput.self
        ) { request in
            let sum = request.input.a + request.input.b
            return AddNumbersOutput(sum: sum)
        }
        .addResource(
            "math://constants/pi",
            name: "pi_constant",
            description: "The mathematical constant pi (π) - the ratio of a circle's circumference to its diameter",
            mimeType: MimeType.textPlain
        ) { request in
            ResourceHandlerResponse(
                name: "pi",
                data: .text("3.14159")
            )
        }
        .addPrompt(
            "explain_math",
            description: "Generates a prompt to request an explanation of a mathematical concept",
            arguments: [
                PromptArgument(
                    name: "concept",
                    description: "The mathematical concept to explain (e.g., 'derivatives', 'fibonacci sequence', 'pythagorean theorem')",
                    required: true
                )
            ]
        ) { request in
            let concept = try request.argumentOrThrow("concept")
            return PromptHandlerResponse(
                messages: [
                    PromptMessage(
                        role: .user,
                        content: .text("Please explain the mathematical concept: \(concept)")
                    )
                ]
            )
        }
}
