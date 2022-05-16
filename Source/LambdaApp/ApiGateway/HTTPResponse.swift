import Foundation

public struct HTTPResponse: Codable {
    
    let statusCode: Int
    let body: Data
    let headers: [String : String]
    let multiValueHeaders: [String : [String]]
    let isBase64Encoded: Bool
    
    public init(
        statusCode: Int,
        body: Data? = nil,
        headers: [String : String] = [:],
        multiValueHeaders: [String : [String]] = [:],
        isBase64Encoded: Bool = true
    ) {
        self.statusCode = statusCode
        self.body = body ?? Data()
        self.headers = headers
        self.multiValueHeaders = multiValueHeaders
        self.isBase64Encoded = isBase64Encoded
    }
    
}
