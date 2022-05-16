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

class Demo {
    
    enum Topics: String, CustomStringConvertible {
        case allStrings
        case stringsConvertedToInts
        
        var description: String {
            return rawValue
        }
    }
    
    enum Functions: String, CustomStringConvertible {
        case stringToInt
        case printInt
        case publishString
        
        var description: String {
            return rawValue
        }
    }
    
    func abc() {
        let awsApp = AWSApp()
        let pubSub = awsApp.awsI.pubSub

        let stringTopic = pubSub.managedTopic(.init(name: Topics.allStrings))
        let intTopic = pubSub.managedTopic(.init(name: Topics.stringsConvertedToInts))

        let stringWriter = stringTopic.writer(String.self)
        let intWriter = intTopic.writer(Int.self)
        let stringReader = stringTopic.reader(String.self, lambdaName: Functions.stringToInt)
        let intReader = intTopic.reader(Int.self, lambdaName: Functions.printInt)

        
        awsApp.app.addApiGateway(Functions.publishString) { request in
            if let str = String(data: request.body, encoding: .utf8) {
                try await stringWriter.write(value: str)
            }
            return HTTPResponse(statusCode: 204)
        }
        
        stringReader.compactMap { str in Int(str) }.sink(write: intWriter)
        intReader.forEach { print($0) }
    }
    
}
