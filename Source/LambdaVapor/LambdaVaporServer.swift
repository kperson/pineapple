import Foundation
import Vapor
import LambdaApp
import LambdaRuntimeAPI

public class LambdaVaporServer: Server, LambdaAppEventHandler {
 
    private let application: Application
    private var shutdownPromise: EventLoopPromise<Void>
    private let responder: Responder
    static let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    
    public init(application: Application) {
        self.application = application
        self.responder = self.application.responder.current
        self.shutdownPromise = LambdaVaporServer.group.next().makePromise(of: Void.self)
    }
    
    // MARK: Server
    
    public func start(address: BindAddress?) throws {
        // this function does really matter for lambdas
    }
        
    public func shutdown() {
        // this function does really matter for lambdas
        shutdownPromise.completeWith(.success(Void()))
    }
    
    public var onShutdown: EventLoopFuture<Void> {
        return self.shutdownPromise.futureResult
    }
        
    // MARK: LambdaAppEventHandler
    
    public func handleEvent(_ event: LambdaEvent) {
        print(String(data: event.payload.body, encoding: .utf8) ?? "")
        event.sendResponse(data: [
            "statusCode": 200,
            "body": "{}",
            "headers": ["Content-Type" : "application/json"]
        ])
    }
    
}
