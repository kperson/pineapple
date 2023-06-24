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
        body: HTTPResponse.Body,
        headers: [String : String],
        multiValueHeaders: [String : [String]]
    ) {
        self.statusCode = statusCode
        switch body {
        case .data(let value):
            self.body = value.base64EncodedString()
            self.isBase64Encoded = true
        case .string(let value):
            self.body = value
            self.isBase64Encoded = false
        }
        self.headers = headers
        self.multiValueHeaders = multiValueHeaders
    }
    
}

public class LambdaHttpEvent {
    
    static let encoder = JSONEncoder()
    let event: LambdaEvent
    public let request: HTTPRequest
    public let base64EncodeResponse: Bool
    
    public init(event: LambdaEvent, request: HTTPRequest, base64EncodeResponse: Bool) {
        self.event = event
        self.request = request
        self.base64EncodeResponse = base64EncodeResponse
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
    
    public typealias Handler = (HTTPRequest) async throws -> HTTPResponse
    
    
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
    public let base64EncodeResponse: Bool
    
    public init(base64EncodeResponse: Bool = true, _ h: ApiGatewayHandler) {
        self.handler = h
        self.base64EncodeResponse = true
    }
    
    public init(base64EncodeResponse: Bool = true, _ h: @escaping (HTTPRequest) async throws -> HTTPResponse) {
        self.base64EncodeResponse = base64EncodeResponse
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
            let httpEvent = LambdaHttpEvent(event: event, request: request, base64EncodeResponse: base64EncodeResponse)
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


public extension LambdaApp {

    func addApiGateway(_ handlerKey: CustomStringConvertible, _ handler: ApiGatewayHandler) {
        self.addHandler(handlerKey, ApiGatewayEventHandler(handler))
    }
    
    func addApiGateway(_ handlerKey: CustomStringConvertible, _ handler: @escaping ApiGatewayEventHandler.Handler) {
        self.addApiGateway(handlerKey, ApiGatewayEventHandler.AsyncApiGatewayHandler(handler: handler))
    }
    
}
