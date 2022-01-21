import Foundation
import LambdaRuntimeAPI
import AsyncHttp


public class LambdaRemoteClient: JSONHttpClient {
    
    public init(baseURL: String) {
        super.init(baseURL: baseURL)
    }
    
    public func getEvent(requestId: String, shouldLongPoll: Bool = false) async throws -> LambdaRemoteEvent? {
        let params = ["shouldLongPoll" : shouldLongPoll ? "1" : "0"]
        return try await get(
            path: "/event/\(requestId)",
            queryParams: params
        ).extractOptional(type: LambdaRemoteEvent.self)
    }
    
    public func saveEvent(event: LambdaRemoteEventPost) async throws -> LambdaRemoteEvent {
        try await post(path: "/event", body: event).extract(type: LambdaRemoteEvent.self)
    }
    
    public func deleteEvent(requestId: String) async throws {
        try await delete(path: "/event/\(requestId)").void()
    }
    
    public func nextInvocation(namespaceKey: String) async throws -> Data? {
        try await get(path: "/\(namespaceKey)/2018-06-01/runtime/invocation/next").requestResponseOptional()?.body
    }
    
    public func sendInvocationResponse(namespaceKey: String, requestId: String, response: Data) async throws {
        let path = "/\(namespaceKey)/2018-06-01/runtime/invocation/\(requestId)/response"
        try await postData(path: path, body: response).void()
    }
    
    public func sendInvocationError(namespaceKey: String, requestId: String, error: LambdaError) async throws {
        let path = "/\(namespaceKey)/2018-06-01/runtime/invocation/\(requestId)/error"
        try await post(path: path, body: error).void()
    }

    public func sendInitError(namespaceKey: String, error: LambdaError) async throws {
        let path = "/\(namespaceKey)/2018-06-01/runtime/init/error"
        try await post(path: path, body: error).void()
    }
    
}
