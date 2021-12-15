import Foundation
import LambdaRuntimeAPI

public protocol LambdaAppEventHandler {
    
    func handleEvent(_ event: LambdaEvent) -> Void
    
}

public class LambdaApp: LambdaEventHandler {
    
    public let runtime = LambdaRuntime()
    private let handlerKeyResolver: () -> String?
    private var handlers: [String : (LambdaEvent) -> Void] = [:]
    
    public init(_ resolveHandler: @escaping () -> String?) {
        self.handlerKeyResolver = resolveHandler
        runtime.eventHandler = self
    }
    
    convenience public init(enviromentVariable: String = "_HANDLER") {
        self.init {
            ProcessInfo.processInfo.environment[enviromentVariable]
        }
    }
    
    convenience public init(singleHandler: @escaping (LambdaEvent) -> Void) {
        let defaultKey = "_DEFAULT_HANDLER_LAMBDA_APP_SWIFT"
        self.init {
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
    
    // MARK: LambdaEventHandler
    public func handleEvent(_ event: LambdaEvent) {
        if let k = handlerKeyResolver() {
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
