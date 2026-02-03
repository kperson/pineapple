import Foundation
@testable import MCPStdio

/// Mock input reader for testing
///
/// Provides predefined lines of input without requiring actual stdin.
/// Useful for testing stdio-based code in a controlled environment.
///
/// ## Example
///
/// ```swift
/// let input = MockInputReader(lines: [
///     #"{"jsonrpc":"2.0","id":"1","method":"initialize"}"#,
///     #"{"jsonrpc":"2.0","id":"2","method":"tools/list"}"#
/// ])
///
/// let adapter = StdioAdapter(
///     server: server,
///     inputReader: input,
///     outputWriter: MockOutputWriter()
/// )
///
/// try await adapter.run()
/// // Will process both requests and then exit
/// ```
actor MockInputReader: InputReader {
    private var lines: [String]
    private var currentIndex = 0
    
    /// Create a mock input reader with predefined lines
    ///
    /// - Parameter lines: Array of strings to return from readLine() calls
    init(lines: [String]) {
        self.lines = lines
    }
    
    /// Read the next line from the predefined array
    ///
    /// Returns lines in order until all are consumed, then returns nil.
    ///
    /// - Returns: Next line from the array, or nil when all lines are consumed
    func readLine() async throws -> String? {
        guard currentIndex < lines.count else { return nil }
        let line = lines[currentIndex]
        currentIndex += 1
        return line
    }
    
    /// Add more lines to the input (useful for multi-stage tests)
    ///
    /// - Parameter newLines: Lines to append to the input queue
    func addLines(_ newLines: [String]) {
        lines.append(contentsOf: newLines)
    }
    
    /// Reset the reader to the beginning
    func reset() {
        currentIndex = 0
    }
}

/// Mock output writer for testing
///
/// Captures all written lines in memory for verification in tests.
/// Useful for testing stdio-based code without writing to actual stdout.
///
/// ## Example
///
/// ```swift
/// let output = MockOutputWriter()
/// let adapter = StdioAdapter(
///     server: server,
///     inputReader: MockInputReader(lines: [...]),
///     outputWriter: output
/// )
///
/// try await adapter.run()
///
/// // Verify output
/// let lines = await output.writtenLines
/// #expect(lines.count == 2)
/// let firstResponse = try JSONDecoder().decode(Response.self, from: lines[0].data(using: .utf8)!)
/// ```
actor MockOutputWriter: OutputWriter {
    private var _writtenLines: [String] = []
    
    /// All lines written to this writer
    ///
    /// Access this property in tests to verify the output.
    var writtenLines: [String] {
        _writtenLines
    }
    
    /// Create a new mock output writer
    init() {}
    
    /// Write a line to the in-memory buffer
    ///
    /// - Parameter line: The line to capture
    func writeLine(_ line: String) async throws {
        _writtenLines.append(line)
    }
    
    /// Flush (no-op for mock)
    ///
    /// In the mock implementation, this does nothing since there's no
    /// actual buffer to flush.
    func flush() async throws {
        // No-op in tests
    }
    
    /// Clear all captured lines (useful for multi-stage tests)
    func clear() {
        _writtenLines.removeAll()
    }
    
    /// Get the last written line (convenience method)
    var lastLine: String? {
        _writtenLines.last
    }
}
