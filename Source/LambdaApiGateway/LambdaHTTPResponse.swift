import Foundation

public struct LambdaHTTPResponse {
    
    let statusCode: Int
    let body: Data
    let headers: [String : String]
    let multiValueHeaders: [String : [String]]
    
    public init(
        statusCode: Int,
        body: Data?,
        headers: [String : String] = [:],
        multiValueHeaders: [String : [String]] = [:]
    ) {
        self.statusCode = statusCode
        self.body = body ?? Data()
        self.headers = headers
        self.multiValueHeaders = multiValueHeaders
    }
    
}
