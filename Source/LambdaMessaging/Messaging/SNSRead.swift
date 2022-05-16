import Foundation
import LambdaApp
import Messaging


public class SNSRead<In>: Read {

    public let app: LambdaApp
    public let functionName: String
    private let decodeFunc: (Data) throws -> In
    
    public init<D: Decode>(
        app: LambdaApp,
        functionName: String,
        decode: D
    ) where D.In == Data, D.Out == In {
        self.app = app
        self.functionName = functionName
        self.decodeFunc = {
            try decode.decode(input: $0)
        }
    }
    
    public func forEach(_ handler: @escaping (In) async throws -> Void) {
        app.addSNSBodyHandler(functionName) { records in
            for r in records {
                if let data = r.message.data(using: .utf8) {
                    let item = try self.decodeFunc(data)
                    try await handler(item)
                }
            }
        }
    }
}

public extension SNSRead {
    
    convenience init(app: LambdaApp, functionName: String) where In: Decodable {
        self.init(app: app, functionName: functionName, decode: JSONDecode(decoder: JSONDecoder()))
    }
    
}
