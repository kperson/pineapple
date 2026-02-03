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

// MARK: - Lambda Payload Types

/// Incoming Lambda invocation payload
///
/// Contains the raw event data and HTTP headers from the Lambda Runtime API.
/// The `body` contains the JSON-encoded event (SQS, S3, API Gateway, etc.)
/// and `headers` contain Lambda-specific metadata like request ID and trace ID.
///
/// ## Headers
///
/// Common headers include:
/// - `lambda-runtime-aws-request-id`: Unique request identifier
/// - `lambda-runtime-trace-id`: AWS X-Ray trace ID
/// - `lambda-runtime-deadline-ms`: Function timeout deadline
/// - `lambda-runtime-invoked-function-arn`: Function ARN
public struct LambdaPayload: Codable, Equatable {

    /// Raw event body data (JSON-encoded Lambda event)
    public let body: Data

    /// Lambda Runtime API headers with request metadata
    public let headers: [String: String]

    /// Create a Lambda payload
    ///
    /// - Parameters:
    ///   - body: Raw event data (defaults to empty)
    ///   - headers: Runtime headers (defaults to empty)
    public init(body: Data = Data(), headers: [String: String] = [:]) {
        self.body = body
        self.headers = headers
    }
}

/// Successful Lambda response payload
///
/// Wraps the response data to be sent back to the Lambda Runtime API
/// after successful handler execution.
public struct LambdaSuccessPayload: Codable, Equatable {

    /// Response body data
    public let body: Data

    /// Create a success payload
    ///
    /// - Parameter body: Response data to return
    public init(body: Data) {
        self.body = body
    }
}

// MARK: - Lambda Error

/// Lambda error response for reporting failures to the Runtime API
///
/// Conforms to AWS Lambda's error response format. When a handler throws
/// an error, it's wrapped in `LambdaError` and sent to the Runtime API.
///
/// ## Example
///
/// ```swift
/// // Create from message
/// let error = LambdaError(errorMessage: "File not found")
///
/// // Create from Swift error
/// do {
///     try await someOperation()
/// } catch {
///     let lambdaError = LambdaError(error: error, errorType: "IOError")
/// }
/// ```
public struct LambdaError: Codable, Error, Equatable {

    /// Human-readable error message
    public let errorMessage: String

    /// Error type/category (e.g., "ValidationError", "IOError")
    public let errorType: String?

    /// Stack trace frames (if available)
    public let stackTrace: [String]

    /// Create a Lambda error from a message
    ///
    /// - Parameters:
    ///   - errorMessage: Human-readable error description
    ///   - errorType: Optional error category
    ///   - stackTrace: Optional stack trace frames
    public init(
        errorMessage: String,
        errorType: String? = nil,
        stackTrace: [String] = []
    ) {
        self.errorMessage = errorMessage
        self.errorType = errorType
        self.stackTrace = stackTrace
    }

    /// Create a Lambda error from a Swift Error
    ///
    /// - Parameters:
    ///   - error: The Swift error to wrap
    ///   - errorType: Optional error category
    ///   - stackTrace: Optional stack trace frames
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



// MARK: - Lambda Event

/// Represents a single Lambda invocation event
///
/// `LambdaEvent` wraps an incoming Lambda invocation, providing access to
/// the request ID, payload, and methods for sending responses or errors
/// back to the Lambda Runtime API.
///
/// ## Response Lifecycle
///
/// Each event must be completed exactly once by calling one of:
/// - `sendResponse(data:)` - Success response
/// - `sendInvocationError(error:)` - Handler error
/// - `sendInitializationError(error:)` - Initialization failure
///
/// The `isComplete` flag prevents duplicate responses.
///
/// ## Example
///
/// ```swift
/// func handleEvent(_ event: LambdaEvent) {
///     do {
///         let result = try processPayload(event.payload)
///         event.sendResponse(data: result)
///     } catch {
///         event.sendInvocationError(error: LambdaError(error: error))
///     }
/// }
/// ```
public final class LambdaEvent: @unchecked Sendable {

