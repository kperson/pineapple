import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

// MARK: - Protocol

/// Protocol for making HTTP requests to Lambda Runtime API
///
/// This protocol allows for dependency injection of the HTTP client, enabling
/// testing with mock implementations while using URLSession in production.
///
/// ## Usage
///
/// **Production:**
/// ```swift
/// let runtime = LambdaRuntime() // Uses URLSessionRuntimeClient by default
/// ```
///
/// **Testing:**
/// ```swift
/// let mockClient = MockRuntimeClient()
/// mockClient.mockResponses = [...]
/// let runtime = LambdaRuntime(httpClient: mockClient)
/// ```
public protocol RuntimeHTTPClient: Sendable {
    
    /// Makes an HTTP request to the Lambda Runtime API
    ///
    /// - Parameters:
    ///   - method: HTTP method (GET, POST, etc.)
    ///   - path: API path (e.g., "2018-06-01/runtime/invocation/next")
    ///   - body: Optional request body
    ///   - headers: HTTP headers
    ///   - runtimeAPI: The runtime API endpoint
    ///   - timeoutInterval: The request timeout
    ///   - callback: Completion handler with response or error
    func request(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String],
        runtimeAPI: String,
        timeoutInterval: TimeInterval,
        callback: @escaping @Sendable (LambdaRequestResponse?, Error?) -> Void
    )
}

public extension RuntimeHTTPClient {
    
    /// Makes an HTTP request to the Lambda Runtime API
    ///
    /// - Parameters:
    ///   - method: HTTP method (GET, POST, etc.)
    ///   - path: API path (e.g., "2018-06-01/runtime/invocation/next")
    ///   - body: Optional request body
    ///   - headers: HTTP headers
    ///   - runtimeAPI: The runtime API endpoint
    ///   - callback: Completion handler with response or error
    func request(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String],
        runtimeAPI: String,
        callback: @escaping @Sendable (LambdaRequestResponse?, Error?) -> Void
    ) {
        return request(
            method: method,
            path: path, body: body,
            headers: headers,
            runtimeAPI: runtimeAPI,
            timeoutInterval: 60,
            callback: callback
        )
    }
}

// MARK: - Production Implementation

/// Production HTTP client using URLSession
///
/// This is the default implementation used in real Lambda environments.
/// It makes actual HTTP calls to the Lambda Runtime API.
public final class URLSessionRuntimeClient: RuntimeHTTPClient, @unchecked Sendable {
    
    private let logger: Logger?
    
    public init(logger: Logger? = nil) {
        self.logger = logger
    }
    
    public func request(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String],
        runtimeAPI: String,
        timeoutInterval: TimeInterval,
        callback: @escaping @Sendable (LambdaRequestResponse?, Error?) -> Void
    ) {
        logger?.trace("Runtime request started: \(path)")
        
        let urlStr: String
        if runtimeAPI.starts(with: "http://") || runtimeAPI.starts(with: "https://") {
            urlStr = "\(runtimeAPI)/\(path)"
        } else {
            urlStr = "http://\(runtimeAPI)/\(path)"
        }
        
        var request = URLRequest(
            url: URL(string: urlStr)!,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: timeoutInterval
        )
        request.httpMethod = method
        request.httpBody = body
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let capturedLogger = logger
        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            if let e = error {
                // Intentionally trace because this is expected for long-polling timeouts
                capturedLogger?.trace("Runtime request failed or timed out: \(urlStr) - \(e)")
                callback(nil, e)
            } else if let httpResponse = response as? HTTPURLResponse {
                var responseHeaders: [String: String] = [:]
                let allHeaders = httpResponse.allHeaderFields
                for headerKey in allHeaders.keys {
                    if let key = headerKey as? String {
                        responseHeaders[key.lowercased()] = httpResponse.value(forHTTPHeaderField: key)
                    }
                }
                let res = LambdaRequestResponse(
                    statusCode: httpResponse.statusCode,
                    body: data ?? Data(),
                    headers: responseHeaders
                )
                capturedLogger?.debug("Runtime request succeeded: \(urlStr) (status: \(httpResponse.statusCode))")
                callback(res, nil)
            } else {
                // Unexpected response type
                let responseType = response.map { String(describing: type(of: $0)) } ?? "nil"
                capturedLogger?.error("Unexpected response type from runtime API: \(responseType)")
                struct UnexpectedResponseError: Error {
                    let responseType: String
                }
                callback(nil, UnexpectedResponseError(responseType: responseType))
            }
        }
        task.resume()
    }
}

// MARK: - Mock Implementation for Testing

/// Mock HTTP client for testing Lambda runtime without network calls
///
/// This client returns pre-configured responses synchronously, allowing for
/// fast, reliable, isolated tests without starting a real Lambda runtime API.
///
/// ## Usage
///
/// ```swift
/// let mockClient = MockRuntimeClient()
///
/// // Mock a "next event" response
/// mockClient.addMockResponse(
///     statusCode: 200,
///     body: eventJSON,
///     headers: ["Lambda-Runtime-Aws-Request-Id": "test-request-id"]
/// )
///
/// // Mock a success response
/// mockClient.addMockResponse(statusCode: 202, body: Data(), headers: [:])
///
/// let runtime = LambdaRuntime(httpClient: mockClient)
/// ```
public final class MockRuntimeClient: RuntimeHTTPClient, @unchecked Sendable {
    
    /// Recorded requests made to this client (for verification in tests)
    public struct RecordedRequest: Sendable {
        public let method: String
        public let path: String
        public let body: Data?
        public let headers: [String: String]
        public let runtimeAPI: String
    }
    
    private let lock = NSLock()
    private var mockResponses: [(LambdaRequestResponse?, Error?)] = []
    private var responseIndex = 0
    private var recordedRequests: [RecordedRequest] = []
    
    public init() {}
    
    /// Add a mock response that will be returned on the next request
    ///
    /// Responses are returned in FIFO order. If more requests are made than
    /// responses provided, subsequent requests will hang (no callback).
    public func addMockResponse(statusCode: Int, body: Data, headers: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        
        let response = LambdaRequestResponse(
            statusCode: statusCode,
            body: body,
            headers: headers
        )
        mockResponses.append((response, nil))
    }
    
    /// Add a mock error that will be returned on the next request
    public func addMockError(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        
        mockResponses.append((nil, error))
    }
    
    /// Get all recorded requests (for test assertions)
    public func getRecordedRequests() -> [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }
    
    /// Clear all recorded requests
    public func clearRecordedRequests() {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.removeAll()
    }
    
    public func request(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String],
        runtimeAPI: String,
        timeoutInterval: TimeInterval,
        callback: @escaping @Sendable (LambdaRequestResponse?, Error?) -> Void
    ) {
        lock.lock()
        
        // Record the request
        recordedRequests.append(RecordedRequest(
            method: method,
            path: path,
            body: body,
            headers: headers,
            runtimeAPI: runtimeAPI
        ))
        
        // Get the next response
        guard responseIndex < mockResponses.count else {
            lock.unlock()
            // No more responses - don't call callback (simulates hanging request)
            return
        }
        
        let (response, error) = mockResponses[responseIndex]
        responseIndex += 1
        lock.unlock()
        
        // Call callback synchronously (tests run fast)
        callback(response, error)
    }
}
