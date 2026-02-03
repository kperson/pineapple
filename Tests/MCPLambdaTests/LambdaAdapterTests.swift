import Testing
import Foundation
import Logging
import HTTPTypes
import TestSupport
import SimpleMathServer
@testable import MCP
@testable import MCPLambda
@testable import LambdaApp
@testable import AWSLambdaEvents

/// Tests for MCPLambda adapter using SimpleMathServer
///
/// These tests verify that the Lambda adapter correctly translates
/// between API Gateway requests and MCP protocol, using the common HTTP test suite.
@Suite("Lambda Adapter Tests")
struct LambdaAdapterTests {
    
    // MARK: - Test Setup
    
    /// Creates a test APIGatewayRequest for the given MCP request
    ///
    /// This mimics what API Gateway sends to Lambda when an HTTP POST arrives.
    /// Based on the structure from swift-aws-lambda-events test suite.
    func createAPIGatewayRequest(
        path: String,
        mcpRequest: MCP.Request
    ) throws -> AWSLambdaEvents.APIGatewayRequest {
        // Encode the MCP request to JSON
        let requestData = try JSONEncoder().encode(mcpRequest)
        let requestBody = String(data: requestData, encoding: .utf8)!
        
        // Build the full API Gateway request JSON structure
        let json: [String: Any] = [
            "httpMethod": "POST",
            "resource": path,
            "path": path,
            "requestContext": [
                "resourceId": "test-resource",
                "apiId": "test-api",
                "domainName": "test.execute-api.us-east-1.amazonaws.com",
                "resourcePath": path,
                "httpMethod": "POST",
                "requestId": UUID().uuidString,
                "accountId": "123456789012",
                "stage": "test",
                "identity": [
                    "apiKey": NSNull(),
                    "userArn": NSNull(),
                    "cognitoAuthenticationType": NSNull(),
                    "caller": NSNull(),
                    "userAgent": "test-agent",
                    "user": NSNull(),
                    "cognitoIdentityPoolId": NSNull(),
                    "cognitoAuthenticationProvider": NSNull(),
                    "sourceIp": "127.0.0.1",
                    "accountId": NSNull()
                ],
                "extendedRequestId": NSNull(),
                "path": path
            ],
            "queryStringParameters": NSNull(),
            "multiValueQueryStringParameters": NSNull(),
            "headers": ["Content-Type": "application/json"],
            "multiValueHeaders": ["Content-Type": ["application/json"]],
            "pathParameters": NSNull(),
            "stageVariables": NSNull(),
            "body": requestBody,
            "isBase64Encoded": false
        ]
        
        // Convert to Data and decode to APIGatewayRequest
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AWSLambdaEvents.APIGatewayRequest.self, from: jsonData)
    }
    
    /// Creates a mock LambdaContext for testing
    func createMockContext() -> MockLambdaContext {
        MockLambdaContext(
            requestID: UUID().uuidString,
            traceID: "test-trace",
            invokedFunctionARN: "arn:aws:lambda:us-east-1:123456789012:function:test"
        )
    }
    
    /// Wraps the common test pattern into a reusable closure
    ///
    /// This creates a test environment similar to Hummingbird's `app.test()` but for Lambda.
    /// Instead of making real HTTP requests, it calls the Lambda handler function directly
    /// with mock API Gateway events.
    func makeRequest(path: String = "/", body: Data) async throws -> Data {
        // Decode the MCP request from the body
        let mcpRequest = try JSONDecoder().decode(MCP.Request.self, from: body)
        
        // Create the server and router
        let server = createSimpleMathServer()
        let router = LambdaRouter()
        router.addServer(path: "/math", server: server)
        
        // Create the adapter and bridge it
        let adapter = LambdaAdapter()
        let handler = adapter.bridge(router)
        
        // Create the API Gateway request
        let apiGwRequest = try createAPIGatewayRequest(path: path, mcpRequest: mcpRequest)
        
        // Create the Lambda context
        let context = createMockContext()
        
        // Call the handler
        let response = try await handler(context, apiGwRequest)
        
        // Verify response structure
        #expect(response.statusCode == HTTPResponse.Status.ok)
        #expect(response.body != nil)
        
        // Decode response body (may be base64 encoded)
        guard let bodyString = response.body else {
            throw TestError.networkError("No response body")
        }
        
        if response.isBase64Encoded == true {
            // Decode from base64
            guard let decodedData = Data(base64Encoded: bodyString) else {
                throw TestError.networkError("Failed to decode base64 response")
            }
            return decodedData
        } else {
            // Use as UTF-8 string
            return bodyString.data(using: String.Encoding.utf8)!
        }
    }
    
    // MARK: - Common HTTP Tests
    
    @Test("Initialize returns capabilities")
    func testInitialize() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testInitialize()
    }
    
    @Test("Tools list returns add_numbers tool")
    func testToolsList() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testToolsList()
    }
    
    @Test("Tools call executes add_numbers")
    func testToolsCall() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testToolsCall()
    }
    
    @Test("Resources list returns pi constant")
    func testResourcesList() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testResourcesList()
    }
    
    @Test("Resources read returns pi value")
    func testResourcesRead() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testResourcesRead()
    }
    
    @Test("Prompts list returns explain_math")
    func testPromptsList() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testPromptsList()
    }
    
    @Test("Prompts get generates math explanation")
    func testPromptsGet() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testPromptsGet()
    }
    
    @Test("Tools call with integers")
    func testToolsCallWithIntegers() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testToolsCallWithIntegers()
    }
    
    @Test("Tools call nonexistent tool returns error")
    func testToolsCallNonexistentTool() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testToolsCallNonexistentTool()
    }
    
    @Test("Resources read nonexistent returns error")
    func testResourcesReadNonexistent() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testResourcesReadNonexistent()
    }
    
    @Test("Prompts get with missing argument returns error")
    func testPromptsGetMissingArgument() async throws {
        let commonTests = CommonMCPTests { path, body in
            try await self.makeRequest(path: path, body: body)
        }
        try await commonTests.testPromptsGetMissingArgument()
    }
    
    // MARK: - Base64 Encoding Tests
    
    @Test("Base64-encoded request body is decoded correctly")
    func testBase64EncodedRequest() async throws {
        // Create server and router
        let server = createSimpleMathServer()
        let router = LambdaRouter()
        router.addServer(path: "/math", server: server)
        
        // Create adapter and bridge
        let adapter = LambdaAdapter()
        let handler = adapter.bridge(router)
        
        // Create MCP request
        let mcpRequest = MCP.Request(
            id: .string("1"),
            method: "tools/list",
            params: nil
        )
        
        // Encode to JSON, then to base64
        let requestData = try JSONEncoder().encode(mcpRequest)
        let requestBody = requestData.base64EncodedString()
        
        // Build API Gateway request with base64 body
        let json: [String: Any] = [
            "httpMethod": "POST",
            "resource": "/math",
            "path": "/math",
            "requestContext": [
                "resourceId": "test-resource",
                "apiId": "test-api",
                "domainName": "test.execute-api.us-east-1.amazonaws.com",
                "resourcePath": "/math",
                "httpMethod": "POST",
                "requestId": UUID().uuidString,
                "accountId": "123456789012",
                "stage": "test",
                "identity": [
                    "apiKey": NSNull(),
                    "userArn": NSNull(),
                    "cognitoAuthenticationType": NSNull(),
                    "caller": NSNull(),
                    "userAgent": "test-agent",
                    "user": NSNull(),
                    "cognitoIdentityPoolId": NSNull(),
                    "cognitoAuthenticationProvider": NSNull(),
                    "sourceIp": "127.0.0.1",
                    "accountId": NSNull()
                ],
                "extendedRequestId": NSNull(),
                "path": "/math"
            ],
            "queryStringParameters": NSNull(),
            "multiValueQueryStringParameters": NSNull(),
            "headers": ["Content-Type": "application/json"],
            "multiValueHeaders": ["Content-Type": ["application/json"]],
            "pathParameters": NSNull(),
            "stageVariables": NSNull(),
            "body": requestBody,
            "isBase64Encoded": true  // Mark as base64 encoded
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let apiGwRequest = try JSONDecoder().decode(AWSLambdaEvents.APIGatewayRequest.self, from: jsonData)
        
        // Create Lambda context
        let context = createMockContext()
        
        // Call handler - should successfully decode base64 body
        let response = try await handler(context, apiGwRequest)
        
        // Verify response
        #expect(response.statusCode == HTTPResponse.Status.ok)
        #expect(response.body != nil)
        
        // Decode response (also base64)
        guard let bodyString = response.body else {
            throw TestError.networkError("No response body")
        }
        
        let responseData: Data
        if response.isBase64Encoded == true {
            guard let decoded = Data(base64Encoded: bodyString) else {
                throw TestError.networkError("Failed to decode base64 response")
            }
            responseData = decoded
        } else {
            responseData = bodyString.data(using: String.Encoding.utf8)!
        }
        
        // Parse and verify response
        let jsonResponse = try JSONSerialization.jsonObject(with: responseData) as! [String: Any]
        let result = jsonResponse["result"] as! [String: Any]
        let tools = result["tools"] as! [[String: Any]]
        
        #expect(tools.count == 1)
        #expect(tools[0]["name"] as? String == "add_numbers")
    }
}

// MARK: - Mock Lambda Context

/// Mock LambdaContext for testing
///
/// Swift Testing doesn't allow protocol extensions with stored properties,
/// so we create a concrete implementation of LambdaContext.
struct MockLambdaContext: LambdaContext {
    let requestId: String
    let traceId: String?
    let invokedFunctionArn: String
    let deadline: Date
    let cognitoIdentity: String?
    let clientContext: String?
    let logger: Logger
    
    init(requestID: String, traceID: String?, invokedFunctionARN: String) {
        self.requestId = requestID
        self.traceId = traceID
        self.invokedFunctionArn = invokedFunctionARN
        self.deadline = Date().addingTimeInterval(30) // 30 seconds from now
        self.cognitoIdentity = nil
        self.clientContext = nil
        
        var logger = Logger(label: "test")
        logger.logLevel = .trace
        self.logger = logger
    }
}
