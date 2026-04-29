import Testing
import Foundation
import Logging
@testable import JSONValueCoding
@testable import MCP

@Suite("ToolHandlerRequest is Sendable when Input is")
struct ToolHandlerRequestSendabilityTests {

    @JSONSchema
    struct EmptyInput: Codable {}

    @JSONSchema
    struct StringInput: Codable {
        let value: String
    }

    /// Compile-time conformance check. If `ToolHandlerRequest<Input>` ever
    /// loses Sendability for a Sendable Input, this file won't compile and
    /// the test file fails to build — making the test fail.
    private func requireSendable<T: Sendable>(_: T.Type) {}

    @Test("ToolHandlerRequest<EmptyInput>: Sendable")
    func emptyInputSendable() {
        requireSendable(ToolHandlerRequest<EmptyInput>.self)
        #expect(true)
    }

    @Test("ToolHandlerRequest<StringInput>: Sendable")
    func stringInputSendable() {
        requireSendable(ToolHandlerRequest<StringInput>.self)
        #expect(true)
    }

    @Test("MCPContext + RequestId + Params are Sendable")
    func componentsSendable() {
        requireSendable(MCPContext.self)
        requireSendable(RequestId.self)
        requireSendable(Params.self)
        #expect(true)
    }

    /// The whole point of the change: a tool body should be able to capture
    /// `request` into a nested `@Sendable` closure (e.g. `Task { ... }`,
    /// `withConnection { ... }`) without the compiler complaining. Compiling
    /// this test is the assertion.
    @Test("Captured into nested @Sendable closure")
    func capturedInNestedSendableClosure() async throws {
        let server = Server().addTool(
            "echo",
            description: "echo",
            inputType: StringInput.self,
            outputType: StringInput.self
        ) { request in
            // The capture below would fail to compile under the old
            // (non-Sendable) ToolHandlerRequest.
            try await Task.detached {
                _ = request.input.value
            }.value
            return request.input
        }
        let result = try await server.executeTool(
            name: "echo",
            argumentsJSON: #"{"value":"hi"}"#
        )
        #expect(result.contains(#""value":"hi""#))
    }
}
