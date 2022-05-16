import Foundation
import LambdaApp
import SotoSNS

public class AWSI {
    

    
    public struct Context {
        public let app: LambdaApp
        public let nameResolver: NameResolver
        public let envNameGenerator: EnvNameGenerator
        public let cloudBuilder: CloudBuilder
        public let sns: SNS
        
        init(
            app: LambdaApp,
            nameResolver: NameResolver,
            envNameGenerator: EnvNameGenerator,
            cloudBuilder: CloudBuilder,
            sns: SNS
        ) {
            self.app = app
            self.nameResolver = nameResolver
            self.envNameGenerator = envNameGenerator
            self.cloudBuilder = cloudBuilder
            self.sns = sns
        }
    }
    
    public let app: LambdaApp
    public let pubSub: PubSub
    public let nameResolver: NameResolver = NameResolver()
    public let envNameGenerator: EnvNameGenerator = EnvNameGenerator()
    public let client: AWSClient
    public let context: Context
    public let cloudBuilder = CloudBuilder()
        
    public init(
        app: LambdaApp,
        client: AWSClient = AWSClient(httpClientProvider: .createNew)
    ) {
        self.app = app
        self.client = client
        self.context = Context(
            app: app,
            nameResolver: nameResolver,
            envNameGenerator: envNameGenerator,
            cloudBuilder: cloudBuilder,
            sns: SNS(client: self.client)
        )
        self.pubSub = PubSub(context: context)
        
    }
        
}
