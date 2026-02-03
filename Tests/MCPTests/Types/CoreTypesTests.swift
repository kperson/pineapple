import Testing
import Foundation
import Logging
@testable import MCP

@Suite("Core MCP Types Tests")
struct CoreTypesTests {
    
    // MARK: - RequestId Tests
    
    @Suite("RequestId")
    struct RequestIdTests {
        
        @Test("RequestId encodes string value")
        func requestIdEncodesString() throws {
            let id = RequestId.string("test-123")
            let encoded = try JSONEncoder().encode(id)
            let str = String(data: encoded, encoding: .utf8)!
            
            #expect(str == "\"test-123\"")
        }
        
        @Test("RequestId encodes number value")
        func requestIdEncodesNumber() throws {
            let id = RequestId.number(42)
            let encoded = try JSONEncoder().encode(id)
            let str = String(data: encoded, encoding: .utf8)!
            
            #expect(str == "42")
        }
        
        @Test("RequestId decodes string value")
        func requestIdDecodesString() throws {
            let json = "\"req-456\"".data(using: .utf8)!
            let id = try JSONDecoder().decode(RequestId.self, from: json)
            
            if case .string(let value) = id {
                #expect(value == "req-456")
            } else {
                Issue.record("Expected string RequestId")
            }
        }
        
        @Test("RequestId decodes number value")
        func requestIdDecodesNumber() throws {
            let json = "999".data(using: .utf8)!
            let id = try JSONDecoder().decode(RequestId.self, from: json)
            
            if case .number(let value) = id {
                #expect(value == 999)
            } else {
                Issue.record("Expected number RequestId")
            }
        }
        
        @Test("RequestId rejects invalid types")
        func requestIdRejectsInvalidTypes() throws {
            let json = "true".data(using: .utf8)!
            
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(RequestId.self, from: json)
            }
        }
        
        @Test("RequestId round-trip string")
        func requestIdRoundTripString() throws {
            let original = RequestId.string("abc-123")
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(RequestId.self, from: encoded)
            
            if case .string(let value) = decoded {
                #expect(value == "abc-123")
            } else {
                Issue.record("Round-trip failed for string RequestId")
            }
        }
        
