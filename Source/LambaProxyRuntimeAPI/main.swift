import Vapor
import LambdaVapor
import LambdaApp
import LambdaRuntimeAPI
import LambdaApiGateway
import SotoDynamoDB
import Foundation

let app = try Application(.detect())

let client = AWSClient(
    credentialProvider: .default,
    httpClientProvider: .createNew
)

let dynamo = DynamoDB(client: client)
let repo = LambdaEventRepo(dynamoDB: dynamo, table: "default_lambda_proxy_events")

app.get(":namespaceKey", "2018-06-01", "runtime", "invocation", "next") { req async throws -> Response in
    let namespaceKey = try req.parameters.require("namespaceKey")
    // fetch event
    guard let next = try await repo.getNext(namespaceKey: namespaceKey) else { throw Abort(.notFound) }
    
    // create raw response
    var headers = HTTPHeaders()
    for (headerKey, headerValue) in next.request.headers {
        headers.add(name: headerKey, value: headerValue)
    }
    return Response(status: .ok, version: .http1_1, headers: headers, body: .init(data: next.request.body))
}

app.post(":namespaceKey", "2018-06-01", "runtime", "invocation", ":requestId", "response") { req async throws -> Response in
    let namespaceKey = try req.parameters.require("namespaceKey")
    let requestId = try req.parameters.require("requestId")
    
    // fetch event
    guard let event = try await repo.getByRequestId(requestId: requestId) else { throw Abort(.notFound) }
    
    // ensure namespace matches
    guard event.namespaceKey == namespaceKey else { throw Abort(.notFound) }
    
    // retrieve raw request body
    guard let byteBuffer = req.body.data else { throw Abort(.badRequest) }
    let lambdaData = Data(buffer: byteBuffer)
    
    // create a new event
    let newEvent = event.copy {
        $0.response = .response(payload: LambdaPayload(body: lambdaData, headers: [:]))
    }
    
    // save and complete response
    try await repo.save(event: newEvent)
    return Response.noContent
}

app.post(":namespaceKey", "2018-06-01", "runtime", "invocation", ":requestId", "error") { req async throws -> String in
    let namespaceKey = req.parameters.get("key")!
    let requestId = req.parameters.get("requestId")!
    print(requestId)
    return namespaceKey
}

app.post(":namespaceKey", "2018-06-01", "runtime", "init", "error") { req -> String in
    let namespaceKey = req.parameters.get("key")!
    return namespaceKey
}

extension Response {
    
    public static let noContent: Response = Response(
        status: .noContent,
        version: .http1_1,
        headers: HTTPHeaders(),
        body: .init(string: "")
    )
    
}

//app.post("event") { req -> String in
//    req.content.decode(<#T##D#>)
//    let namespaceKey = req.parameters.get("key")!
//    return namespaceKey
//}

try app.run()


//let gatewayAdapater = LambdaVaporServer.gatewayFrom(application: app)
//let lambdaApp = LambdaApp(singleHandler: gatewayAdapater)
//lambdaApp.runtime.start()
