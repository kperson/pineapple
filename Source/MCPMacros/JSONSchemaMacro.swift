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
        
        // Find stored properties (name, swiftType, isOptional, description?)
        let properties = structDecl.memberBlock.members.compactMap { member -> (String, String, Bool, String?)? in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                return nil
            }

            let propertyName = identifier.identifier.text
            let isOptional = binding.typeAnnotation?.type.is(OptionalTypeSyntax.self) ?? false
            let swiftType = extractSwiftType(from: binding.typeAnnotation?.type)
            let description = extractSchemaDescription(from: varDecl)

            return (propertyName, swiftType, isOptional, description)
        }

        // Generate schema properties using DSL
        let schemaProperties = properties.map { (name, swiftType, isOptional, description) in
            let schemaType = swiftTypeToSchemaType(swiftType, isOptional: isOptional, description: description)
            return "            \"\(name)\": \(schemaType)"
        }.joined(separator: ",\n")
        
        let requiredProperties = properties.compactMap { (name, _, isOptional, _) in
            isOptional ? nil : "\"\(name)\""
        }.joined(separator: ", ")
        
        // Add 'public' modifier if the struct is public
        let accessModifier = isPublic ? "public " : ""

        // Use [:] for empty properties to ensure Swift infers a dictionary, not an array
        let propertiesLiteral = schemaProperties.isEmpty ? ":" : "\n            \(schemaProperties)\n            "

        let schemaCode = """
        \(accessModifier)static let jsonSchema = JSONValue([
            "type": "object",
            "properties": [\(propertiesLiteral)],
            "required": [\(requiredProperties)],
            "additionalProperties": false
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
    
    private static func swiftTypeToSchemaType(_ swiftType: String, isOptional: Bool, description: String? = nil) -> String {
        let baseType: String

        if swiftType.hasPrefix("[") && swiftType.contains(":") {
            // Dictionary type like [String: String] or [String: Int]
            let valueType = extractDictionaryValueType(swiftType)
            let descPart = description.map { ", \"description\": \"\($0)\"" } ?? ""
            baseType = "[\"type\": \"object\", \"additionalProperties\": \(swiftTypeToSchemaType(valueType, isOptional: false))\(descPart)]"
        } else if swiftType.hasPrefix("[") {
            let elementType = extractArrayElementType(swiftType)
            let descPart = description.map { ", \"description\": \"\($0)\"" } ?? ""
            baseType = "[\"type\": \"array\", \"items\": \(swiftTypeToSchemaType(elementType, isOptional: false))\(descPart)]"
        } else {
            let descPart = description.map { ", \"description\": \"\($0)\"" } ?? ""
            baseType = switch swiftType {
            case "String": "[\"type\": \"string\"\(descPart)]"
            case "Int", "Int32", "Int64": "[\"type\": \"integer\"\(descPart)]"
            case "Double", "Float": "[\"type\": \"number\"\(descPart)]"
            case "Bool": "[\"type\": \"boolean\"\(descPart)]"
            default:
                // Reference the nested type's schema
                if let description {
                    // Merge description into the referenced schema at runtime
                    "JSONValue.withDescription(\(swiftType).jsonSchema, \"\(description)\")"
                } else {
                    "\(swiftType).jsonSchema"
                }
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

    private static func extractSchemaDescription(from varDecl: VariableDeclSyntax) -> String? {
        for attribute in varDecl.attributes {
            guard let attr = attribute.as(AttributeSyntax.self),
                  let identifierType = attr.attributeName.as(IdentifierTypeSyntax.self),
                  identifierType.name.text == "SchemaDescription",
                  let arguments = attr.arguments?.as(LabeledExprListSyntax.self),
                  let firstArg = arguments.first,
                  let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
                  let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) else {
                continue
            }
            return segment.content.text
        }
        return nil
    }

    private static func extractDictionaryValueType(_ dictType: String) -> String {
        // Handle [Key: Value] syntax — extract the value type
        if dictType.hasPrefix("[") && dictType.hasSuffix("]") {
            let inner = String(dictType.dropFirst().dropLast())
            if let colonIndex = inner.firstIndex(of: ":") {
                let valueType = inner[inner.index(after: colonIndex)...]
                    .trimmingCharacters(in: .whitespaces)
                return valueType
            }
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
