import Testing
import Foundation
@testable import JSONValueCoding
@testable import MCP

@Suite("@JSONSchema auto-adds Sendable")
struct JSONSchemaSendableTests {

    // The compile-time check below is the actual test. If the macro stops
    // emitting Sendable for any reason, this file will not compile.
    @JSONSchema
    struct Foo: Codable {
        let x: Int
    }

    @JSONSchema
    struct Nested: Codable {
        let foo: Foo
        let when: Date
    }

    /// Generic constraint forces the compiler to verify `T: Sendable`. If
    /// the type isn't Sendable, the build fails — making this test fail at
    /// compile time, not runtime.
    private func requireSendable<T: Sendable>(_: T.Type) {}

    @Test("@JSONSchema struct conforms to Sendable")
    func fooIsSendable() {
        requireSendable(Foo.self)
        requireSendable(Nested.self)
        // Reach the assertion so Swift Testing reports a passed test.
        #expect(true)
    }
}
