import LambdaApp
import LambdaRuntimeAPI
import Foundation

public protocol LambdaApiGatewayHandler {
    
    func handleRequest(_ requestEvent: LambdaHttpEvent) -> Void
    
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
    public let request: LambdaHTTPRequest
    
    public init(event: LambdaEvent, request: LambdaHTTPRequest) {
        self.event = event
        self.request = request
    }
    
    public func sendError(error: Error) {
        event.sendInvocationError(error: .init(error: error, errorType: "Vapor.Unknown"))
    }
    
    public func sendResponse(response: LambdaHTTPResponse) {
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

public class LambdaApiGatewayAdapter: LambdaAppEventHandler {
    
    static let jsonDecoder = JSONDecoder()
    let handler: LambdaApiGatewayHandler
    
    public init(_ handler: LambdaApiGatewayHandler) {
        self.handler = handler
    }
    
    public func handleEvent(_ event: LambdaEvent) {
        do {
            let request = try Self.jsonDecoder.decode(
                LambdaHTTPRequestBuilder.self,
                from: event.payload.body
            ).build()
            print(request)
            handler.handleRequest(.init(event: event, request: request))
        }
        catch let e {
            event.sendInvocationError(error: .init(error: e, errorType: "Lambda.RequestSerialization"))
        }
    }
}
