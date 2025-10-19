import Foundation

/**
 Base protocol for Lambda event handlers that process events and return results
 */
public protocol LambdaEventHandler {
    associatedtype Event: Decodable
    associatedtype Output: Encodable
    
    func handleEvent(context: LambdaContext, event: Event) async throws -> Output
}

/**
 Base protocol for Lambda event handlers that process events without returning results (void handlers)
 */
public protocol LambdaVoidEventHandler {
    associatedtype Event: Decodable
    
    func handleEvent(context: LambdaContext, event: Event) async throws
}
