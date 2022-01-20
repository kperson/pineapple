import Foundation
import LambdaRuntimeAPI

protocol AutoCopy {}

public enum LambdaRemoteResponse: Codable {
    
    case response(payload: LambdaPayload)
    case invocationError(error: LambdaError)
    case initializationError(error: LambdaError)

}

public typealias LambdaRemoteRequest = LambdaPayload


public struct LambdaRemoteEvent: Codable, AutoCopy {

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
        response: LambdaRemoteResponse?,
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
