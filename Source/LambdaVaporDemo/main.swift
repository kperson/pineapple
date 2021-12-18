import Vapor
import LambdaVapor
import LambdaApp
import LambdaRuntimeAPI
import LambdaApiGateway

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

//try app.run()

let gatewayAdapater = LambdaVaporServer.gatewayFrom(application: app)
lambdaApp.addHandler("com.kperson.http", gatewayAdapater)
lambdaApp.runtime.start()