    /// Unique identifier for this invocation
    public let requestId: String

    /// The Lambda invocation payload
    public let payload: LambdaPayload

    /// Whether a response has been sent for this event
    public private(set) var isComplete = false

    let runTime: Runtime

    /// Create a Lambda event
    ///
    /// - Parameters:
    ///   - requestId: Unique request identifier from Runtime API
    ///   - payload: The invocation payload
    ///   - runTime: Runtime instance for sending responses
    public init(requestId: String, payload: LambdaPayload, runTime: Runtime) {
        self.requestId = requestId
        self.payload = payload
        self.runTime = runTime
    }

    /// Send a successful response
    ///
    /// Sends the response data to the Lambda Runtime API. Can only be called
    /// once per event - subsequent calls are ignored.
    ///
    /// - Parameter data: Response data to return
    public func sendResponse(data: Data) {
        if !isComplete {
            isComplete = true
            runTime.sendResponse(requestId: requestId, data: data)
        }
    }

    /// Report an initialization error
    ///
    /// Used when the handler fails during initialization (before processing
    /// can begin). Stops the runtime after reporting.
    ///
    /// - Parameter error: The initialization error
    public func sendInitializationError(error: LambdaError) {
        if !isComplete {
            isComplete = true
            runTime.sendInitializationError(error: error)
        }
    }

    /// Report an invocation error
    ///
    /// Used when the handler fails during event processing. The runtime
    /// continues to accept new events after reporting.
    ///
    /// - Parameter error: The invocation error
    public func sendInvocationError(error: LambdaError) {
        if !isComplete {
            isComplete = true
            runTime.sendInvocationError(requestId: requestId, error: error)
        }
    }
}

public extension LambdaEvent {

    /// Send a string response
    ///
    /// Convenience method that converts a string to data before sending.
    ///
    /// - Parameters:
    ///   - data: String response
    ///   - encoding: String encoding (defaults to UTF-8)
    func sendResponse(data: String, encoding: String.Encoding = .utf8) {
        let bytes = data.data(using: encoding) ?? Data()
        sendResponse(data: bytes)
    }

    /// Send a dictionary response as JSON
    ///
    /// Convenience method that serializes a dictionary to JSON before sending.
    ///
    /// - Parameters:
    ///   - data: Dictionary to serialize as JSON
    ///   - encoding: String encoding (defaults to UTF-8)
    func sendResponse(data: [String: Any], encoding: String.Encoding = .utf8) {
        let bytes = try? JSONSerialization.data(withJSONObject: data, options: [])
        sendResponse(data: bytes ?? Data())
    }
}

// MARK: - Runtime Event Handler Protocol

/// Protocol for handling Lambda events
///
/// Implement this protocol to create custom Lambda event handlers.
/// `LambdaApp` implements this protocol internally.
///
/// ## Example
///
/// ```swift
/// class MyHandler: RuntimeEventHandler {
///     func handleEvent(_ event: LambdaEvent) {
///         // Process event and send response
///         event.sendResponse(data: "OK".data(using: .utf8)!)
///     }
/// }
/// ```
public protocol RuntimeEventHandler: AnyObject, Sendable {

    /// Handle an incoming Lambda event
    ///
    /// Implementation must eventually call one of the response methods on
    /// the event to complete the invocation.
    ///
    /// - Parameter event: The Lambda event to process
    func handleEvent(_ event: LambdaEvent)
}

// MARK: - Lambda Request Response

/// Response from the Lambda Runtime API
///
/// Represents an HTTP response from runtime API calls (internal use).
public struct LambdaRequestResponse: Sendable {

    /// HTTP status code
    public let statusCode: Int

    /// Response body data
    public let body: Data

    /// Response headers
    public let headers: [String: String]

