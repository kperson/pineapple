import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Input/Output Protocols

/// Protocol for reading input lines (abstracts stdin)
///
/// This protocol allows testing of stdio-based code by providing a way to inject
/// mock input sources instead of relying on actual stdin.
///
/// ## Usage
///
/// Production code uses `StandardInputReader` which reads from actual stdin:
/// ```swift
/// let reader = StandardInputReader()
/// while let line = try await reader.readLine() {
///     // Process line
/// }
/// ```
///
/// Test code uses `MockInputReader` with predefined lines:
/// ```swift
/// let reader = MockInputReader(lines: ["line1", "line2"])
/// while let line = try await reader.readLine() {
///     // Will return "line1", then "line2", then nil
/// }
/// ```
public protocol InputReader: Sendable {
    /// Read the next line of input
    ///
    /// Returns `nil` when the input stream is closed or reaches end-of-file.
    /// This is an async method to allow for flexible input sources (network, files, etc.)
    /// even though stdin itself is blocking.
    ///
    /// - Returns: The next line as a String, or nil if no more input is available
    /// - Throws: If an error occurs while reading input
    func readLine() async throws -> String?
}

/// Protocol for writing output lines (abstracts stdout)
///
/// This protocol allows testing of stdio-based code by providing a way to capture
/// output instead of writing to actual stdout.
///
/// ## Usage
///
/// Production code uses `StandardOutputWriter` which writes to actual stdout:
/// ```swift
/// let writer = StandardOutputWriter()
/// try await writer.writeLine("Hello")
/// try await writer.flush()
/// ```
///
/// Test code uses `MockOutputWriter` to capture output:
/// ```swift
/// let writer = MockOutputWriter()
/// try await writer.writeLine("Hello")
/// #expect(writer.writtenLines == ["Hello"])
/// ```
public protocol OutputWriter: Sendable {
    /// Write a line to the output stream
    ///
    /// The line should not include a trailing newline - it will be added automatically.
    ///
    /// - Parameter line: The line to write
    /// - Throws: If an error occurs while writing
    func writeLine(_ line: String) async throws
    
    /// Flush the output buffer
    ///
    /// Ensures all buffered output is written to the underlying stream.
    /// Important for stdio to ensure the client receives responses immediately.
    ///
    /// - Throws: If an error occurs while flushing
    func flush() async throws
}

// MARK: - Production Implementations

/// Standard input reader that reads from stdin
///
/// This is the production implementation used by `StdioAdapter` in normal operation.
/// It wraps Swift's built-in `readLine()` function, making it available through the
/// `InputReader` protocol for dependency injection.
///
/// ## Thread Safety
///
/// The `readLine()` call is blocking, but we wrap it in `Task.detached` to avoid
/// blocking the cooperative thread pool. This is safe because stdin reading is
/// inherently sequential.
///
/// ## Example
///
/// ```swift
/// let reader = StandardInputReader()
/// let adapter = StdioAdapter(
///     server: server,
///     inputReader: reader,
///     outputWriter: StandardOutputWriter()
/// )
/// try await adapter.run()
/// ```
public final class StandardInputReader: InputReader {
    
    /// Create a new standard input reader
    public init() {}
    
    /// Read the next line from stdin
    ///
    /// This method wraps Swift's `readLine()` in a detached task to avoid blocking
    /// the cooperative thread pool. The underlying `readLine()` is still blocking
    /// at the system level, but this prevents Swift concurrency warnings.
    ///
    /// - Returns: The next line from stdin, or nil when stdin is closed
    public func readLine() async throws -> String? {
        return await Task.detached {
            Swift.readLine()
        }.value
    }
}

/// Standard output writer that writes to stdout
///
/// This is the production implementation used by `StdioAdapter` in normal operation.
/// It wraps Swift's `print()` function and FileHandle synchronization, making them
/// available through the `OutputWriter` protocol for dependency injection.
///
/// ## Buffering
///
/// Output is line-buffered by default. Call `flush()` after each write to ensure
/// the client receives responses immediately (important for JSON-RPC over stdio).
///
/// ## Example
///
/// ```swift
/// let writer = StandardOutputWriter()
/// let adapter = StdioAdapter(
///     server: server,
///     inputReader: StandardInputReader(),
///     outputWriter: writer
/// )
/// try await adapter.run()
/// ```
public final class StandardOutputWriter: OutputWriter {
    
    /// Create a new standard output writer
    public init() {}
    
    /// Write a line to stdout
    ///
    /// Writes the line using Swift's `print()` function, which automatically
    /// adds a newline character.
    ///
    /// - Parameter line: The line to write (without trailing newline)
    public func writeLine(_ line: String) async throws {
        print(line)
        // Immediately flush to ensure output is sent
        try await flush()
    }
    
    /// Flush stdout buffer
    ///
    /// Ensures all buffered output is written to stdout immediately.
    /// This is critical for JSON-RPC over stdio to ensure clients receive
    /// responses without delay.
    public func flush() async throws {
        #if canImport(Darwin)
        // On macOS, use fflush directly
        _ = Darwin.fflush(Darwin.stdout)
        #else
        // On Linux, try FileHandle.synchronizeFile() and gracefully handle errors
        // This will work in most cases except when stdout is a pipe
        do {
            try FileHandle.standardOutput.synchronize()
        } catch {
            // If synchronize fails (e.g., stdout is a pipe), that's okay
            // The output has already been written by print()
        }
        #endif
    }
}
