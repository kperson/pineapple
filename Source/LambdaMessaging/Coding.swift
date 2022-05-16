import Foundation
import LambdaApp

public protocol Encode {
    
    associatedtype In
    associatedtype Out
    
    func encode(input: In) throws -> Out
    
}

public class FuncEncode<In, Out>: Encode {

    let handler: (In) throws -> Out
    
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

    let handler: (In) throws -> Out
    
    public init(_ handler: @escaping (In) throws -> Out) {
        self.handler = handler
    }
    
    public func decode(input: In) throws -> Out {
        try handler(input)
    }
    
}

public class JSONEncode<In: Encodable>: Encode {
    
    public typealias Out = Data
    
    let encoder: JSONEncoder
        
    public init(encoder: JSONEncoder?) {
        self.encoder = encoder ?? JSONEncoder()
    }
    
    public func encode<In: Encodable>(input: In) throws -> Data  {
        try encoder.encode(input)
    }
    
}

public class JSONDecode<Out: Decodable>: Decode {
    
    public typealias In = Data
    
    let decoder: JSONDecoder
    
    public init(decoder: JSONDecoder?) {
        self.decoder = decoder ?? JSONDecoder()
    }
    
    public func decode(input: Data) throws -> Out {
        try decoder.decode(Out.self, from: input)
    }
    
}

class Demo {
    
    enum Topics: String, CustomStringConvertible {
        case strToInt
        case converToint
        var description: String {
            return rawValue
        }
    }
    
    enum Functions: String, CustomStringConvertible {
        case converToint
        case intReader
        
        var description: String {
            return rawValue
        }
    }
    
    
    func abc() {
        let awsApp = AWSApp()
        let pubSub = awsApp.awsI.pubSub

        let stringTopic = pubSub.managedTopic(.init(name: Topics.strToInt)) //new strings
        let intTopic = pubSub.managedTopic(.init(name: Topics.converToint)) //strings converted to int

        let intWriter = intTopic.writer(Int.self) //save as ints
                
        let stringToIntLambda = stringTopic.reader(String.self, lambdaName: Functions.converToint)
        let intPrintLambda = intTopic.reader(Int.self, lambdaName: Functions.intReader)
            
        stringToIntLambda.compactMap { str in Int(str) }.sink(write: intWriter)
        intPrintLambda.forEach { print($0) }
    }
    
}
