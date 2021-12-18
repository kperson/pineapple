import Foundation
import LambdaRuntimeAPI

public protocol LambdaAppEventHandler {
    
    func handleEvent(_ event: LambdaEvent) -> Void
    
}

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
    
    public let runtime = LambdaRuntime()
    private let handlerKeyResolver: (LambdaEvent) -> String?
    private var handlers: [String : (LambdaEvent) -> Void] = [:]
    private var internalLogHandler: LambdaRuntimeLogHandlerWrapper?
    
    public init(_ resolveHandler: @escaping (LambdaEvent) -> String?) {
        self.handlerKeyResolver = resolveHandler
        runtime.eventHandler = self
    }
    
    convenience public init(enviromentVariable: String = "_HANDLER") {
        self.init { _ in
            ProcessInfo.processInfo.environment[enviromentVariable]
        }
    }
    
    convenience public init(singleHandler: @escaping (LambdaEvent) -> Void) {
        let defaultKey = "_DEFAULT_HANDLER_LAMBDA_APP_SWIFT"
        self.init { _ in
            defaultKey
        }
        handlers[defaultKey] = singleHandler
    }
    
    convenience public init(singleHandler: LambdaAppEventHandler) {
        self.init(singleHandler: singleHandler.handleEvent)
    }
    
    public func addHandler(_ handlerKey: String, _ handler: @escaping (LambdaEvent) -> Void) {
        handlers[handlerKey] = handler
    }
    
    public func addHandler(_ handlerKey: String, _ handler: LambdaAppEventHandler) {
        addHandler(handlerKey, handler.handleEvent)
    }
    
    public func removeHandler(_ handlerKey: String) {
        handlers.removeValue(forKey: handlerKey)
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
