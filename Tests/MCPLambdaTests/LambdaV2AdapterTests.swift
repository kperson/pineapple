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

/// Tests for MCPLambda V2 adapter using SimpleMathServer
///
/// These tests verify that the Lambda V2 adapter correctly translates
/// between API Gateway V2 requests and MCP protocol.
@Suite("Lambda V2 Adapter Tests")
struct LambdaV2AdapterTests {

    // MARK: - Test Setup

    /// Creates a test APIGatewayV2Request for the given MCP request
    func createAPIGatewayV2Request(
        path: String,
        mcpRequest: MCP.Request
    ) throws -> AWSLambdaEvents.APIGatewayV2Request {
        let requestData = try JSONEncoder().encode(mcpRequest)
        let requestBody = String(data: requestData, encoding: .utf8)!

        let json: [String: Any] = [
            "version": "2.0",
            "routeKey": "$default",
            "rawPath": path,
            "rawQueryString": "",
            "headers": ["Content-Type": "application/json"],
            "queryStringParameters": [:] as [String: String],
            "requestContext": [
                "accountId": "123456789012",
                "apiId": "test-api",
                "domainName": "test.execute-api.us-east-1.amazonaws.com",
                "domainPrefix": "test",
                "stage": "$default",
                "requestId": UUID().uuidString,
                "http": [
                    "method": "POST",
                    "path": path,
                    "protocol": "HTTP/1.1",
                    "sourceIp": "127.0.0.1",
                    "userAgent": "test-agent"
                ],
                "time": "12/Mar/2020:19:03:58 +0000",
                "timeEpoch": 1583348638390
            ],
            "body": requestBody,
            "isBase64Encoded": false
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AWSLambdaEvents.APIGatewayV2Request.self, from: jsonData)
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
    func makeRequest(path: String = "/", body: Data) async throws -> Data {
        let mcpRequest = try JSONDecoder().decode(MCP.Request.self, from: body)

        let server = createSimpleMathServer()
        let router = LambdaV2Router()
        router.addServer(path: "/math", server: server)

        let adapter = LambdaV2Adapter()
        let handler = adapter.bridge(router)

        let apiGwRequest = try createAPIGatewayV2Request(path: path, mcpRequest: mcpRequest)
        let context = createMockContext()

        let response = try await handler(context, apiGwRequest)

        #expect(response.statusCode == HTTPResponse.Status.ok)
        #expect(response.body != nil)

        guard let bodyString = response.body else {
            throw TestError.networkError("No response body")
        }

        if response.isBase64Encoded == true {
            guard let decodedData = Data(base64Encoded: bodyString) else {
                throw TestError.networkError("Failed to decode base64 response")
            }
            return decodedData
        } else {
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
        let server = createSimpleMathServer()
        let router = LambdaV2Router()
        router.addServer(path: "/math", server: server)

        let adapter = LambdaV2Adapter()
        let handler = adapter.bridge(router)

        let mcpRequest = MCP.Request(
            id: .string("1"),
            method: "tools/list",
            params: nil
        )

        let requestData = try JSONEncoder().encode(mcpRequest)
        let requestBody = requestData.base64EncodedString()

        let json: [String: Any] = [
            "version": "2.0",
            "routeKey": "$default",
            "rawPath": "/math",
            "rawQueryString": "",
            "headers": ["Content-Type": "application/json"],
            "requestContext": [
                "accountId": "123456789012",
                "apiId": "test-api",
                "domainName": "test.execute-api.us-east-1.amazonaws.com",
                "domainPrefix": "test",
                "stage": "$default",
                "requestId": UUID().uuidString,
                "http": [
                    "method": "POST",
                    "path": "/math",
                    "protocol": "HTTP/1.1",
                    "sourceIp": "127.0.0.1",
                    "userAgent": "test-agent"
                ],
                "time": "12/Mar/2020:19:03:58 +0000",
                "timeEpoch": 1583348638390
            ],
            "body": requestBody,
            "isBase64Encoded": true
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let apiGwRequest = try JSONDecoder().decode(AWSLambdaEvents.APIGatewayV2Request.self, from: jsonData)

        let context = createMockContext()

        let response = try await handler(context, apiGwRequest)

        #expect(response.statusCode == HTTPResponse.Status.ok)
        #expect(response.body != nil)

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

        let jsonResponse = try JSONSerialization.jsonObject(with: responseData) as! [String: Any]
        let result = jsonResponse["result"] as! [String: Any]
        let tools = result["tools"] as! [[String: Any]]

        #expect(tools.count == 1)
        #expect(tools[0]["name"] as? String == "add_numbers")
    }
}

// MockLambdaContext is defined in LambdaAdapterTests.swift
