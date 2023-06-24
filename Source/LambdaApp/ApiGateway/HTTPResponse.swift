import Foundation

public struct HTTPResponse {
    
    public enum Body {
        case string(_ value: String)
        case data(_ value: Data)
    }
    
    let statusCode: Int
    let body: Body
    let headers: [String : String]
    let multiValueHeaders: [String : [String]]
    
    public init(
        statusCode: Int,
        body: Body = .data(Data()),
        headers: [String : String] = [:],
        multiValueHeaders: [String : [String]] = [:]
    ) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
        self.multiValueHeaders = multiValueHeaders
    }
    
}
