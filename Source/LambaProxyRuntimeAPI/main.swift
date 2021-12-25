import Vapor
import LambdaVapor
import LambdaApp
import LambdaRuntimeAPI
import LambdaApiGateway
import SotoDynamoDB

//let app = try Application(.detect())
//
//let client = AWSClient(httpClientProvider: .createNew)
//let dynamo = DynamoDB(client: client, endpoint: "http://localhost:8000")
//let tables = dynamo.listTables(.init(exclusiveStartTableName: nil, limit: 10))
//try print(tables.wait())




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

app.post(":key", "2018-06-01", "runtime", "invocation", ":requestId", "error") { req -> String in
    let namespaceKey = req.parameters.get("key")!
    let requestId = req.parameters.get("requestId")!
    return namespaceKey
}

app.post(":key", "2018-06-01", "runtime", "init", "error") { req -> String in
    let namespaceKey = req.parameters.get("key")!
    return namespaceKey
}

try app.run()


let gatewayAdapater = LambdaVaporServer.gatewayFrom(application: app)
let lambdaApp = LambdaApp(singleHandler: gatewayAdapater)
lambdaApp.runtime.start()