    /// Create a request response
    ///
    /// - Parameters:
    ///   - statusCode: HTTP status code
    ///   - body: Response body
    ///   - headers: Response headers
    public init(statusCode: Int, body: Data, headers: [String: String]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }
}

// MARK: - Runtime Protocol

/// Protocol defining the Lambda Runtime API interface
///
/// Implementations communicate with AWS Lambda's Runtime API to:
/// - Poll for new invocation events
/// - Send successful responses
/// - Report errors
///
/// `LambdaRuntime` is the standard implementation using HTTP.
public protocol Runtime {

    /// Start the runtime event loop
    ///
    /// Begins polling for Lambda events. Depending on configuration,
    /// may block the current thread or run asynchronously.
    func start()

    /// Stop the runtime event loop
    ///
    /// Stops accepting new events and terminates the runtime.
    func stop()

    /// Send a successful invocation response
    ///
    /// - Parameters:
    ///   - requestId: The request ID to respond to
    ///   - data: Response data
    func sendResponse(requestId: String, data: Data)

    /// Report an initialization error
    ///
    /// Called when the handler fails during initialization.
    /// Typically terminates the runtime.
    ///
    /// - Parameter error: The initialization error
    func sendInitializationError(error: LambdaError)

    /// Report an invocation error
    ///
    /// Called when handler processing fails. Runtime continues
    /// accepting new events.
    ///
    /// - Parameters:
    ///   - requestId: The request ID that failed
    ///   - error: The invocation error
    func sendInvocationError(requestId: String, error: LambdaError)

    /// The event handler that processes Lambda events
    var eventHandler: RuntimeEventHandler? { get set }
}

// MARK: - Lambda Runtime

/// AWS Lambda custom runtime implementation
///
/// `LambdaRuntime` implements the AWS Lambda Runtime API, polling for events
/// and dispatching them to registered handlers. It handles the complete
/// lifecycle of Lambda invocations including responses and error reporting.
///
/// ## Architecture
///
/// ```
/// AWS Lambda Runtime API
///     ↓ (HTTP long-poll)
/// LambdaRuntime.next()
///     ↓
/// LambdaEvent created
///     ↓
/// RuntimeEventHandler.handleEvent()
///     ↓
/// LambdaEvent.sendResponse() / sendInvocationError()
///     ↓
/// LambdaRuntime.sendResponse() / sendInvocationError()
///     ↓ (HTTP POST)
/// AWS Lambda Runtime API
/// ```
///
/// ## Usage
///
/// Typically used through `LambdaApp` rather than directly:
///
/// ```swift
/// let app = LambdaApp()
///     .addSQS(key: "handler") { context, event in
///         // Process SQS event
///     }
/// app.run(handlerKey: "handler")
/// ```
///
/// ## Direct Usage
///
/// For custom runtime scenarios:
///
/// ```swift
/// let runtime = LambdaRuntime(logger: logger)
/// runtime.eventHandler = myHandler
/// runtime.start()  // Blocks until stopped
/// ```
///
/// ## Async Mode
///
/// By default, `start()` blocks the current thread. Set `runAsync: true`
/// if another mechanism keeps the process alive:
///
/// ```swift
/// let runtime = LambdaRuntime(runAsync: true)
/// runtime.start()  // Returns immediately
/// dispatchMain()   // Keep process alive
/// ```
public class LambdaRuntime: Runtime, @unchecked Sendable {

    /// The event handler that processes Lambda events
    public weak var eventHandler: RuntimeEventHandler?

    /// The Lambda Runtime API endpoint (host:port)
    public let runtimeAPI: String

    /// Whether the runtime is currently accepting events
    public private(set) var isRunning: Bool = false

    private let encoder = JSONEncoder()
    private let runAsync: Bool
    private let logger: Logger?
    private var runningTask: Task<Void, Never>?
    private let httpClient: RuntimeHTTPClient

