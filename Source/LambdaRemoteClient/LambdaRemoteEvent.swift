import Foundation
import LambdaRuntimeAPI
import LambdaApp


protocol AutoCopy {}



public typealias LambdaRemoteRequest = LambdaPayload

public typealias LambdaRemoteResponse = LambdaResponse

public struct LambdaRemoteEvent: Codable, AutoCopy, Equatable {

    public let requestId: String
    public let namespaceKey: String
    public let payloadCreatedAt: Int64
    public let request: LambdaRemoteRequest
    public let response: LambdaRemoteResponse?
    public let expiresAt: Int64
    
    public init(
        requestId: String,
        namespaceKey: String,
        payloadCreatedAt: Int64,
        request: LambdaRemoteRequest,
        response: LambdaResponse?,
        expiresAt: Int64
    ) {
        self.requestId = requestId
        self.namespaceKey = namespaceKey
        self.payloadCreatedAt = payloadCreatedAt
        self.request = request
        self.response = response
        self.expiresAt = expiresAt
    }
    
}


public struct LambdaRemoteEventPost: Codable, Equatable {

    public let namespaceKey: String
    public let request: LambdaRemoteRequest
    public let requestId: String
    
    public init(namespaceKey: String, request: LambdaRemoteRequest, requestId: String) {
        self.namespaceKey = namespaceKey
        self.request = request
        self.requestId = requestId
    }
    
}