        @Test("RequestId round-trip number")
        func requestIdRoundTripNumber() throws {
            let original = RequestId.number(12345)
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(RequestId.self, from: encoded)
            
            if case .number(let value) = decoded {
                #expect(value == 12345)
            } else {
                Issue.record("Round-trip failed for number RequestId")
            }
        }
    }
    
    // MARK: - Request Tests
    
    @Suite("Request")
    struct RequestTests {
        
        @Test("Request encodes with all fields")
        func requestEncodesWithAllFields() throws {
            let request = Request(
                id: .string("1"),
                method: "tools/call",
                params: ["name": .string("test")]
            )
            
            let encoded = try JSONEncoder().encode(request)
            let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            
            #expect(json?["jsonrpc"] as? String == "2.0")
            #expect(json?["id"] as? String == "1")
            #expect(json?["method"] as? String == "tools/call")
            #expect(json?["params"] != nil)
        }
        
        @Test("Request encodes without id")
        func requestEncodesWithoutId() throws {
            let request = Request(
                id: nil,
                method: "tools/list"
            )
            
            let encoded = try JSONEncoder().encode(request)
            let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            
            #expect(json?["jsonrpc"] as? String == "2.0")
            #expect(json?["id"] == nil)
            #expect(json?["method"] as? String == "tools/list")
        }
        
        @Test("Request decodes with all fields")
        func requestDecodesWithAllFields() throws {
            let json = """
            {
                "jsonrpc": "2.0",
                "id": "123",
                "method": "tools/call",
                "params": {"name": "test"}
            }
            """.data(using: .utf8)!
            
            let request = try JSONDecoder().decode(Request.self, from: json)
            
            #expect(request.jsonrpc == "2.0")
            #expect(request.method == "tools/call")
            #expect(request.params != nil)
            
            if case .string(let id) = request.id {
                #expect(id == "123")
            } else {
                Issue.record("Expected string ID")
            }
        }
        
        @Test("Request decodes without params")
        func requestDecodesWithoutParams() throws {
            let json = """
            {
                "jsonrpc": "2.0",
                "id": 42,
                "method": "initialize"
            }
            """.data(using: .utf8)!
            
            let request = try JSONDecoder().decode(Request.self, from: json)
            
            #expect(request.method == "initialize")
            #expect(request.params == nil)
            
            if case .number(let id) = request.id {
                #expect(id == 42)
            } else {
                Issue.record("Expected number ID")
            }
        }
        
        @Test("Request round-trip preserves all fields")
        func requestRoundTrip() throws {
            let original = Request(
                id: .number(999),
                method: "resources/read",
                params: ["uri": .string("file://test.json")]
            )
            
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(Request.self, from: encoded)
            
            #expect(decoded.method == original.method)
            #expect(decoded.params?.count == original.params?.count)
        }
    }
    
    // MARK: - Response Tests
    
    @Suite("Response")
    struct ResponseTests {
        
        @Test("Response encodes success result")
        func responseEncodesSuccess() throws {
            let response = Response(
                id: .string("1"),
                result: "success"
            )
            
            let encoded = try JSONEncoder().encode(response)
            let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            
            #expect(json?["jsonrpc"] as? String == "2.0")
            #expect(json?["id"] as? String == "1")
            #expect(json?["result"] as? String == "success")
            #expect(json?["error"] == nil)
        }
        
        @Test("Response encodes error")
        func responseEncodesError() throws {
            let error = MCPError(
                code: .methodNotFound,
                message: "Method not found"
            )
            let response = Response<String>(
                id: .number(42),
                error: error
            )
            
            let encoded = try JSONEncoder().encode(response)
            let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            
            #expect(json?["jsonrpc"] as? String == "2.0")
            #expect(json?["error"] != nil)
            #expect(json?["result"] == nil)
        }
        
        @Test("Response fromError factory method works")
        func responseFromError() throws {
            let error = MCPError(
                code: .invalidParams,
                message: "Invalid parameters"
            )
            let response = Response<String>.fromError(
                id: .string("test"),
                error: error
            )
            
            #expect(response.error != nil)
            #expect(response.result == nil)
            #expect(response.error?.code == MCPErrorCode.invalidParams.rawValue)
        }
        
        @Test("Response encodes complex result")
        func responseEncodesComplexResult() throws {
            struct ComplexResult: Encodable {
                let items: [String]
                let count: Int
            }
            
            let response = Response(
                id: .string("1"),
                result: ComplexResult(items: ["a", "b"], count: 2)
            )
            
            let encoded = try JSONEncoder().encode(response)
            let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            
            #expect(json?["result"] != nil)
        }
    }
    
    // MARK: - MCPError Tests
    
    @Suite("MCPError")
    struct MCPErrorTests {
        
        @Test("MCPError with standard code")
        func mcpErrorWithStandardCode() throws {
            let error = MCPError(
                code: .methodNotFound,
                message: "Tool not found"
            )
            
            #expect(error.code == -32601)
            #expect(error.message == "Tool not found")
            #expect(error.data == nil)
        }
        
        @Test("MCPError with custom code")
        func mcpErrorWithCustomCode() throws {
            let error = MCPError(
                code: 1001,
                message: "Custom error"
            )
            
            #expect(error.code == 1001)
            #expect(error.message == "Custom error")
        }
        
        @Test("MCPError with data")
        func mcpErrorWithData() throws {
            let error = MCPError(
                code: .invalidParams,
                message: "Missing field",
                data: ["field": "name", "expected": "string"]
            )
            
            #expect(error.data != nil)
        }
        
        @Test("MCPError encodes correctly")
        func mcpErrorEncodes() throws {
            let error = MCPError(
                code: .parseError,
                message: "Invalid JSON"
            )
            
            let encoded = try JSONEncoder().encode(error)
            let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            
            #expect(json?["code"] as? Int == -32700)
            #expect(json?["message"] as? String == "Invalid JSON")
        }
        
        @Test("MCPError decodes correctly")
        func mcpErrorDecodes() throws {
            let json = """
            {
                "code": -32602,
                "message": "Invalid parameters"
            }
            """.data(using: .utf8)!
            
            let error = try JSONDecoder().decode(MCPError.self, from: json)
            
            #expect(error.code == -32602)
            #expect(error.message == "Invalid parameters")
        }
        
        @Test("MCPError round-trip with data")
        func mcpErrorRoundTrip() throws {
            let original = MCPError(
                code: .internalError,
                message: "Server error",
                data: ["trace": "stack trace here"]
            )
            
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(MCPError.self, from: encoded)
            
            #expect(decoded.code == original.code)
            #expect(decoded.message == original.message)
            #expect(decoded.data != nil)
        }
        
        @Test("MCPErrorCode all cases have valid values")
        func mcpErrorCodeAllCases() {
            #expect(MCPErrorCode.parseError.rawValue == -32700)
            #expect(MCPErrorCode.invalidRequest.rawValue == -32600)
            #expect(MCPErrorCode.methodNotFound.rawValue == -32601)
            #expect(MCPErrorCode.invalidParams.rawValue == -32602)
            #expect(MCPErrorCode.internalError.rawValue == -32603)
        }
    }
    
    // MARK: - TransportEnvelope Tests
    
    @Suite("TransportEnvelope")
    struct TransportEnvelopeTests {
        
        @Test("TransportEnvelope initializes with all fields")
        func transportEnvelopeInitialization() {
            let request = Request(id: .string("1"), method: "test")
            let envelope = TransportEnvelope(
                mcpRequest: request,
                routePath: "/test",
                metadata: ["key": "value"],
                pathParams: Params(["param": "value"])
            )
            
            #expect(envelope.mcpRequest.method == "test")
            #expect(envelope.routePath == "/test")
            #expect(envelope.metadata["key"] as? String == "value")
            #expect(envelope.pathParams?["param"] == "value")
        }
        
        @Test("TransportEnvelope combine merges metadata")
        func transportEnvelopeCombine() {
            let request = Request(id: .string("1"), method: "test")
            let envelope = TransportEnvelope(
                mcpRequest: request,
                routePath: "/",
                metadata: ["key1": "value1"]
            )
            
            let combined = envelope.combine(with: ["key2": "value2"])
            
            #expect(combined.metadata["key1"] as? String == "value1")
            #expect(combined.metadata["key2"] as? String == "value2")
        }
        
        @Test("TransportEnvelope combine last write wins")
        func transportEnvelopeCombineConflict() {
            let request = Request(id: .string("1"), method: "test")
            let envelope = TransportEnvelope(
                mcpRequest: request,
                routePath: "/",
                metadata: ["key": "old"]
            )
            
            let combined = envelope.combine(with: ["key": "new"])
            
            #expect(combined.metadata["key"] as? String == "new")
        }
        
        @Test("TransportEnvelope combine preserves pathParams")
        func transportEnvelopeCombinePreservesPathParams() {
            let request = Request(id: .string("1"), method: "test")
            let params = Params(["id": "123"])
            let envelope = TransportEnvelope(
                mcpRequest: request,
                routePath: "/",
                metadata: [:],
                pathParams: params
            )
            
            let combined = envelope.combine(with: ["key": "value"])
            
            #expect(combined.pathParams?["id"] == "123")
        }
        
        @Test("TransportEnvelope combine with empty metadata")
        func transportEnvelopeCombineEmpty() {
            let request = Request(id: .string("1"), method: "test")
            let envelope = TransportEnvelope(
                mcpRequest: request,
                routePath: "/",
                metadata: ["original": "data"]
            )
            
            let combined = envelope.combine(with: [:])
            
            #expect(combined.metadata["original"] as? String == "data")
        }
    }
    
    // MARK: - MCPContext Tests
    
    @Suite("MCPContext")
    struct MCPContextTests {
        
        @Test("MCPContext initializes with all fields")
        func mcpContextInitialization() {
            let logger = Logger(label: "test")
            let context = MCPContext(
                requestId: .string("req-1"),
                method: "tools/call",
                logger: logger,
                metadata: ["userId": "user-123"]
            )
            
            if case .string(let id) = context.requestId {
                #expect(id == "req-1")
            } else {
                Issue.record("Expected string requestId")
            }
            
            #expect(context.method == "tools/call")
            #expect(context.metadata["userId"] as? String == "user-123")
        }
        
        @Test("MCPContext metadata access")
        func mcpContextMetadataAccess() {
            let logger = Logger(label: "test")
            let context = MCPContext(
                requestId: .number(42),
                method: "test",
                logger: logger,
                metadata: [
                    "string": "value",
                    "number": 123,
                    "bool": true
                ]
            )
            
            #expect(context.metadata["string"] as? String == "value")
            #expect(context.metadata["number"] as? Int == 123)
            #expect(context.metadata["bool"] as? Bool == true)
        }
    }
}
