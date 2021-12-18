import Vapor
import LambdaVapor
import LambdaApp
import LambdaRuntimeAPI
import LambdaApiGateway
import SotoDynamoDB

let lambdaApp = LambdaApp(enviromentVariable: "MY_HANDLER")
let app = try Application(.detect())


//query params
app.get(":key", "2018-06-01", "runtime", "invocation", "next") { req -> String in
    let namespaceKey = req.parameters.get("key")!
    return namespaceKey
}

app.post(":key", "2018-06-01", "runtime", "invocation", ":requestId", "response") { req -> String in
    let namespaceKey = req.parameters.get("key")!
    let requestId = req.parameters.get("requestId")!
    return namespaceKey
}

app.post(":key", "2018-06-01", "runtime", "init", "error") { req -> String in
    let namespaceKey = req.parameters.get("key")!
    return namespaceKey
}

try app.run()

//let gatewayAdapater = LambdaVaporServer.gatewayFrom(application: app)
//lambdaApp.addHandler("com.kperson.http", gatewayAdapater)
//lambdaApp.runtime.start()
