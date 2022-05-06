import Foundation
import Vapor
import LambdaApp
import NIOPosix

extension HTTPRequest {
    
    func vaporRequest(
        eventLoopGroup: EventLoopGroup,
        application: Vapor.Application
    ) -> Request {
        
        let method: HTTPMethod
        switch httpMethod.lowercased() {
        case "get":
            method = HTTPMethod.GET
        case "post":
            method = HTTPMethod.POST
        case "patch":
            method = HTTPMethod.PATCH
        case "put":
            method = HTTPMethod.PUT
        case "options":
            method = HTTPMethod.OPTIONS
        case "head":
            method = HTTPMethod.HEAD
        case "delete":
            method = HTTPMethod.DELETE
        case "connect":
            method = HTTPMethod.CONNECT
        case "acl":
            method = HTTPMethod.ACL
        case "trace":
            method = HTTPMethod.TRACE
        default:
            method = HTTPMethod.RAW(value: httpMethod.uppercased())
        }
        
        var vaporHeaders = HTTPHeaders()
        for (k, v) in headers {
            if multiValueHeaders[k] == nil {
                vaporHeaders.add(name: k, value: v)
            }
        }
        for (k, l) in multiValueHeaders {
            l.forEach {
                vaporHeaders.add(name: k, value: $0)
            }
        }
        
        var c = URLComponents()
        c.host = "localhost"
        c.path = path
        c.scheme = "http"
        c.port = 8080
        
        var qItems: [URLQueryItem] = []
        for (k, v) in queryStringParameters {
            if multiValueQueryStringParameters[k] == nil {
                qItems.append(URLQueryItem(name: k, value: v))
            }
        }
        for (k, l) in multiValueQueryStringParameters {
            l.forEach {
                qItems.append(URLQueryItem(name: k, value: $0))
            }
        }
        if !qItems.isEmpty {
            c.queryItems = qItems
        }
    
        let uri = URI(
            scheme: .http,
            host: c.host,
            port: c.port,
            path: c.path,
            query: c.percentEncodedQuery,
            fragment: nil
        )
        
        return Request(
            application: application,
            method: method,
            url: uri,
            version: .init(major: 1, minor: 1),
            headers: vaporHeaders,
            collectedBody: ByteBuffer(data: body),
            on: eventLoopGroup.next()
        )
    }
    
}

// TODO: move this to a new project, Vapor is not part of the core
public class LambdaVaporServer: Server, ApiGatewayHandler {
 
    private let application: Application
    private var shutdownPromise: EventLoopPromise<Void>
    private let responder: Responder
    static let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    
    public init(application: Application) {
        self.application = application
        self.responder = self.application.responder.current
        self.shutdownPromise = LambdaVaporServer.group.next().makePromise(of: Void.self)
    }
    
    public static func gatewayFrom(application: Application) -> ApiGatewayEventHandler {
        return ApiGatewayEventHandler(LambdaVaporServer(application: application))
    }
    
    // MARK: Server
    
    public func start(address: BindAddress?) throws {
        // this function does really matter for lambdas
    }
        
    public func shutdown() {
        // this function does really matter for lambdas
        shutdownPromise.completeWith(.success(Void()))
    }
    
    public var onShutdown: EventLoopFuture<Void> {
        return self.shutdownPromise.futureResult
    }
        
    // MARK: LambdaApiGatewayHandler
    
    public func handleRequest(_ requestEvent: HTTPRequest) async throws -> HTTPResponse {
        let vaporRequest = requestEvent.vaporRequest(
            eventLoopGroup: Self.group,
            application: application
        )
        let future = responder.respond(to: vaporRequest)
        return try await withUnsafeThrowingContinuation { cont in
            future.whenSuccess { response in
                cont.resume(returning: response.toLambdaResponse)
            }
            future.whenFailure { err in
                cont.resume(throwing: err)
            }
        }
    
    }
}


extension Response {
    
    var toLambdaResponse: HTTPResponse {
        var h: [String : [String]] = [:]
        for (k, v) in headers {
            if let l = h[k] {
                h[k] = l + [v]
            }
            else {
                h[k] = [v]
            }
        }
        var sHeaders: [String : String] = [:]
        var mHeaders: [String : [String]] = [:]
        for (k, v) in h {
            if v.count == 1 {
                sHeaders[k] = v[0]
            }
            else {
                mHeaders[k] = v
            }
        }
        
        return HTTPResponse(
            statusCode: Int(status.code),
            body: body.data,
            headers: sHeaders,
            multiValueHeaders: mHeaders
        )
    }
}
