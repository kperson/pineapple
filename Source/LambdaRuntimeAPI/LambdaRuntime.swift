import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LambdaPayload {
    
    public let body: Data
    public let headers: [String : Any]
    
    public init(body: Data, headers: [String : Any]) {
        self.body = body
        self.headers = headers
    }
}

public struct LambdaError: Codable, Error {
    
    public let errorMessage: String
    public let errorType: String?
    public let stackTrace: [String]
    
    public init(
        errorMessage: String,
        errorType: String? = nil,
        stackTrace: [String] = []
    ) {
        self.errorMessage = errorMessage
        self.errorType = errorType
        self.stackTrace = stackTrace
    }
    
}


public class LambdaEvent {

    public let requestId: String
    public let payload: LambdaPayload
    public private(set) var isComplete = false
    
    let runTime: LambdaRuntime
    
    init(requestId: String, payload: LambdaPayload, runTime: LambdaRuntime) {
        self.requestId = requestId
        self.payload = payload
        self.runTime = runTime
    }
    
    public func sendResponse(data: Data) {
        if !isComplete {
            isComplete = true
            runTime.sendResponse(requestId: requestId, data: data)
        }
    }
    
    public func sendResponse(data: String, encoding: String.Encoding = .utf8) {
        if !isComplete {
            isComplete = true
            let bytes = data.data(using: encoding) ?? Data()
            runTime.sendResponse(requestId: requestId, data: bytes)
        }
    }
    
    public func sendResponse(data: [String : Any], encoding: String.Encoding = .utf8) {
        if !isComplete {
            isComplete = true
            let bytes = try? JSONSerialization.data(withJSONObject: data, options: [])
            runTime.sendResponse(requestId: requestId, data: bytes ?? Data())
        }
    }

    public func sendInitializationError(error: LambdaError) {
        if !isComplete {
            isComplete = true
            runTime.sendInitializationError(error: error)
        }
    }
    
    public func sendInvocationError(error: LambdaError) {
        if !isComplete {
            isComplete = true
            runTime.sendInvocationError(requestId: requestId, error: error)
        }
    }

}

public protocol LambdaEventHandler: AnyObject {
    
    func handleEvent(_ event: LambdaEvent)
    
}


public enum LambdaLogEvent {
    
    case runTimeInitialized(api: String)
    case nextEventRequested
    case requestStarted(path: String)
    case requestSucceeded(path: String, response: LambdaRequestResponse)
    case requestFailed(path: String, error: Error)
    
}


public protocol LambdaRuntimeLogHandler: AnyObject {
    
    func handleRuntimeLog(_ log: LambdaLogEvent)
    
}


public struct LambdaRequestResponse {
    
    public let statusCode: Int
    public let body: Data
    public let headers: [String : Any]
    
    public init(statusCode: Int, body: Data, headers: [String : Any]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }
    
}


public class LambdaRuntime {
    
    public weak var eventHandler: LambdaEventHandler?
    public weak var logHandler: LambdaRuntimeLogHandler?

    public let runtimeAPI: String
    public private(set) var isRunning: Bool = false
    
    private let encoder = JSONEncoder()
    private let semaphore = DispatchSemaphore(value: 0)
    private let runAsync: Bool
    
    
    /// Initializes a Lambda Runtime
    /// - Parameters:
    ///   - runTimeAPI: the API enpoint to hit
    ///   - runAsync: if some other process if keeping the application alive, set to true, defaults to false
    public init(
        runTimeAPI: String? = nil,
        runAsync: Bool = false
    ) {
        self.runtimeAPI = runTimeAPI
            ?? ProcessInfo.processInfo.environment["AWS_LAMBDA_RUNTIME_API"]
            ?? "localhost:8080"
        self.runAsync = runAsync
    }
    
    public func start() {
        if !isRunning {
            isRunning = true
            logHandler?.handleRuntimeLog(.runTimeInitialized(api: runtimeAPI))
            next()
            if !runAsync {
                semaphore.wait()
            }
        }
    }
    
    public func stop() {
        if isRunning {
            isRunning = false
            if !runAsync {
                semaphore.signal()
            }
        }
    }
    
    private func next() {
        if let handler = eventHandler, isRunning {
            logHandler?.handleRuntimeLog(.nextEventRequested)
            request(
                method: "GET",
                path: "2018-06-01/runtime/invocation/next",
                body: nil,
                headers: [:]
            ) { res, err in
                if  let r = res,
                    let requestId = r.headers["Lambda-Runtime-Aws-Request-Id".lowercased()] as? String {
                    let payload = LambdaPayload(body: r.body, headers: r.headers)
                    let event = LambdaEvent(requestId: requestId, payload: payload, runTime: self)
                    handler.handleEvent(event)
                }
                else {
                    self.next()
                }
            }
        }
    }
    
    func sendResponse(requestId: String, data: Data) {
        request(
            method: "POST",
            path: "2018-06-01/runtime/invocation/\(requestId)/response",
            body: data,
            headers: [:]
        ) { res, err in
            self.next()
        }
    }
    
    func sendInitializationError(error: LambdaError) {
        if let data = try? encoder.encode(error) {
            request(
                method: "POST",
                path: "2018-06-01/runtime/init/error",
                body: data,
                headers: ["Content-Type": "application/vnd.aws.lambda.error+json"]
            ) { res, err in
                self.next()
            }
        }
    }
    
    func sendInvocationError(requestId: String, error: LambdaError) {
        if let data = try? encoder.encode(error) {
            request(
                method: "POST",
                path: "2018-06-01/runtime/invocation/\(requestId)/error",
                body: data,
                headers: ["Content-Type": "application/vnd.aws.lambda.error+json"]
            ) { res, err in
                self.next()
            }
        }
    }
    
    
    private func request(
        method: String,
        path: String,
        body: Data?,
        headers: [String : String],
        callback: @escaping (LambdaRequestResponse?, Error?) -> Void
    ) {
        logHandler?.handleRuntimeLog(.requestStarted(path: path))
        let urlStr = "http://\(runtimeAPI)/\(path)"
        var request = URLRequest(
            url: URL(string: urlStr)!,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 60
        )
        request.httpMethod = method
        request.httpBody = body
        
        let session = URLSession.shared
        let task = session.dataTask(with: request, completionHandler: { data, response, error -> Void in
            if let e = error {
                self.logHandler?.handleRuntimeLog(.requestFailed(path: path, error: e))
                callback(nil, e)
            }
            else {
                let httpResponse = response as! HTTPURLResponse
                var responseHeaders: [String : Any] = [:]
                for (headerKey, headerValue) in httpResponse.allHeaderFields {
                    if let key = headerKey as? String {
                        responseHeaders[key.lowercased()] = headerValue
                    }
                }
                let res = LambdaRequestResponse(
                    statusCode: httpResponse.statusCode,
                    body: data ?? Data(),
                    headers: responseHeaders
                )
                self.logHandler?.handleRuntimeLog(.requestSucceeded(path: path, response: res))
                callback(res, nil)
            }
        })
        task.resume()
    }
    
}
