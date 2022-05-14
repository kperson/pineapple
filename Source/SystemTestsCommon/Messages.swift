import Foundation



public struct DemoMessage: Codable, Equatable {
    
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
    
    public let testRunKey: String
    public let message: String
    
    
    public init(jsonData: Data) throws {
        let tmp = try Self.decoder.decode(Self.self, from: jsonData)
        self.testRunKey = tmp.testRunKey
        self.message = tmp.message
    }

    public init(jsonStr: String) throws {
        try self.init(jsonData: jsonStr.data(using: .utf8)!)
    }
    
    public init(testRunKey: String, message: String) {
        self.testRunKey = testRunKey
        self.message = message
    }
    
    public func jsonData() throws -> Data {
        return try Self.encoder.encode(self)
    }
    
    public func jsonStr() throws -> String {
        return try String(data: jsonData(), encoding: .utf8)!
    }
    
}
