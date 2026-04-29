import Testing
import Foundation
@testable import JSONValueCoding
@testable import MCP

@Suite("Server defaults to ISO 8601 dates")
struct ServerDateEncodingTests {

    @JSONSchema
    struct EchoInput: Codable, Sendable {
        let when: Date
    }

    @JSONSchema
    struct EchoOutput: Codable, Sendable {
        let echoed: Date
    }

    private func buildServer() -> Server {
        Server().addTool(
            "echo",
            description: "echo the date back",
            inputType: EchoInput.self,
            outputType: EchoOutput.self
        ) { request in
            EchoOutput(echoed: request.input.when)
        }
    }

    @Test("ISO 8601 input round-trips through executeTool")
    func iso8601RoundTrip() async throws {
        let server = buildServer()
        let result = try await server.executeTool(
            name: "echo",
            argumentsJSON: #"{"when":"2026-04-28T15:30:00Z"}"#
        )
        #expect(result.contains(#""echoed":"2026-04-28T15:30:00Z""#),
                "expected ISO 8601 in result, got: \(result)")
    }

    @Test("Fractional-seconds input is also accepted")
    func iso8601FractionalAccepted() async throws {
        let server = buildServer()
        let result = try await server.executeTool(
            name: "echo",
            argumentsJSON: #"{"when":"2026-04-28T15:30:00.123Z"}"#
        )
        // Output drops fractional seconds — the round-trip normalizes.
        #expect(result.contains("\"echoed\":\"2026-04-28T15:30:00"),
                "expected 2026-04-28 prefix in result, got: \(result)")
    }

    @Test("Numeric reference-date seconds is rejected")
    func numericInputRejected() async throws {
        let server = buildServer()
        await #expect(throws: (any Error).self) {
            _ = try await server.executeTool(
                name: "echo",
                argumentsJSON: #"{"when":799109055}"#
            )
        }
    }

    @Test("Bare String through JSONValueEncoder/Decoder round-trips Date as iso8601")
    func directCoderRoundTrip() throws {
        let encoder = JSONValueEncoder()
        let decoder = JSONValueDecoder()
        // Use a fixed ISO date so we can compare without timezone drift.
        let original = ISO8601DateFormatter().date(from: "2026-04-28T15:30:00Z")!
        let encoded = try encoder.encode(original)
        guard case .string(let s) = encoded else {
            Issue.record("expected .string from Date encode, got \(encoded)")
            return
        }
        #expect(s == "2026-04-28T15:30:00Z")
        let decoded: Date = try decoder.decode(Date.self, from: encoded)
        #expect(decoded == original)
    }
}
