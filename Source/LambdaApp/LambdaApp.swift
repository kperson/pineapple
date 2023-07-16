import Foundation
import LambdaRuntimeAPI

public protocol LambdaAppEventHandler {
    
    func handleEvent(_ event: LambdaEvent) -> Void
    
}

public enum LambdaResponse: Codable, Equatable {
    
    public static let emptyResponse: LambdaResponse = .response(payload: .init(body: "{}".data(using: .utf8)!))
    
    case response(payload: LambdaSuccessPayload)
    case invocationError(error: LambdaError)
    case initializationError(error: LambdaError)

}

/**
 LambdaApp is a collection of event handlers for a give project.
 For exammple, you could have a event handler for SQL, API Gateway, and a Dynamo stream.
 All of these handlers would be store in the LambdaApp.
 The LambdaApp decides which handler to invoke based off the execution parameters, such as environment variables.
 */
public class LambdaApp: LambdaEventHandler {
    
    private class LambdaRuntimeLogHandlerWrapper: LambdaRuntimeLogHandler {
  
        let handler: (LambdaLogEvent) -> Void
        
        init(_ handler: @escaping (LambdaLogEvent) -> Void) {
            self.handler = handler
        }
        
        func handleRuntimeLog(_ log: LambdaLogEvent) {
            handler(log)
        }
        
    }
    
    public final var runtime: Runtime
    private let handlerKeyResolver: (LambdaEvent) -> String?
    private var handlers: [String : (LambdaEvent) -> Void] = [:]
    private var internalLogHandler: LambdaRuntimeLogHandlerWrapper?
    
    public init(runtime: Runtime = LambdaRuntime(), _ resolveHandler: @escaping (LambdaEvent) -> String?) {
        self.handlerKeyResolver = resolveHandler
        self.runtime = runtime
        self.runtime.eventHandler = self
    }
    
    convenience public init(
        runtime: Runtime = LambdaRuntime(),
        enviromentVariable: String = "_HANDLER"
    ) {
        self.init(runtime: runtime) { _ in
            ProcessInfo.processInfo.environment[enviromentVariable]
        }
    }
    
    convenience public init(runtime: Runtime = LambdaRuntime(), _ singleHandler: @escaping (LambdaEvent) -> Void) {
        let defaultKey = "_DEFAULT_HANDLER_LAMBDA_APP_SWIFT"
        self.init(runtime: runtime) { _ in
            defaultKey
        }
        handlers[defaultKey] = singleHandler
    }
    
    convenience public init(runtime: Runtime = LambdaRuntime(), singleHandler: LambdaAppEventHandler) {
        self.init(runtime: runtime, singleHandler.handleEvent)
    }
    
    public func addHandler(_ handlerKey: CustomStringConvertible, _ handler: @escaping (LambdaEvent) -> Void) {
        handlers[String(describing: handlerKey)] = handler
    }
    
    public func addAsyncHandler(_ handlerKey: CustomStringConvertible, _ handler: @escaping (LambdaEvent) async throws -> LambdaResponse) {
        let lambdaHandler: (LambdaEvent) -> Void = { event in
            Task {
                let result = try await handler(event)
                switch result {
                case .response(payload: let r): event.sendResponse(data: r.body)
                case .invocationError(error: let err): event.sendInvocationError(error: err)
                case .initializationError(error: let err): event.sendInitializationError(error: err)
                }
                
            }
        }
        handlers[String(describing: handlerKey)] = lambdaHandler
    }
    
    public func addHandler(_ handlerKey: CustomStringConvertible, _ handler: LambdaAppEventHandler) {
        addHandler(String(describing: handlerKey), handler.handleEvent)
    }
    
    public func removeHandler(_ handlerKey: CustomStringConvertible) {
        handlers.removeValue(forKey: String(describing: handlerKey))
    }
    
    public func setRunTimeLogHandler(_ handler: LambdaRuntimeLogHandler) {
        runtime.logHandler = handler
    }
    
    public func setRunTimeLogHandler(_ handler: @escaping (LambdaLogEvent) -> Void) {
        internalLogHandler = LambdaRuntimeLogHandlerWrapper(handler)
        runtime.logHandler = internalLogHandler
    }
    
    // MARK: LambdaEventHandler
    public func handleEvent(_ event: LambdaEvent) {
        if let k = handlerKeyResolver(event) {
            if let h = handlers[k] {
                h(event)
            }
            else {
                let error = LambdaError(
                    errorMessage: "Unable to initialize handler for '\(k)'",
                    errorType: "Runtime.NoSuchHandler"
                )
                event.sendInitializationError(error: error)
            }
        }
        else {
            let error = LambdaError(
                errorMessage: "Unable to initialize handler, unable to determine handler key",
                errorType: "Runtime.NoSuchHandler"
            )
            event.sendInitializationError(error: error)
        }
    }
    
}
