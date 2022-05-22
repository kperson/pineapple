import Foundation
import LambdaApp

public protocol Encode {
    
    associatedtype In
    associatedtype Out
    
    func encode(input: In) throws -> Out
    
}

public class FuncEncode<In, Out>: Encode {

    private let handler: (In) throws -> Out
    
    public init(_ handler: @escaping (In) throws -> Out) {
        self.handler = handler
    }
    
    public func encode(input: In) throws -> Out {
        try handler(input)
    }
    
}

public protocol Decode {
    
    associatedtype In
    associatedtype Out
    
    func decode(input: In) throws -> Out
    
}

public class FuncDecode<In, Out>: Decode {

    private let handler: (In) throws -> Out
    
    public init(_ handler: @escaping (In) throws -> Out) {
        self.handler = handler
    }
    
    public func decode(input: In) throws -> Out {
        try handler(input)
    }
    
}

public class JSONEncode<In: Encodable>: Encode {
    
    public typealias Out = Data
    
    private let encoder: JSONEncoder
        
    public init(encoder: JSONEncoder?) {
        self.encoder = encoder ?? JSONEncoder()
    }
    
    public func encode<In: Encodable>(input: In) throws -> Data  {
        try encoder.encode(input)
    }
    
}

public class JSONDecode<Out: Decodable>: Decode {
    
    public typealias In = Data
    
    private let decoder: JSONDecoder
    
    public init(decoder: JSONDecoder?) {
        self.decoder = decoder ?? JSONDecoder()
    }
    
    public func decode(input: Data) throws -> Out {
        try decoder.decode(Out.self, from: input)
    }
    
}
