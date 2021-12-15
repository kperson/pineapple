import Vapor
import LambdaVapor
import LambdaApp
import LambdaRuntimeAPI

let lambdaApp = LambdaApp(enviromentVariable: "MY_HANDLER")
let app = try Application(.detect())

app.get("hello") { req in
    return "Hello, world."
}

app.servers.use {
    let server = LambdaVaporServer(application: $0)
    lambdaApp.addHandler("com.kperson.http", server)
    return server
}
    
lambdaApp.runtime.start()
