import Vapor

import Foundation
import SotoDynamoDB
import LambdaRuntimeAPI
import LambdaRemoteClient

public class App {
    
    let app: Vapor.Application
    let repo: LambdaEventRepo
    
    public init(vaporApp app: Vapor.Application, dynamo: DynamoDB, port: Int, table: String) {
        self.app = app
        self.repo = LambdaEventRepo(dynamoDB: dynamo, table: table)
        self.app.http.server.configuration.port = port
    }
    
    public func configureRoutes() {
        app.get(":namespaceKey", "2018-06-01", "runtime", "invocation", "next") { req async throws -> Response in
            let namespaceKey = try req.parameters.require("namespaceKey")
            // fetch event
            let nextOpt = try await self.retry {
                try await self.repo.getNext(namespaceKey: namespaceKey)
            }
            guard let next = nextOpt else { throw Abort(.notFound) }
            
            // create raw response
            var headers = HTTPHeaders()
            for (headerKey, headerValue) in next.request.headers {
                headers.add(name: headerKey, value: headerValue)
            }
            if !headers.contains(name: "Lambda-Runtime-Aws-Request-Id") {
                headers.remove(name: "Lambda-Runtime-Aws-Request-Id")
            }
            headers.add(name: "Lambda-Runtime-Aws-Request-Id", value: next.requestId)
            
            return Response(status: .ok, version: .http1_1, headers: headers, body: .init(data: next.request.body))
        }

        app.post(":namespaceKey", "2018-06-01", "runtime", "invocation", ":requestId", "response") { req async throws -> Response in
            let namespaceKey = try req.parameters.require("namespaceKey")
            let requestId = try req.parameters.require("requestId")
            
            // fetch event
            guard let event = try await self.repo.getByRequestId(requestId: requestId) else { throw Abort(.notFound) }
            
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
            try await self.repo.save(event: newEvent)
            return Response.noContent
        }

        app.post(":namespaceKey", "2018-06-01", "runtime", "invocation", ":requestId", "error") { req async throws -> Response in
            let namespaceKey = try req.parameters.require("namespaceKey")
            let requestId = try req.parameters.require("requestId")
            
            // fetch event
            guard let event = try await self.repo.getByRequestId(requestId: requestId) else {
                throw Abort(.notFound)
            }
            
            // ensure namespace matches
            guard event.namespaceKey == namespaceKey else { throw Abort(.notFound) }
            
            // retrieve error
            let error = try req.content.decode(
                LambdaError.self,
                using: ContentConfiguration.global.requireDecoder(for: HTTPMediaType.json)
            )

            // create a new event
            let newEvent = event.copy {
                $0.response = .invocationError(error: error)
            }
            
            // save and complete response
            try await self.repo.save(event: newEvent)
            return Response.noContent
        }

        app.post(":namespaceKey", "2018-06-01", "runtime", "init", "error") { req async throws -> Response in
            let namespaceKey = try req.parameters.require("namespaceKey")
            
            // fetch event
            guard let event = try await self.repo.getNext(namespaceKey: namespaceKey) else { throw Abort(.notFound) }
            
            // ensure namespace matches
            guard event.namespaceKey == namespaceKey else { throw Abort(.notFound) }
            
            // retrieve error
            let error = try req.content.decode(
                LambdaError.self,
                using: ContentConfiguration.global.requireDecoder(for: HTTPMediaType.json)
            )

            // create a new event
            let newEvent = event.copy {
                $0.response = .initializationError(error: error)
            }
            
            // save and complete response
            try await self.repo.save(event: newEvent)
            return Response.noContent
        }

        app.get("event", ":requestId") { req async throws -> LambdaRemoteEvent in
            let requestId = try req.parameters.require("requestId")
            guard let event = try await self.repo.getByRequestId(requestId: requestId) else {
                throw Abort(.notFound)
            }
            return event
        }

        app.post("event") { req async throws -> LambdaRemoteEvent in
            // submit an event to be processed
            let expiresAt = Int64(Date().timeIntervalSince1970 + 60 * 15) // 15 minutes
            let post = try req.content.decode(LambdaRemoteEventPost.self)
            let payloadCreatedAt = Int64(Date().timeIntervalSince1970)
            let event = LambdaRemoteEvent(
                requestId: post.requestId,
                namespaceKey: post.namespaceKey,
                payloadCreatedAt: payloadCreatedAt,
                request: post.request,
                response: nil,
                expiresAt: expiresAt
            )
            try await self.repo.save(event: event)
            return event
        }

        app.delete("event", ":requestId") { req async throws -> Response in
            let requestId = try req.parameters.require("requestId")
            guard try await self.repo.delete(requestId: requestId) else { throw Abort(.notFound) }
            return Response.noContent
        }
    }
    
    // partially applied so margic numbers aren't all over the place
    func retry<T>(
        _ f: () async throws -> T?) async rethrows -> T? {
        return try await Async.retryOptional(seconds: 0.5, delayIncrease: 1.1, maxAttempts: 14, f)
    }

    
}

extension Response {
    
    public static let noContent: Response = Response(
        status: .noContent,
        version: .http1_1,
        headers: HTTPHeaders(),
        body: .init(string: "")
    )

}

struct LambdaRemoteEventPost: Content {

    let namespaceKey: String
    let request: LambdaRemoteRequest
    let requestId: String
    
}

extension LambdaRemoteEvent: Content {}
