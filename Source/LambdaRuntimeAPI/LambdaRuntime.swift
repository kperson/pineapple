import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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


public class LambdaEvent {

    public let requestId: String
    public let payload: LambdaPayload
    public private(set) var isComplete = false
    
    let runTime: LambdaRuntime
    
    public init(requestId: String, payload: LambdaPayload, runTime: LambdaRuntime) {
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
    
    var eventHandler: LambdaEventHandler? { get set }
    var logHandler: LambdaRuntimeLogHandler? { get set }
    
}

public class LambdaRuntime: Runtime {
    
    public enum LogLevel: Int {
        case debug = 1
        case info = 2
        case error = 3
        
        var name: String {
            switch self {
            case .debug: return "debug"
            case .info: return "info"
            case.error: return "error"
            }
        }
    }
    
    public weak var eventHandler: LambdaEventHandler?
    public weak var logHandler: LambdaRuntimeLogHandler?

    public let runtimeAPI: String
    public private(set) var isRunning: Bool = false
    
    private let encoder = JSONEncoder()
    private let semaphore = DispatchSemaphore(value: 0)
    private let runAsync: Bool
    private let logLevel: LogLevel
    
    
    
    /// Initializes a Lambda Runtime
    /// - Parameters:
    ///   - runTimeAPI: the API enpoint to hit
    ///   - runAsync: if some other process if keeping the application alive, set to true, defaults to false
    public init(
        runTimeAPI: String? = nil,
        runAsync: Bool = false,
        logLevel: LogLevel = .error
    ) {
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        self.runtimeAPI = runTimeAPI
            ?? ProcessInfo.processInfo.environment["AWS_LAMBDA_RUNTIME_API"]
            ?? "localhost:8080"
        self.runAsync = runAsync
        self.logLevel = logLevel
    }
    
    private func log(_ level: LogLevel, _ items: Any...) {
        if level.rawValue >= self.logLevel.rawValue {
            print("\(level.name): \(items)")
            fflush(stdout)
        }
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
        log(.debug, "Sending response for requestId = \(requestId)")
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
        log(.error, "Sending initialization error: \(error)")
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
        log(.error, "Sending invocation error: \(error)")
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
        
        let session = URLSession.shared
        let task = session.dataTask(with: request, completionHandler: { data, response, error -> Void in
            if let e = error {
                self.logHandler?.handleRuntimeLog(.requestFailed(path: path, error: e))
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
                self.logHandler?.handleRuntimeLog(.requestSucceeded(path: path, response: res))
                callback(res, nil)
            }
        })
        task.resume()
    }
    
    
    
}
