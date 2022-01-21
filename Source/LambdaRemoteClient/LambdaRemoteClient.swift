import Foundation
import LambdaRuntimeAPI
import AsyncHttp


public class LambdaRemoteClient {
    
    let client: JSONHttpClient
    
    public init(baseURL: String) {
        client = JSONHttpClient(baseURL: baseURL)
    }
    
    public func getEvent(requestId: String, shouldLongPoll: Bool = false) async throws -> LambdaRemoteEvent? {
        let params = ["shouldLongPoll": shouldLongPoll ? "1" : "0"]
        return try await client.get(
            path: "/event/\(requestId)",
            queryParams: params
        ).extractOptional(type: LambdaRemoteEvent.self)
    }
    
    public func saveEvent(event: LambdaRemoteEventPost) async throws -> LambdaRemoteEvent {
        try await client.post(path: "/event", body: event).extract(type: LambdaRemoteEvent.self)
    }
    
    public func deleteEvent(requestId: String) async throws {
        try await client.delete(path: "/event/\(requestId)").void()
    }
    
    public func getNextInvocation(namespaceKey: String) async throws -> Data? {
        try await client.get(path: "/\(namespaceKey)/2018-06-01/runtime/invocation/next").requestResponseOptional()?.body
    }
    
    public func sendInvocationResponse(namespaceKey: String, requestId: String, response: Data) async throws {
        let path = "/\(namespaceKey)/2018-06-01/runtime/invocation/\(requestId)/response"
        try await client.postData(path: path, body: response).void()
    }
    
    public func sendInvocationError(namespaceKey: String, requestId: String, error: LambdaError) async throws {
        let path = "/\(namespaceKey)/2018-06-01/runtime/invocation/\(requestId)/error"
        try await client.post(path: path, body: error).void()
    }

    public func sendInitError(namespaceKey: String, error: LambdaError) async throws {
        let path = "/\(namespaceKey)/2018-06-01/runtime/init/error"
        try await client.post(path: path, body: error).void()
    }
    
}
