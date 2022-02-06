import Vapor
import LambdaVapor
import LambdaApp
import LambdaRuntimeAPI
import LambdaApiGateway
import LambdaRemoteProxy

let enviroment = ProcessInfo.processInfo.environment
let shouldProxyRequest = enviroment["SHOULD_PROXY_REQUEST"] == "1"
let shouldRunAsLambda = enviroment["RUN_AS_LAMBDA"] == "1"

// Run this on AWS only, this just sends remote request to a local client
if let proxyApp = LambdaRemoteProxy.setupProxy(
    namespaceKey: enviroment["PROXY_NAMESPACE_KEY"],
    remoteAPIBaseURL: enviroment["PROXY_BASE_URL"]), shouldProxyRequest {
    proxyApp.runtime.start()
}
else {
    let lambdaApp = LambdaApp(enviromentVariable: "MY_HANDLER")
    let app = try Application(.detect())
    
    struct User: Content {
        let name: [String]
    }

    //form-data, x-www-form-urlencoded, json
    app.post("hello") { req -> User in
        return try req.content.decode(User.self)
    }

    //query params
    app.get("hello") { req -> User in
        let user = try req.query.decode(User.self)
        return user
    }

    if shouldRunAsLambda {
        let gatewayAdapater = LambdaVaporServer.gatewayFrom(application: app)
        lambdaApp.addHandler("com.kperson.http", gatewayAdapater)
        lambdaApp.runtime.start()
    }
    else {
        try app.run()
    }
}
