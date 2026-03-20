import SwiftSyntax
import SwiftSyntaxMacros

/// A peer macro that produces no code — it exists only as a marker
/// that `@JSONSchema` reads during its expansion.
public struct SchemaDescriptionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // No code generation — the description is read by @JSONSchema
        return []
    }
}
