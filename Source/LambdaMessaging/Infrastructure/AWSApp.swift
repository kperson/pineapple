import Foundation
import LambdaApp
import SotoCore


public class AWSApp {
    
    public let app: LambdaApp
    public let awsI: AWSI
    
    public init(
        app: LambdaApp = LambdaApp(),
        client: AWSClient = AWSClient(httpClientProvider: .createNew)
    ) {
        self.app = app
        self.awsI = AWSI(app: app)
    }
    
    private func generateInfrastructure() {
        //TODO, pass instruction set to instrution executer
    }
    
    private func startApp() {
        app.runtime.start()
    }
    
    public func run() {
        if let gen = ProcessInfo.processInfo.environment["GENERATE_INFRASTRUCTURE"], gen == "1" {
            generateInfrastructure()
        }
        else {
            startApp()
        }
    }
    
}
