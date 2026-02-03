import Foundation
import MCP
import MCPStdio
import MCPHummingbird
import SimpleMathServer

/// Simple MCP Example Server using SimpleMathServer
///
/// This example demonstrates how to run the SimpleMathServer with different
/// transport adapters (HTTP via Hummingbird or Stdio).
///
/// ## Usage
///
/// ```bash
/// # Run with HTTP server on localhost:8080
/// swift run MCPExample http
///
/// # Run with stdio transport (for Claude Desktop integration)
/// swift run MCPExample stdio
/// ```
///
/// ## Available Features
///
/// The SimpleMathServer provides:
/// - **Tool**: `add_numbers` - Adds two numbers together
/// - **Resource**: `math://constants/pi` - Returns the value of pi
/// - **Prompt**: `explain_math` - Generates a prompt to explain a math concept
///
/// ## Testing with curl (HTTP mode)
///
/// ```bash
/// # List available tools
/// curl -X POST http://localhost:8080/math \
///   -H "Content-Type: application/json" \
///   -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'
///
/// # Call add_numbers tool
/// curl -X POST http://localhost:8080/math \
///   -H "Content-Type: application/json" \
///   -d '{
///     "jsonrpc": "2.0",
///     "method": "tools/call",
///     "params": {
///       "name": "add_numbers",
///       "arguments": {"a": 5, "b": 3}
///     },
///     "id": 2
///   }'
///
/// # Read pi constant resource
/// curl -X POST http://localhost:8080/math \
///   -H "Content-Type: application/json" \
///   -d '{
///     "jsonrpc": "2.0",
///     "method": "resources/read",
///     "params": {
///       "uri": "math://constants/pi"
///     },
///     "id": 3
///   }'
///
/// # Get explain_math prompt
/// curl -X POST http://localhost:8080/math \
///   -H "Content-Type: application/json" \
///   -d '{
///     "jsonrpc": "2.0",
///     "method": "prompts/get",
///     "params": {
///       "name": "explain_math",
///       "arguments": {"concept": "derivatives"}
///     },
///     "id": 4
///   }'
/// ```

enum ServerMode: String, CaseIterable {
    case stdio = "stdio"
    case http = "http"
}

// Parse command line arguments
let mode: ServerMode
if CommandLine.arguments.count > 1, let parsedMode = ServerMode(rawValue: CommandLine.arguments[1]) {
    mode = parsedMode
} else {
    print("Usage: MCPExample <mode>")
    print("Modes: \(ServerMode.allCases.map { $0.rawValue }.joined(separator: ", "))")
    print("")
    print("Examples:")
    print("  swift run MCPExample http   # Run HTTP server on localhost:8080")
    print("  swift run MCPExample stdio  # Run stdio transport for Claude Desktop")
    exit(1)
}

// Create the simple math server
let server = createSimpleMathServer()

// Helper to print to stderr (to avoid polluting stdout in stdio mode)
func printInfo(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let message = items.map { "\($0)" }.joined(separator: separator)
    FileHandle.standardError.write((message + terminator).data(using: .utf8)!)
}

printInfo("🧮 Simple Math MCP Server")
printInfo("📊 Mode: \(mode.rawValue)")
printInfo("")
printInfo("Features:")
printInfo("  • Tool: add_numbers - Adds two numbers together")
printInfo("  • Resource: math://constants/pi - Returns π")
printInfo("  • Prompt: explain_math - Explains math concepts")
printInfo("")

switch mode {
case .stdio:
    printInfo("🔌 Running in stdio mode (for Claude Desktop integration)")
    printInfo("💡 Add this to your Claude Desktop config:")
    printInfo("")
    printInfo("  {")
    printInfo("    \"mcpServers\": {")
    printInfo("      \"simple-math\": {")
    printInfo("        \"command\": \"swift\",")
    printInfo("        \"args\": [\"run\", \"MCPExample\", \"stdio\"]")
    printInfo("      }")
    printInfo("    }")
    printInfo("  }")
    printInfo("")
    
    let app = MCPStdio.App { adapter, router in
        router.addServer(path: "/math", server: server)
    }
    try await app.run(path: "/math")

case .http:
    printInfo("🌐 Starting HTTP server on http://localhost:8080")
    printInfo("")
    printInfo("Test with curl:")
    printInfo("  curl -X POST http://localhost:8080/math \\")
    printInfo("    -H \"Content-Type: application/json\" \\")
    printInfo("    -d '{\"jsonrpc\": \"2.0\", \"method\": \"tools/list\", \"id\": 1}'")
    printInfo("")
    
    // Create HTTP server with logging middleware
    let loggingMiddleware = PreRequestMiddlewareHelpers.from { 
        (context: HummingbirdMCPContext, envelope: TransportEnvelope) in
        context.logger.info("📥 \(envelope.mcpRequest.method)")
        return .passthrough
    }
    
    let app = MCPHummingbird.App(.init(address: .hostname("localhost", port: 8080))) { adapter, router in
        // Add global logging middleware
        adapter.usePreRequestMiddleware(loggingMiddleware)
        
        // Add the math server at /math path
        router.addServer(path: "/math", server: server)
    }
    
    try await app.run()
}
