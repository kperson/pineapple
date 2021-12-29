import LambdaRuntimeAPI
import Vapor

protocol AutoCopy {}

enum LambdaRemoteResponse: Codable {
    
    case response(payload: LambdaPayload)
    case invocationError(error: LambdaError)
    case initializationError(error: LambdaError)

}

typealias LambdaRemoteRequest = LambdaPayload


struct LambdaRemoteEvent: Codable, AutoCopy, Content {

    let requestId: String
    let namespaceKey: String
    let payloadCreatedAt: Int64
    let request: LambdaRemoteRequest
    let response: LambdaRemoteResponse?
    let expiresAt: Int64
    
}
