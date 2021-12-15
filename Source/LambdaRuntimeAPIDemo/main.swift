import LambdaRuntimeAPI
import Foundation

// Demo of using runtime API client
class App: LambdaEventHandler, LambdaRuntimeLogHandler {
    
    let runtime = LambdaRuntime()
    
    init() {
        runtime.eventHandler = self
        runtime.logHandler = self
    }
    
    // MARK: LambdaEventHandler
    func handleEvent(_ event: LambdaEvent) {
        event.sendResponse(data: [
            "statusCode": 200,
            "body": "<p>Hola</p>",
            "headers": ["Content-Type": "text/html"]
        ])
    }
    
    // MARK: LambdaRuntimeLogHandler
    func handleRuntimeLog(_ log: LambdaLogEvent) {
        print("Log Event: \(log)")
    }
    
}


print("starting")
let app = App()
app.runtime.start()
