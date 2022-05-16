import Foundation
import LambdaApp
import SotoSNS


public protocol AWSContext: AnyObject {
    var app: LambdaApp { get }
    var nameResolver: NameResolver { get }
    var envNameGenerator: EnvNameGenerator { get }
    var cloudBuilder: CloudBuilder { get }
    var sns: SNS { get }
}

public class AWSI: AWSContext {
        
    public let app: LambdaApp
    public let nameResolver: NameResolver = NameResolver()
    public let envNameGenerator: EnvNameGenerator = EnvNameGenerator()
    public let client: AWSClient
    public let cloudBuilder = CloudBuilder()
        
    public init(
        app: LambdaApp,
        client: AWSClient = AWSClient(httpClientProvider: .createNew)
    ) {
        self.app = app
        self.client = client
    }
    
    public lazy var pubSub: PubSub = {
        return PubSub(context: self)
    }()
    
    public lazy var sns: SNS = {
        return SNS(client: self.client)
    }()
            
}
