import LambdaRuntimeAPI
import Foundation

public protocol ApiGatewayHandler {
    
    func handleRequest(_ requestEvent: HTTPRequest) async throws -> HTTPResponse
    
}

struct RawLambdaHTTPResponse: Codable {
    
    let statusCode: Int
    let body: String
    let headers: [String : String]
    let multiValueHeaders: [String : [String]]
    let isBase64Encoded: Bool
    
    init(
        statusCode: Int,
        body: Data,
        headers: [String : String],
        multiValueHeaders: [String : [String]]
    ) {
        
        self.statusCode = statusCode
        self.body = body.base64EncodedString()
        self.headers = headers
        self.multiValueHeaders = multiValueHeaders
        self.isBase64Encoded = true
    }
    
}

public class LambdaHttpEvent {
    
    static let encoder = JSONEncoder()
    let event: LambdaEvent
    public let request: HTTPRequest
    
    public init(event: LambdaEvent, request: HTTPRequest) {
        self.event = event
        self.request = request
    }
    
    public func sendError(error: Error) {
        event.sendInvocationError(error: .init(error: error, errorType: "Vapor.Unknown"))
    }
    
    public func sendResponse(response: HTTPResponse) {
        do {
            let rawResponse = RawLambdaHTTPResponse(
                statusCode: response.statusCode,
                body: response.body,
                headers: response.headers,
                multiValueHeaders: response.multiValueHeaders
            )
            let data = try Self.encoder.encode(rawResponse)
            event.sendResponse(data: data)
        }
        catch let e {
            event.sendInvocationError(error: .init(error: e, errorType: "Lambda.ResponseSerialization"))
        }
    }
}

public class ApiGatewayEventHandler: LambdaAppEventHandler {
    
    typealias Handler = (HTTPRequest) async throws -> HTTPResponse
    
    class AsyncApiGatewayHandler: ApiGatewayHandler {

        let handler: (HTTPRequest) async throws -> HTTPResponse
        
        init(handler: @escaping Handler) {
            self.handler = handler
        }
        
        func handleRequest(_ requestEvent: HTTPRequest) async throws -> HTTPResponse {
            return try await handler(requestEvent)
        }
    }
    
    
    static let jsonDecoder = JSONDecoder()
    let handler: ApiGatewayHandler
    
    public init(_ h: ApiGatewayHandler) {
        self.handler = h
    }
    
    public init(_ h: @escaping (HTTPRequest) async throws -> HTTPResponse) {
        self.handler = AsyncApiGatewayHandler { (event: HTTPRequest) in
            try await h(event)
        }
    }
    
    public func handleEvent(_ event: LambdaEvent) {
        do {
            let request = try Self.jsonDecoder.decode(
                LambdaHTTPRequestBuilder.self,
                from: event.payload.body
            ).build()
            let httpEvent = LambdaHttpEvent(event: event, request: request)
            Task {
                do {
                    let response = try await handler.handleRequest(httpEvent.request)
                    httpEvent.sendResponse(response: response)
                }
                catch let e {
                    httpEvent.sendError(error: e)
                }
            }
        }
        catch let e {
            event.sendInvocationError(error: .init(error: e, errorType: "Lambda.RequestSerialization"))
        }
    }
}