    /// Initialize a Lambda Runtime
    ///
    /// - Parameters:
    ///   - httpClient: HTTP client for Runtime API requests (defaults to URLSession-based client)
    ///   - runTimeAPI: Runtime API endpoint. Defaults to `AWS_LAMBDA_RUNTIME_API` env var
    ///     or `localhost:8080` for local testing
    ///   - runAsync: If `true`, `start()` returns immediately. If `false` (default),
    ///     `start()` blocks until `stop()` is called
    ///   - logger: Logger for runtime diagnostics
    public init(
        httpClient: RuntimeHTTPClient? = nil,
        runTimeAPI: String? = nil,
        runAsync: Bool = false,
        logger: Logger? = nil
    ) {
        self.runtimeAPI = runTimeAPI
            ?? ProcessInfo.processInfo.environment["AWS_LAMBDA_RUNTIME_API"]
            ?? "localhost:8080"
        self.runAsync = runAsync
        self.logger = logger
        self.httpClient = httpClient ?? URLSessionRuntimeClient(logger: logger)
    }

    /// Start the runtime event loop
    ///
    /// Begins polling the Lambda Runtime API for events. Events are dispatched
    /// to the configured `eventHandler`.
    ///
    /// ## Blocking Behavior
    ///
    /// - `runAsync: false` (default): Blocks until `stop()` is called
    /// - `runAsync: true`: Returns immediately after starting the event loop
    ///
    /// ## Platform Notes
    ///
    /// - **Linux**: Uses a sleep-based blocking loop
    /// - **macOS**: Uses `RunLoop.main.run()` for blocking
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
    
    /// Stop the runtime event loop
    ///
    /// Stops accepting new events and terminates any blocking `start()` call.
    /// Safe to call multiple times.
    public func stop() {
        if isRunning {
            isRunning = false
            #if !os(Linux)
            CFRunLoopStop(CFRunLoopGetMain())
            #endif
        }
    }

    /// Poll for the next Lambda event (internal)
    private func next() {
        if let handler = eventHandler, isRunning {
            logger?.debug("Requesting next event from runtime")
            request(
                method: "GET",
                path: "2018-06-01/runtime/invocation/next",
                body: nil,
                headers: [:]
            ) { res, err in
                if let r = res,
                   let requestId = r.headers["Lambda-Runtime-Aws-Request-Id".lowercased()] {
                    let payload = LambdaPayload(body: r.body, headers: r.headers)
                    let event = LambdaEvent(requestId: requestId, payload: payload, runTime: self)
                    handler.handleEvent(event)
                } else {
                    // Log why we're retrying
                    if let r = res {
                        self.logger?.warning("Received response without request ID header. Available headers: \(r.headers.keys.joined(separator: ", "))")
                    }
                    if let err = err {
                        self.logger?.error("Event polling failed: \(err.localizedDescription)")
                    }
                    self.next()
                }
            }
        }
    }
    
    /// Send a successful response to the Runtime API
    ///
    /// Posts the response data to the Lambda Runtime API and polls for
    /// the next event.
    ///
    /// - Parameters:
    ///   - requestId: The request ID to respond to
    ///   - data: Response data to return to Lambda
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

    /// Report an initialization error to the Runtime API
    ///
    /// Posts an error to the Lambda Runtime API indicating the handler
    /// failed during initialization. Stops the runtime after reporting.
    ///
    /// - Parameter error: The initialization error details
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

    /// Report an invocation error to the Runtime API
    ///
    /// Posts an error to the Lambda Runtime API indicating the handler
    /// failed during event processing. Continues polling for new events.
    ///
    /// - Parameters:
    ///   - requestId: The request ID that failed
    ///   - error: The invocation error details
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
        httpClient.request(
            method: method,
            path: path,
            body: body,
            headers: headers,
            runtimeAPI: runtimeAPI,
            callback: callback
        )
    }
    
}
