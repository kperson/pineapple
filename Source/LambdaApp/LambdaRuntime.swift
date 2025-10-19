import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif


public struct LambdaPayload: Codable, Equatable {
    
    public let body: Data
    public let headers: [String : String]
    
    public init(body: Data = Data(), headers: [String : String] = [:]) {
        self.body = body
        self.headers = headers
    }
}

public struct LambdaSuccessPayload: Codable, Equatable {
    
    public let body: Data
    
    public init(body: Data) {
        self.body = body
    }
}

public struct LambdaError: Codable, Error, Equatable {
    
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
    
    public init(
        error: Error,
        errorType: String? = nil,
        stackTrace: [String] = []
    ) {
        self.errorMessage = error.localizedDescription
        self.errorType = errorType
        self.stackTrace = stackTrace
    }
    
}



public final class LambdaEvent: @unchecked Sendable {

    public let requestId: String
    public let payload: LambdaPayload
    public private(set) var isComplete = false
    
    let runTime: Runtime
    
    public init(requestId: String, payload: LambdaPayload, runTime: Runtime) {
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

public extension LambdaEvent {
    
    func sendResponse(data: String, encoding: String.Encoding = .utf8) {
        let bytes = data.data(using: encoding) ?? Data()
        sendResponse(data: bytes)
    }
    
    func sendResponse(data: [String : Any], encoding: String.Encoding = .utf8) {
        let bytes = try? JSONSerialization.data(withJSONObject: data, options: [])
        sendResponse(data: bytes ?? Data())
    }
    
}

public protocol RuntimeEventHandler: AnyObject, Sendable {
    
    func handleEvent(_ event: LambdaEvent)
    
}

public struct LambdaRequestResponse {
    
    public let statusCode: Int
    public let body: Data
    public let headers: [String : String]
    
    public init(statusCode: Int, body: Data, headers: [String : String]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }
    
}

public protocol Runtime {

    func start()
    func stop()
    func sendResponse(requestId: String, data: Data)
    func sendInitializationError(error: LambdaError)
    func sendInvocationError(requestId: String, error: LambdaError)
    
    var eventHandler: RuntimeEventHandler? { get set }
    
}

public class LambdaRuntime: Runtime, @unchecked Sendable {

    public weak var eventHandler: RuntimeEventHandler?

    public let runtimeAPI: String
    public private(set) var isRunning: Bool = false
    
    private let encoder = JSONEncoder()
    private let runAsync: Bool
    private let logger: Logger?
    private var runningTask: Task<Void, Never>?
    
    
    
    /// Initializes a Lambda Runtime
    /// - Parameters:
    ///   - runTimeAPI: the API enpoint to hit
    ///   - runAsync: if some other process if keeping the application alive, set to true, defaults to false
    ///   - logger: Swift Logger instance for runtime logging
    public init(
        runTimeAPI: String? = nil,
        runAsync: Bool = false,
        logger: Logger? = nil
    ) {
        self.runtimeAPI = runTimeAPI
            ?? ProcessInfo.processInfo.environment["AWS_LAMBDA_RUNTIME_API"]
            ?? "localhost:8080"
        self.runAsync = runAsync
        self.logger = logger
    }
        
        
    public func start() {
        if !isRunning {
            isRunning = true
            logger?.info("Lambda runtime initialized with API: \(runtimeAPI)")
            next()
            if !runAsync {
                // Use RunLoop to keep the main thread alive in Lambda environment
                #if os(Linux)
                // On Linux, use a simple blocking loop
                while isRunning {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                #else
                // On macOS, use RunLoop
                RunLoop.main.run()
                #endif
            }
        }
    }
    
    public func stop() {
        if isRunning {
            isRunning = false
            #if !os(Linux)
            CFRunLoopStop(CFRunLoopGetMain())
            #endif
        }
    }
    
    private func next() {
        if let handler = eventHandler, isRunning {
            logger?.debug("Requesting next event from runtime")
            request(
                method: "GET",
                path: "2018-06-01/runtime/invocation/next",
                body: nil,
                headers: [:]
            ) { res, err in
                if  let r = res,
                    let requestId = r.headers["Lambda-Runtime-Aws-Request-Id".lowercased()] {
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
    
    public func sendResponse(requestId: String, data: Data) {
        logger?.debug("Sending response for requestId = \(requestId)")
        request(
            method: "POST",
            path: "2018-06-01/runtime/invocation/\(requestId)/response",
            body: data,
            headers: [:]
        ) { res, err in
            self.next()
        }
    }
    
    public func sendInitializationError(error: LambdaError) {
        logger?.error("Sending initialization error: \(error)")
        if let data = try? encoder.encode(error) {
            request(
                method: "POST",
                path: "2018-06-01/runtime/init/error",
                body: data,
                headers: ["Content-Type": "application/vnd.aws.lambda.error+json"]
            ) { res, err in
                self.stop()
            }
        }
    }
    
    public func sendInvocationError(requestId: String, error: LambdaError) {
        logger?.error("Sending invocation error: \(error)")
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
        callback: @escaping @Sendable (LambdaRequestResponse?, Error?) -> Void
    ) {
        logger?.trace("Runtime request started: \(path)")
        let urlStr: String
        if runtimeAPI.starts(with: "http://") || runtimeAPI.starts(with: "https://") {
            urlStr = "\(runtimeAPI)/\(path)"
        }
        else {
            urlStr = "http://\(runtimeAPI)/\(path)"
        }
        var request = URLRequest(
            url: URL(string: urlStr)!,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 60
        )
        request.httpMethod = method
        request.httpBody = body
        
        let capturedLogger = logger
        let session = URLSession.shared
        let task = session.dataTask(with: request, completionHandler: { data, response, error -> Void in
            if let e = error {
                // Intentionally debug because this is expected, but sometimes this could indicate an errror
                capturedLogger?.trace("Runtime request failed or timedout: \(urlStr) - \(e)")
                callback(nil, e)
            }
            else {
                let httpResponse = response as! HTTPURLResponse
                var responseHeaders: [String : String] = [:]
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
            }
        })
        task.resume()
    }
    
}
