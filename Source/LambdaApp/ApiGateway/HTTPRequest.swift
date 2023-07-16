import Foundation

public struct LambdaPathParameters: Codable, Equatable {
    
    let proxy: String?
    
}

public struct LambdaHTTPRequestBuilder: Codable, Equatable {

    public let httpMethod: String
    public let pathParameters: LambdaPathParameters
    public let isBase64Encoded: Bool
    
    public let headers: [String : String]?
    public let multiValueHeaders: [String : [String]]?
    
    public let body: String?
    public let queryStringParameters: [String : String]?
    public let multiValueQueryStringParameters: [String : [String]]?
    
    public var path: String {
        let p = pathParameters.proxy ?? ""
        return p.starts(with: "/") ? p : "/\(p)"
    }
    
    func build() -> HTTPRequest {
        let finalBody = body.flatMap { b in
            isBase64Encoded
            ? Data(base64Encoded: b)
            : b.data(using: .utf8)
        } ?? Data()
        return HTTPRequest(
            httpMethod: httpMethod,
            path: path,
            headers: headers ?? [:],
            multiValueHeaders: multiValueHeaders ?? [:],
            body: finalBody,
            queryStringParameters: queryStringParameters ?? [:],
            multiValueQueryStringParameters: multiValueQueryStringParameters ?? [:]
        )
    }
    
}

public struct HTTPRequest: Codable, Equatable {

    public let httpMethod: String
    public let path: String
    
    public let headers: [String : String]
    public let multiValueHeaders: [String : [String]]
    
    public let body: Data
    public let queryStringParameters: [String : String]
    public let multiValueQueryStringParameters: [String : [String]]
    
    public init(
        httpMethod: String,
        path: String,
        headers: [String : String],
        multiValueHeaders: [String : [String]],
        body: Data,
        queryStringParameters: [String : String],
        multiValueQueryStringParameters: [String : [String]]
    ) {
        self.httpMethod = httpMethod
        self.path = path
        self.headers = headers
        self.multiValueHeaders = multiValueHeaders
        self.body = body
        self.queryStringParameters = queryStringParameters
        self.multiValueQueryStringParameters = multiValueQueryStringParameters
    }
    
}
