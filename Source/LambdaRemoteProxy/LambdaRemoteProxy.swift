import Foundation
import LambdaApp
import LambdaRuntimeAPI
import LambdaRemoteClient

public class LambdaRemoteProxy {
    
    public class func setupProxy(
        namespaceKey: String?,
        remoteAPIBaseURL: String?
    ) -> LambdaApp? {
        if let n = namespaceKey, let r = remoteAPIBaseURL {
            return createLambdaApp(namespaceKey: n, remoteAPIBaseURL: r)
        }
        return nil
    }
    
    public class func createLambdaApp(namespaceKey: String, remoteAPIBaseURL: String) -> LambdaApp {
        let client = LambdaRemoteClient(baseURL: remoteAPIBaseURL)
        return LambdaApp { (event: LambdaEvent) -> Void in
            let post = LambdaRemoteEventPost(
                namespaceKey: namespaceKey,
                request: event.payload,
                requestId: event.requestId
            )
            Task { 
                do {
                    let savedEvent = try await client.saveEvent(event: post)
                    let remoteEvent = try await client.getEvent(requestId: savedEvent.requestId, shouldLongPoll: true)
                    if let response = remoteEvent?.response {
                        switch response {
                        case .response(let payload):
                            event.sendResponse(data: payload.body)
                        case .invocationError(let error):
                            event.sendInvocationError(error: error)
                        case .initializationError(let error):
                            event.sendInitializationError(error: error)
                        }
                    }
                    else {
                        event.sendInvocationError(error: .init(errorMessage: "remote timeout"))
                    }
                }
                catch let error {
                    event.sendInvocationError(error: LambdaError(error: error))
                }
            }
        }
    }
    
}
