import Vapor
import LambdaVapor
import LambdaApp
import LambdaRuntimeAPI
import SotoDynamoDB
import Foundation
import LambdaRemoteClient

let enviroment = ProcessInfo.processInfo.environment

let client = AWSClient(
    credentialProvider: .default,
    httpClientProvider: .createNew
)
let dynamo = DynamoDB(client: client)
let app = try Application(.detect())

let table = enviroment["DYNAMO_TABLE"] ?? "lambda_proxy"
let proxyApp = LambdaRemoteAPI.App(vaporApp: app, dynamo: dynamo, port: 8080, table: table)
proxyApp.configureRoutes()

if enviroment["RUN_AS_LAMBDA"] == "1" {
    let gatewayAdapater = LambdaVaporServer.gatewayFrom(application: app)
    let lambdaApp = LambdaApp(singleHandler: gatewayAdapater)
    lambdaApp.runtime.start()
}
else {
    try app.run()
}
