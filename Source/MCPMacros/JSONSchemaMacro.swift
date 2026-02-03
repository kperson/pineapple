import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct JSONSchemaMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        // Only work with structs
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.notAStruct
        }
        
        // Check if the struct is public
        let isPublic = structDecl.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.public)
        }
        
        // Find stored properties
        let properties = structDecl.memberBlock.members.compactMap { member -> (String, String, Bool)? in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                return nil
            }
            
            let propertyName = identifier.identifier.text
            let isOptional = binding.typeAnnotation?.type.is(OptionalTypeSyntax.self) ?? false
            let swiftType = extractSwiftType(from: binding.typeAnnotation?.type)
            
            return (propertyName, swiftType, isOptional)
        }
        
        // Generate schema properties using DSL
        let schemaProperties = properties.map { (name, swiftType, isOptional) in
            let schemaType = swiftTypeToSchemaType(swiftType, isOptional: isOptional)
            return "            \"\(name)\": \(schemaType)"
        }.joined(separator: ",\n")
        
        let requiredProperties = properties.compactMap { (name, _, isOptional) in
            isOptional ? nil : "\"\(name)\""
        }.joined(separator: ", ")
        
        // Add 'public' modifier if the struct is public
        let accessModifier = isPublic ? "public " : ""
        
        let schemaCode = """
        \(accessModifier)static let jsonSchema = JSONValue([
            "type": "object",
            "properties": [
            \(schemaProperties)
            ],
            "required": [\(requiredProperties)]
        ])
        """
        
        return [DeclSyntax(stringLiteral: schemaCode)]
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let extensionDecl = try ExtensionDeclSyntax("extension \(type): JSONSchemaProvider {}")
        return [extensionDecl]
    }
    
    private static func extractSwiftType(from typeAnnotation: TypeSyntax?) -> String {
        guard let typeAnnotation = typeAnnotation else { return "Any" }
        
        if let optionalType = typeAnnotation.as(OptionalTypeSyntax.self) {
            return extractSwiftType(from: optionalType.wrappedType)
        }
        
        if let identifierType = typeAnnotation.as(IdentifierTypeSyntax.self) {
            return identifierType.name.text
        }
        
        // Return the full type description for arrays and other complex types
        return typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func swiftTypeToSchemaType(_ swiftType: String, isOptional: Bool) -> String {
        let baseType: String
        
        if swiftType.hasPrefix("[") {
            let elementType = extractArrayElementType(swiftType)
            baseType = "[\"type\": \"array\", \"items\": \(swiftTypeToSchemaType(elementType, isOptional: false))]"
        } else {
            baseType = switch swiftType {
            case "String": "[\"type\": \"string\"]"
            case "Int", "Int32", "Int64": "[\"type\": \"integer\"]"
            case "Double", "Float": "[\"type\": \"number\"]"
            case "Bool": "[\"type\": \"boolean\"]"
            default: 
                // Reference the nested type's schema
                "\(swiftType).jsonSchema"
            }
        }
        
        return baseType
    }
    
    private static func extractArrayElementType(_ arrayType: String) -> String {
        // Handle [Type] syntax
        if arrayType.hasPrefix("[") && arrayType.hasSuffix("]") {
            let inner = String(arrayType.dropFirst().dropLast())
            return inner
        }
        return "String" // fallback
    }
}

enum MacroError: Error, CustomStringConvertible {
    case notAStruct
    
    var description: String {
        switch self {
        case .notAStruct:
            return "@JSONSchema can only be applied to structs"
        }
    }
}
