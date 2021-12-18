import Foundation

public struct LambdaPathParameters: Codable {
    
    let proxy: String?
    
}

public struct LambdaHTTPRequestBuilder: Codable {

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
    
    func build() -> LambdaHTTPRequest {
        let finalBody = body.flatMap { b in
            isBase64Encoded
            ? Data(base64Encoded: b)
            : b.data(using: .utf8)
        } ?? Data()
        return LambdaHTTPRequest(
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

public struct LambdaHTTPRequest {

    public let httpMethod: String
    public let path: String
    
    public let headers: [String : String]
    public let multiValueHeaders: [String : [String]]
    
    public let body: Data
    public let queryStringParameters: [String : String]
    public let multiValueQueryStringParameters: [String : [String]]
    
}
